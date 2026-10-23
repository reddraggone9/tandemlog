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
          "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='checklist.itemCreated' AND json_extract(semantic,'\$.data.parent')=?",
          [parent],
        )
        .map((row) => _recurringTextMemo.decodeCanonical(row['raw'] as String))
        .toList();
    final copies = db
        .select(
          "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.completedWithChecklist' AND json_extract(semantic,'\$.data.successor.id')=?",
          [parent],
        )
        .map((row) => _recurringTextMemo.decodeCanonical(row['raw'] as String))
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
            .map(
              (row) => _recurringTextMemo.decodeCanonical(row['raw'] as String),
            ),
    ];
  }

  List<(LogEvent, Map<String, dynamic>)> _itemCopySeeds(String entity) {
    if (_copySeedScopeDepth > 0 && !_copySeedIndexUnavailable) {
      if (_copySeedIndex == null) {
        // Check a cheap bounded payload total before loading whole descriptors.
        final size =
            db
                    .select(
                      "SELECT COALESCE(SUM(length(CAST(raw AS BLOB))),0) AS bytes FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.completedWithChecklist'",
                    )
                    .single['bytes']
                as int;
        if (size * 4 <= 4 * 1024 * 1024) {
          _copySeedIndex = ChecklistCopyIndex.build(
            db
                .select(
                  "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.completedWithChecklist' ORDER BY clock,writer,seq",
                )
                .map(
                  (r) => _recurringTextMemo.decodeCanonical(r['raw'] as String),
                ),
          );
        }
        if (_copySeedIndex == null) _copySeedIndexUnavailable = true;
      }
      if (_copySeedIndex != null) return _copySeedIndex![entity];
    }
    return db
        .select(
          "SELECT e.raw,i.value FROM ${tables.events} e JOIN json_each(json_extract(e.semantic,'\$.data.checklist.items')) i WHERE json_extract(e.semantic,'\$.type')='task.completedWithChecklist' AND json_extract(i.value,'\$.id')=? ORDER BY e.clock,e.writer,e.seq",
          [entity],
        )
        .map(
          (row) => (
            _recurringTextMemo.decodeCanonical(row['raw'] as String),
            jsonDecode(row['value'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
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
        ? _textResolution(
            entities: [
              state['id'] as String,
              ...items.map((item) => item['id'] as String),
            ],
          )
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

  void _validateChecklistReferences(
    LogEvent? pending, {
    bool scoped = false,
    bool enforceLocalAvailability = true,
  }) {
    final references = db
        .select(
          "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type') IN ('checklist.itemCreated','checklist.itemMoved')${scoped ? " AND (entity=? OR json_extract(semantic,'\$.data.parent')=? OR json_extract(semantic,'\$.data.before')=?)" : ''}",
          scoped ? [pending!.entity, pending.entity, pending.entity] : [],
        )
        .map((row) => _recurringTextMemo.decodeCanonical(row['raw'] as String))
        .toList();
    if (pending != null &&
        {
          'checklist.itemCreated',
          'checklist.itemMoved',
        }.contains(pending.type)) {
      references.add(pending);
    }
    final pendingInserted =
        pending != null &&
        db.select('SELECT 1 FROM ${tables.events} WHERE id=?', [
          pending.id,
        ]).isNotEmpty;
    Map<String, dynamic>? state(String id) => project([
      ..._entityEvents(id),
      if (!pendingInserted && pending?.entity == id) pending!,
    ]);
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
      if (enforceLocalAvailability &&
          identical(reference, pending) &&
          !_checklistParentAvailable(parent)) {
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
      if (enforceLocalAvailability &&
          identical(reference, pending) &&
          anchor == null) {
        throw FormatFailure('Checklist order anchor is missing.');
      }
    }
    if (enforceLocalAvailability && pending != null) {
      _validatePendingChecklistEligibility(pending);
    }
  }

  // Local availability is still checked even when unchanged global references
  // have a settled-graph proof.
  void _validatePendingChecklistEligibility(LogEvent pending) {
    Map<String, dynamic>? state(String id) =>
        project([..._entityEvents(id), if (pending.entity == id) pending]);
    if (pending.type.startsWith('checklist.') ||
        pending.type == 'task.textEdited') {
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

  void _requireObservedTextFrontiers(
    Map<String, dynamic> descriptor,
    LogEvent pending,
  ) {
    for (final entry in (descriptor['frontiers'] as Map).entries) {
      final writer = entry.key as String, frontier = entry.value as Map;
      final sequence = frontier['seq'] as int;
      if (writer == pending.writer && sequence >= pending.sequence) {
        throw FormatFailure(
          'Text inheritance cannot reference a forward operation.',
        );
      }
      if (sequence == 0) {
        if (frontier['hash'] != eventGenesisHash(space, writer)) {
          throw FormatFailure('Text inheritance genesis hash mismatch.');
        }
        continue;
      }
      final rows = db.select('SELECT raw FROM ${tables.events} WHERE id=?', [
        '$writer:$sequence',
      ]);
      if (rows.isEmpty) {
        throw FormatFailure(
          'Completion requires its observed canonical history.',
        );
      }
      final head = _recurringTextMemo.decodeCanonical(
        rows.single['raw'] as String,
      );
      if (head.hash != frontier['hash'] || head.clock >= pending.clock) {
        throw FormatFailure(
          'Text inheritance frontier differs from observed history.',
        );
      }
    }
  }

  void _validateChecklistCompletions([
    LogEvent? pending,
    bool auditExisting = true,
    RecurringTextResolver? suppliedResolution,
  ]) {
    final completions = !auditExisting
        ? <LogEvent>[]
        : db
              .select(
                "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.completedWithChecklist'",
              )
              .map(
                (row) =>
                    _recurringTextMemo.decodeCanonical(row['raw'] as String),
              )
              .toList();
    if (pending?.type == 'task.completedWithChecklist') {
      completions.add(pending!);
    }
    if (completions.isEmpty) return;
    // This is the exact committed/transactional SQL input. A preparation
    // overlay is kept only in its separate resolver and cannot supply a missing
    // frontier here; post-INSERT replay sees its actual inserted rows.
    final roots = <String>{for (final event in completions) event.entity};
    final canonicalInput = _textInput(entities: roots);
    final resolution =
        suppliedResolution ??
        _textResolution(
          pending: pending == null ? [] : [pending],
          entities: roots,
        );
    for (final completion in completions) {
      final descriptor = completion.data['checklist'] as Map;
      final declared = (descriptor['items'] as List)
          .cast<Map<String, dynamic>>();
      final cut = <String, dynamic>{
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
      };
      final verification = canonicalInput.verifyInheritance(
        cut,
        completion: completion,
      );
      if (verification.isPending) {
        if (identical(completion, pending)) {
          throw FormatFailure(
            'Checklist completion requires its observed history.',
          );
        }
        continue;
      }
      final baselineScope =
          '${_textBaseline?.hash ?? ''}|${textWriteBlocked ?? ''}';
      if (!_recurringTextMemo.hasVerifiedChecklistInputCut(
        textEngine!,
        baselineScope,
        completion,
        canonicalInput,
        cut,
      )) {
        final observed = canonicalInput.observedChecklist(
          completion.entity,
          cut,
          completion: completion,
        );
        if (jsonEncode(observed.map((item) => item['id']).toList()) !=
            jsonEncode(declared.map((item) => item['source']).toList())) {
          throw FormatFailure(
            'Observed checklist membership/order differs in ${completion.id}.',
          );
        }
        final nativeParent =
            verification.recordsForResolution.any(
              (event) =>
                  event.entity == completion.entity &&
                  isNativeTextCreation(event.type),
            ) ||
            textContributions(
              verification.recordsForResolution,
              completion.entity,
            ).isNotEmpty ||
            _legacyTextRoots(
                  completion.entity,
                  verification.recordsForResolution,
                )?.isNotEmpty ==
                true;
        if (nativeParent != hasNativeTaskSuccessor(completion)) {
          throw FormatFailure(
            'Checklist completion parent text mode differs in ${completion.id}.',
          );
        }
        _recurringTextMemo.rememberVerifiedChecklistInputCut(
          textEngine!,
          baselineScope,
          completion,
          canonicalInput,
          cut,
        );
      }
      // Reuse only the proved immutable predicates. Never rebuild an existing
      // cut entry on a hit; current global native lineage/collision checks remain.
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
    final resolution = _textResolution(
      entities: [parent, ...items.map((item) => item['id'] as String)],
    );
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
