part of 'task_store.dart';

/// Checklist persistence stays within the task command/ingestion transaction.
/// Domain membership/order and the native field adapter own their own meanings.
extension ChecklistStore on TaskStore {
  Future<LogEvent> addChecklistItem(
    String parent,
    String title, {
    String notes = '',
    String? before,
    String? id,
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(() async {
    await _refresh();
    if (textEngine == null) {
      throw FormatFailure('Native text support is unavailable.');
    }
    final value = title.trim();
    return _command(id ?? const Uuid().v4(), 'checklist.itemCreated', {
      'parent': parent,
      'title': value,
      'description': notes,
      'before': before,
      'text': {
        'codec': 'yrs-v1',
        'adapter': 1,
        'seeds': {
          'title': sha256.convert(textEngine!.seedText(value).bytes).toString(),
          'description': sha256
              .convert(textEngine!.seedText(notes).bytes)
              .toString(),
        },
      },
    }, onPrepared: onPrepared);
  });

  Future<LogEvent> setChecklistCompleted(
    String item,
    bool completed, {
    void Function(OperationReceipt)? onPrepared,
  }) => command(item, 'checklist.itemEdited', {
    'completed': completed,
  }, onPrepared: onPrepared);

  Future<LogEvent> moveChecklistItem(
    String item,
    String? before, {
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(
    () => _command(
      item,
      'checklist.itemMoved',
      {'before': before},
      canCommit: canCommit,
      onPrepared: onPrepared,
    ),
  );

  Future<LogEvent> deleteChecklistItem(
    String item, {
    void Function(OperationReceipt)? onPrepared,
  }) => command(item, 'checklist.itemDeleted', {}, onPrepared: onPrepared);

  List<Map<String, dynamic>> checklistItems(String parent) {
    final record = db.select('SELECT raw FROM ${tables.views} WHERE id=?', [
      parent,
    ]);
    if (record.isEmpty) return const [];
    final state = jsonDecode(record.single['raw'] as String) as Map;
    return (state['checklist'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  String checklistSnapshot(String parent) => jsonEncode(checklistItems(parent));

  /// The acknowledged native Save result includes items hidden from task rows.
  /// A missing result means the entity or its containing task is unavailable.
  Map<String, dynamic>? currentTextRow(String entity) {
    final records = db.select('SELECT raw FROM ${tables.views} WHERE id=?', [
      entity,
    ]);
    if (records.isEmpty) return null;
    final row =
        jsonDecode(records.single['raw'] as String) as Map<String, dynamic>;
    if (!{'task', 'checklistItem'}.contains(row['kind']) ||
        row['deleted'] == true ||
        row['successorSuppressed'] == true ||
        (row['kind'] == 'checklistItem' &&
            !_checklistParentAvailable(row['parent'] as String))) {
      return null;
    }
    return Map.unmodifiable(row);
  }

  bool _checklistParentAvailable(String id) {
    final parent = project(_entityEvents(id));
    if (parent == null ||
        parent['kind'] != 'task' ||
        parent['deleted'] == true) {
      return false;
    }
    _attachSuccessorSuppression(parent);
    return parent['successorSuppressed'] != true;
  }

  List<LogEvent> _checklistHistory(String parent) {
    final creations = db
        .select(
          "SELECT raw FROM ${tables.events} WHERE json_extract(raw,'\$.type')='checklist.itemCreated' AND json_extract(raw,'\$.data.parent')=?",
          [parent],
        )
        .map((row) => LogEvent.decode(row['raw'] as String))
        .toList();
    final copies = db
        .select(
          "SELECT raw FROM ${tables.events} WHERE json_extract(raw,'\$.type')='task.completedWithChecklist' AND json_extract(raw,'\$.data.successor.id')=?",
          [parent],
        )
        .map((row) => LogEvent.decode(row['raw'] as String))
        .toList();
    final ids = <String>{
      ...creations.map((event) => event.entity),
      for (final event in copies)
        for (final item in (event.data['checklist'] as Map)['items'] as List)
          (item as Map)['id'] as String,
    };
    return [
      ...copies,
      if (ids.isNotEmpty)
        ...db
            .select(
              'SELECT raw FROM ${tables.events} WHERE entity IN (${List.filled(ids.length, '?').join(',')})',
              ids.toList(),
            )
            .map((row) => LogEvent.decode(row['raw'] as String)),
    ];
  }

  List<(LogEvent, Map<String, dynamic>)> _itemCopySeeds(String entity) => db
      .select(
        "SELECT e.raw,i.value FROM ${tables.events} e JOIN json_each(json_extract(e.raw,'\$.data.checklist.items')) i WHERE json_extract(e.raw,'\$.type')='task.completedWithChecklist' AND json_extract(i.value,'\$.id')=? ORDER BY e.clock,e.writer,e.seq",
        [entity],
      )
      .map(
        (row) => (
          LogEvent.decode(row['raw'] as String),
          jsonDecode(row['value'] as String) as Map<String, dynamic>,
        ),
      )
      .toList();

  String? _checklistParent(String entity) {
    final own = db.select(
      "SELECT json_extract(raw,'\$.data.parent') AS parent FROM ${tables.events} WHERE entity=? AND json_extract(raw,'\$.type')='checklist.itemCreated'",
      [entity],
    );
    if (own.isNotEmpty) return own.first['parent'] as String;
    final copies = _itemCopySeeds(entity);
    return copies.isEmpty
        ? null
        : (copies.first.$1.data['successor'] as Map)['id'] as String;
  }

  void _attachChecklist(
    Map<String, dynamic> state, {
    RecurringTextResolver? resolution,
    TextCache? textCache,
  }) {
    if (state['kind'] != 'task') return;
    final history = _checklistHistory(state['id'] as String);
    if (history.isEmpty) return;
    final items = projectChecklist(history, state['id'] as String);
    resolution ??= items.any((item) => _hasInheritedText(item['id'] as String))
        ? _textResolution()
        : null;
    for (final item in items) {
      _materializeText(
        item,
        _entityEvents(item['id'] as String),
        resolution: resolution,
        textCache: textCache,
      );
    }
    state['checklist'] = items;
  }

  /// Durable descendant work protects its containing task. Merely materialized
  /// item seeds and private drafts do not fabricate canonical activity.
  bool _hasChecklistActivity(String parent) =>
      hasDurableChecklistActivity(_checklistHistory(parent), parent);

  void _validateChecklistReferences([LogEvent? pending]) {
    final references = db
        .select(
          "SELECT raw FROM ${tables.events} WHERE json_extract(raw,'\$.type') IN ('checklist.itemCreated','checklist.itemMoved')",
        )
        .map((row) => LogEvent.decode(row['raw'] as String))
        .toList();
    if (pending != null &&
        {
          'checklist.itemCreated',
          'checklist.itemMoved',
        }.contains(pending.type)) {
      references.add(pending);
    }
    Map<String, dynamic>? state(String id) =>
        project([..._entityEvents(id), if (pending?.entity == id) pending!]);
    for (final reference in references) {
      final owner = state(reference.entity);
      if (owner == null) continue;
      if (owner['kind'] != 'checklistItem') {
        throw FormatFailure(
          'Checklist operation references a non-item in ${reference.id}.',
        );
      }
      final parent = owner['parent'] as String;
      final parentState = state(parent);
      if (parentState != null && parentState['kind'] != 'task') {
        throw FormatFailure(
          'Checklist parent must be a task in ${reference.id}.',
        );
      }
      if (identical(reference, pending) && !_checklistParentAvailable(parent)) {
        throw FormatFailure('Choose an existing task for the checklist.');
      }
      final before = reference.data['before'];
      if (before == null) continue;
      final anchor = state(before as String);
      if (anchor != null &&
          (anchor['kind'] != 'checklistItem' || anchor['parent'] != parent)) {
        throw FormatFailure(
          'Checklist order anchor belongs to another parent in ${reference.id}.',
        );
      }
      if (identical(reference, pending) && anchor == null) {
        throw FormatFailure('Checklist order anchor is missing.');
      }
    }
    if (pending != null &&
        (pending.type.startsWith('checklist.') ||
            pending.type == 'task.textEdited')) {
      final owner = state(pending.entity);
      if (owner?['kind'] == 'checklistItem') {
        final parent = state(owner!['parent'] as String);
        if (!_checklistParentAvailable(owner['parent'] as String)) {
          throw FormatFailure('This checklist item’s task is unavailable.');
        }
        if (parent == null ||
            parent['kind'] != 'task' ||
            parent['deleted'] == true ||
            owner['deleted'] == true) {
          // Item deletion is evaluated against the pre-command owner below.
          if (pending.type != 'checklist.itemDeleted' ||
              project(_entityEvents(pending.entity))?['deleted'] == true ||
              parent == null ||
              parent['deleted'] == true) {
            throw FormatFailure(
              'This checklist item or its parent is unavailable.',
            );
          }
        }
      }
    }
  }

  void _validateChecklistCompletions([LogEvent? pending]) {
    final completions = db
        .select(
          "SELECT raw FROM ${tables.events} WHERE json_extract(raw,'\$.type')='task.completedWithChecklist'",
        )
        .map((row) => LogEvent.decode(row['raw'] as String))
        .toList();
    if (pending?.type == 'task.completedWithChecklist') {
      completions.add(pending!);
    }
    if (completions.isEmpty) return;
    final canonical = db
        .select('SELECT raw FROM ${tables.events}')
        .map((row) => LogEvent.decode(row['raw'] as String))
        .toList();
    final resolution = _textResolution(
      pending: pending == null ? [] : [pending],
    );
    for (final completion in completions) {
      final descriptor = completion.data['checklist'] as Map;
      final declared = (descriptor['items'] as List)
          .cast<Map<String, dynamic>>();
      final verification = verifyTextInheritance(
        {
          'codec': descriptor['codec'],
          'adapter': descriptor['adapter'],
          'frontiers': descriptor['frontiers'],
          'fields': declared.isNotEmpty
              ? declared.first['fields']
              : {
                  for (final field in ['title', 'description'])
                    field: {
                      'parentContext': '0' * 64,
                      'seedHash': '0' * 64,
                      'historyHash': '0' * 64,
                    },
                },
        },
        completion: completion,
        available: canonical,
      );
      if (verification.isPending) {
        if (identical(completion, pending)) {
          throw FormatFailure(
            'Checklist completion requires its observed history.',
          );
        }
        continue;
      }
      final observed = projectChecklist(
        verification.observedPrefix.toList(),
        completion.entity,
      );
      if (jsonEncode(observed.map((item) => item['id']).toList()) !=
          jsonEncode(declared.map((item) => item['source']).toList())) {
        throw FormatFailure(
          'Observed checklist membership/order differs in ${completion.id}.',
        );
      }
      final nativeParent =
          verification.observedPrefix.any(
            (event) =>
                event.entity == completion.entity &&
                isNativeTextCreation(event.type),
          ) ||
          textContributions(
            verification.observedPrefix,
            completion.entity,
          ).isNotEmpty ||
          _legacyTextRoots(
                completion.entity,
                verification.observedPrefix,
              )?.isNotEmpty ==
              true;
      if (nativeParent != hasNativeTaskSuccessor(completion)) {
        throw FormatFailure(
          'Checklist completion parent text mode differs in ${completion.id}.',
        );
      }
      if (hasNativeTaskSuccessor(completion)) {
        resolution.resolve(
          (completion.data['successor'] as Map)['id'] as String,
        );
      }
      for (final item in declared) {
        resolution.resolve(item['id'] as String);
      }
    }
  }

  Map<String, dynamic> _checklistCopy(
    String parent,
    String successor,
    List<Map<String, dynamic>> items,
    Map<String, dynamic> frontiers,
  ) {
    if (items.length > maximumChecklistCopyItems) {
      throw FormatFailure(
        'This checklist exceeds the recurring-copy item limit.',
      );
    }
    final resolution = _textResolution();
    return {
      'codec': 'yrs-v1',
      'adapter': 2,
      'frontiers': frontiers,
      'items': [
        for (final item in items)
          (() {
            final fields = resolution.resolve(item['id'] as String);
            return {
              'id': copiedChecklistId(successor, item['id'] as String),
              'source': item['id'],
              'title': fields['title']!.text,
              'description': fields['description']!.text,
              'fields': {
                for (final field in ['title', 'description'])
                  field: {
                    'parentContext': fields[field]!.context.hash,
                    'seedHash': fields[field]!.context.seedHash,
                    'historyHash': fields[field]!.historyReference!.hash,
                  },
              },
            };
          })(),
      ],
    };
  }
}
