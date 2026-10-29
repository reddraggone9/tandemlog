import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../application/task_text_session.dart';
import '../application/text_save_command.dart';
import '../food/food_purchase_import.dart';
import '../food/inventory.dart';
import '../storage/task_store.dart';
import 'agent_profile.dart';
import 'command.dart';
import 'commands_read.dart';
import 'commands_write.dart';
import 'render.dart';

const _revs = AgentArg(
  'rev',
  'string',
  'Current revision of each affected item as id=rev.',
  required: true,
  repeated: true,
);

/// `id=rev` pairs → full ID → rev, resolving ID prefixes against [ids].
Map<String, String> revMap(AgentCall call, Iterable<String> ids, String noun) {
  final out = <String, String>{};
  for (final pair in call.strings('rev')) {
    final eq = pair.lastIndexOf('=');
    if (eq < 1) {
      throw AgentFailure(
        'validation',
        'Write each revision as id=rev ("$pair").',
        details: {'field': 'rev', 'error': 'format'},
      );
    }
    out[resolveId(pair.substring(0, eq), ids, noun)] = pair.substring(eq + 1);
  }
  return out;
}

Iterable<String> _taskIds(AgentCall call) => call.ws.session.tasks.rows
    .where((r) => r['kind'] == 'task')
    .map((r) => r['id'] as String);

/// Every listed target must carry a revision; extra revisions (neighbors,
/// parents) are checked too.
Map<String, String> _requireRevs(
  AgentCall call,
  List<String> targets,
  Iterable<String> ids,
  String noun,
) {
  final revs = revMap(call, ids, noun);
  final missing = targets.where((t) => !revs.containsKey(t)).toList();
  if (missing.isNotEmpty) {
    throw AgentFailure(
      'validation',
      'Missing --rev for ${missing.map(shortId).join(', ')}.',
      details: {'field': 'rev', 'error': 'missing', 'ids': missing},
    );
  }
  return revs;
}

Map<String, dynamic>? _checklistItem(AgentCall call, String item) {
  for (final r in call.ws.session.tasks.rows) {
    for (final i in (r['checklist'] as List? ?? const [])) {
      if (i is Map && i['id'] == item) return Map<String, dynamic>.from(i);
    }
  }
  return null;
}

Iterable<String> _checklistIds(AgentCall call) => [
  for (final r in call.ws.session.tasks.rows)
    for (final i in (r['checklist'] as List? ?? const []))
      if (i is Map) i['id'] as String,
];

String _checklistParent(AgentCall call, String item) {
  for (final r in call.ws.session.tasks.rows) {
    for (final i in (r['checklist'] as List? ?? const [])) {
      if (i is Map && i['id'] == item) return r['id'] as String;
    }
  }
  throw AgentFailure('not_found', 'No checklist item ${shortId(item)}.');
}

Future<AgentResult> _textEdit(
  AgentCall call,
  String entity,
  Map<String, String> text,
  bool Function() guard, {
  Map<String, dynamic> fields = const {},
  List<String>? tags,
  Map<String, String> observedTagRefs = const {},
  required String result,
  required List<String> affected,
}) async {
  final store = call.ws.session.tasks;
  final before = ownHead(call);
  final capture = await store.captureTaskText(entity);
  final session = TaskTextSession(capture);
  try {
    for (final e in text.entries) {
      session.replace(e.key, e.value);
    }
    final saved = await TextSaveCommand(store, session).save(
      fields: fields,
      tags: tags ?? const [],
      observedTagRefs: observedTagRefs,
      canCommit: guard,
    );
    return writeResult(
      call,
      before,
      saved.status == TextSaveStatus.unchanged ? 'No changes.' : result,
      affected,
    );
  } finally {
    session.cancel();
  }
}

FoodDetails _withChanges(FoodDetails base, AgentCall call) => FoodDetails(
  name: call.string('name')?.trim() ?? base.name,
  brand: call.string('brand')?.trim() ?? base.brand,
  size: call.string('size')?.trim() ?? base.size,
  expiry: call.string('expiry') == null
      ? base.expiry
      : call.string('expiry') == 'none'
      ? null
      : call.string('expiry'),
  estimated: base.estimated,
  retention: call.string('retention')?.trim() ?? base.retention,
  location: call.string('location')?.trim() ?? base.location,
);

const _foodFieldArgs = [
  AgentArg('expiry', 'string', 'Expiry date YYYY-MM-DD, or "none".'),
  AgentArg('location', 'string', 'Location.'),
  AgentArg('retention', 'string', 'Retention reason ("" to clear).'),
  AgentArg('name', 'string', 'Product name (changes the product).'),
  AgentArg('brand', 'string', 'Product brand (changes the product).'),
  AgentArg('size', 'string', 'Product size (changes the product).'),
];

/// Product-level edits travel with the product's containers, as from the
/// app's row editor; a product without containers cannot be edited there.
List<String> _productContainers(AgentCall call, List<String> products) {
  final ids = [
    for (final c in foodState(call).containers)
      if (products.contains(c.product)) c.id,
  ];
  if (ids.isEmpty) {
    throw const AgentFailure(
      'validation',
      'This product has no containers to edit it through.',
    );
  }
  return ids;
}

List<AgentCommand> moreCommands() => [
  AgentCommand(
    'tasks move',
    'Move a task before another (same-date rule), or to the end.',
    CommandKind.write,
    const [
      AgentArg(
        'id',
        'string',
        'Task to move.',
        required: true,
        positional: true,
      ),
      AgentArg(
        'before',
        'string',
        'Task to place it before, or "end".',
        required: true,
      ),
      _revs,
    ],
    (call) async {
      final ids = _taskIds(call);
      final id = resolveId(call.require('id'), ids, 'task');
      final anchor = call.require('before') == 'end'
          ? null
          : resolveId(call.require('before'), ids, 'task');
      final revs = _requireRevs(call, [id, ?anchor], ids, 'task');
      final guard = taskGuard(call, revs);
      final before = ownHead(call);
      await call.ws.session.tasks.moveBefore(id, anchor, canCommit: guard);
      return writeResult(call, before, 'Moved ${shortId(id)}.', [id]);
    },
  ),
  AgentCommand(
    'tasks bulk-edit',
    'Apply schedule, assignee and tag changes to several tasks as one action.',
    CommandKind.write,
    const [
      AgentArg(
        'id',
        'string',
        'Tasks to edit.',
        required: true,
        positional: true,
        repeated: true,
      ),
      _revs,
      AgentArg('start', 'string', 'Start date YYYY-MM-DD, or "none".'),
      AgentArg('due', 'string', 'Due date YYYY-MM-DD, or "none".'),
      AgentArg('start-time', 'string', 'Start time HH:MM, or "none".'),
      AgentArg('due-time', 'string', 'Due time HH:MM, or "none".'),
      AgentArg('for', 'string', 'New assignee.'),
      AgentArg('tag', 'string', 'Add a tag.', repeated: true),
      AgentArg('untag', 'string', 'Remove a tag.', repeated: true),
    ],
    (call) async {
      final all = _taskIds(call);
      final ids = [
        for (final i in call.strings('id')) resolveId(i, all, 'task'),
      ];
      final guard = taskGuard(call, _requireRevs(call, ids, all, 'task'));
      final patch = <String, dynamic>{
        for (final (arg, key) in const [
          ('start', 'startDate'),
          ('due', 'dueDate'),
          ('start-time', 'startTime'),
          ('due-time', 'dueTime'),
        ])
          if (call.string(arg) != null)
            key: call.string(arg) == 'none' ? null : call.string(arg),
      };
      final store = call.ws.session.tasks;
      final before = ownHead(call);
      final result = await store.bulkEdit(
        ids,
        BulkTaskEdit(
          schedulePatch: patch,
          assignee: call.string('for') == null
              ? null
              : resolvePerson(call, call.string('for')!),
          addTags: call.strings('tag'),
          removeTags: call.strings('untag'),
        ),
        expectedTaskSnapshot: store.taskSnapshot,
        canCommit: guard,
      );
      if (result.error != null && result.committedIds.isEmpty) {
        throw result.error!;
      }
      return writeResult(
        call,
        before,
        result.succeeded
            ? 'Edited ${result.committedIds.length} tasks.'
            : 'Edited ${result.committedIds.length} of ${ids.length}; ${result.remainingIds.length} not changed: ${result.error}',
        ids,
        extra: {'remaining': result.remainingIds},
      );
    },
    requiresPlan: true,
  ),
  AgentCommand(
    'tasks bulk-delete',
    'Delete several tasks as one action.',
    CommandKind.write,
    const [
      AgentArg(
        'id',
        'string',
        'Tasks to delete.',
        required: true,
        positional: true,
        repeated: true,
      ),
      _revs,
    ],
    (call) async {
      final all = _taskIds(call);
      final ids = [
        for (final i in call.strings('id')) resolveId(i, all, 'task'),
      ];
      final guard = taskGuard(call, _requireRevs(call, ids, all, 'task'));
      final store = call.ws.session.tasks;
      final before = ownHead(call);
      final result = await store.deleteTasks(
        ids,
        expectedTaskSnapshot: store.taskSnapshot,
        canCommit: guard,
      );
      if (result.error != null) throw result.error!;
      return writeResult(call, before, 'Deleted ${ids.length} tasks.', ids);
    },
    requiresPlan: true,
  ),
  AgentCommand(
    'tasks bulk-move',
    'Move several tasks before another task (or to the end), keeping their order.',
    CommandKind.write,
    const [
      AgentArg(
        'id',
        'string',
        'Tasks to move.',
        required: true,
        positional: true,
        repeated: true,
      ),
      AgentArg(
        'before',
        'string',
        'Task to place them before, or "end".',
        required: true,
      ),
      _revs,
    ],
    (call) async {
      final all = _taskIds(call);
      final ids = [
        for (final i in call.strings('id')) resolveId(i, all, 'task'),
      ];
      final anchor = call.require('before') == 'end'
          ? null
          : resolveId(call.require('before'), all, 'task');
      final guard = taskGuard(
        call,
        _requireRevs(call, [...ids, ?anchor], all, 'task'),
      );
      final store = call.ws.session.tasks;
      final before = ownHead(call);
      final result = await store.moveBlockBefore(
        ids,
        anchor,
        expectedTaskSnapshot: store.taskSnapshot,
        canCommit: guard,
      );
      if (result.error != null) throw result.error!;
      return writeResult(call, before, 'Moved ${ids.length} tasks.', ids);
    },
    requiresPlan: true,
  ),
  AgentCommand(
    'checklist add',
    'Add a checklist item to a task.',
    CommandKind.write,
    const [
      AgentArg(
        'task',
        'string',
        'Parent task.',
        required: true,
        positional: true,
      ),
      AgentArg(
        'title',
        'string',
        'Item text.',
        required: true,
        positional: true,
      ),
      AgentArg('notes', 'string', 'Item notes.'),
      AgentArg(
        'before',
        'string',
        'Existing item to insert before (default end).',
      ),
      AgentArg(
        'if-rev',
        'string',
        'Current rev of the parent task.',
        required: true,
      ),
      AgentArg('request-id', 'string', 'UUID making a retry idempotent.'),
    ],
    (call) async {
      final parent = resolveId(call.require('task'), _taskIds(call), 'task');
      taskGuard(call, {parent: call.require('if-rev')});
      final title = call.require('title').trim();
      if (title.isEmpty) {
        throw const AgentFailure(
          'validation',
          'Enter the item text.',
          details: {'field': 'title', 'error': 'empty'},
        );
      }
      final request = call.string('request-id');
      final id = request == null
          ? const Uuid().v4()
          : const Uuid().v5(request, 'checklist');
      final store = call.ws.session.tasks;
      final before = ownHead(call);
      if (!store.hasEntity(id)) {
        await store.addChecklistItem(
          parent,
          title,
          notes: call.string('notes') ?? '',
          before: call.string('before') == null
              ? null
              : resolveId(
                  call.string('before')!,
                  _checklistIds(call),
                  'checklist item',
                ),
          id: id,
        );
      }
      return writeResult(
        call,
        before,
        'Added item ${shortId(id)}.',
        [parent],
        extra: {'id': id, 'rev': taskRev(call, id)},
      );
    },
  ),
  for (final (name, completed) in const [('check', true), ('uncheck', false)])
    AgentCommand(
      'checklist $name',
      '${completed ? 'Check' : 'Uncheck'} a checklist item.',
      CommandKind.write,
      const [
        AgentArg(
          'item',
          'string',
          'Checklist item.',
          required: true,
          positional: true,
        ),
        AgentArg(
          'if-rev',
          'string',
          'Current rev of the item.',
          required: true,
        ),
      ],
      (call) async {
        final item = resolveId(
          call.require('item'),
          _checklistIds(call),
          'checklist item',
        );
        final guard = taskGuard(call, {item: call.require('if-rev')});
        final before = ownHead(call);
        await call.ws.session.tasks.command(item, 'checklist.itemEdited', {
          'completed': completed,
        }, canCommit: guard);
        return writeResult(
          call,
          before,
          '${completed ? 'Checked' : 'Unchecked'} ${shortId(item)}.',
          [_checklistParent(call, item)],
          extra: {'item': item, 'rev': taskRev(call, item)},
        );
      },
    ),
  AgentCommand(
    'checklist edit',
    'Change a checklist item\'s text or notes.',
    CommandKind.write,
    const [
      AgentArg(
        'item',
        'string',
        'Checklist item.',
        required: true,
        positional: true,
      ),
      AgentArg('if-rev', 'string', 'Current rev of the item.', required: true),
      AgentArg('title', 'string', 'New text.'),
      AgentArg('notes', 'string', 'New notes.'),
    ],
    (call) async {
      final item = resolveId(
        call.require('item'),
        _checklistIds(call),
        'checklist item',
      );
      final guard = taskGuard(call, {item: call.require('if-rev')});
      final current = _checklistItem(call, item)!;
      final title = call.string('title')?.trim();
      if (title != null && title.isEmpty) {
        throw const AgentFailure(
          'validation',
          'Enter the item text.',
          details: {'field': 'title', 'error': 'empty'},
        );
      }
      return _textEdit(
        call,
        item,
        {
          if (title != null && title != current['title']) 'title': title,
          if (call.string('notes') != null &&
              call.string('notes') != current['description'])
            'description': call.string('notes')!,
        },
        guard,
        result: 'Saved item ${shortId(item)}.',
        affected: [_checklistParent(call, item)],
      );
    },
  ),
  AgentCommand(
    'checklist delete',
    'Delete a checklist item.',
    CommandKind.write,
    const [
      AgentArg(
        'item',
        'string',
        'Checklist item.',
        required: true,
        positional: true,
      ),
      AgentArg('if-rev', 'string', 'Current rev of the item.', required: true),
    ],
    (call) async {
      final item = resolveId(
        call.require('item'),
        _checklistIds(call),
        'checklist item',
      );
      final parent = _checklistParent(call, item);
      final guard = taskGuard(call, {item: call.require('if-rev')});
      final before = ownHead(call);
      await call.ws.session.tasks.command(
        item,
        'checklist.itemDeleted',
        {},
        canCommit: guard,
      );
      return writeResult(call, before, 'Deleted item ${shortId(item)}.', [
        parent,
      ]);
    },
  ),
  AgentCommand(
    'checklist move',
    'Move a checklist item before another, or to the end.',
    CommandKind.write,
    const [
      AgentArg(
        'item',
        'string',
        'Checklist item.',
        required: true,
        positional: true,
      ),
      AgentArg(
        'before',
        'string',
        'Item to place it before, or "end".',
        required: true,
      ),
      _revs,
    ],
    (call) async {
      final ids = _checklistIds(call);
      final item = resolveId(call.require('item'), ids, 'checklist item');
      final anchor = call.require('before') == 'end'
          ? null
          : resolveId(call.require('before'), ids, 'checklist item');
      final guard = taskGuard(
        call,
        _requireRevs(call, [item, ?anchor], ids, 'checklist item'),
      );
      final before = ownHead(call);
      await call.ws.session.tasks.moveChecklistItem(
        item,
        anchor,
        canCommit: guard,
      );
      return writeResult(call, before, 'Moved item ${shortId(item)}.', [
        _checklistParent(call, item),
      ]);
    },
  ),
  AgentCommand(
    'food edit',
    'Edit containers; name/brand/size change the product and may merge products.',
    CommandKind.write,
    [
      const AgentArg(
        'id',
        'string',
        'Containers to edit.',
        required: true,
        positional: true,
        repeated: true,
      ),
      _revs,
      ..._foodFieldArgs,
    ],
    (call) async {
      final state = foodState(call);
      final all = [for (final c in state.containers) c.id];
      final ids = [
        for (final i in call.strings('id')) resolveId(i, all, 'container'),
      ];
      final revs = _requireRevs(call, ids, all, 'container');
      final guard = foodGuard(call, revs.keys.toList(), revs.values.toList());
      final targets = [
        for (final c in state.containers)
          if (ids.contains(c.id)) c,
      ];
      final details = _withChanges(targets.first.details, call);
      details.validate();
      final after = details.toJson();
      const productFields = {'name', 'brand', 'size'};
      final fields = [
        for (final f in const ['expiry', 'location', 'retention'])
          if (call.string(f) != null &&
              targets.any((t) => t.details.toJson()[f] != after[f]))
            f,
      ];
      final changes = <String, Object?>{
        for (final f in productFields)
          if (call.string(f) != null &&
              targets.any((t) => t.details.toJson()[f] != after[f]))
            f: after[f],
      };
      final products = FoodProductChange(
        roots: {for (final t in targets) t.product}.toList(),
        changes: changes,
      );
      final before = ownHead(call);
      if (fields.isEmpty && products.isEmpty) {
        return writeResult(
          call,
          before,
          'No changes.',
          const [],
          containerIds: ids,
        );
      }
      final scope = state.containers
          .where(
            (c) => !ids.contains(c.id) && products.roots.contains(c.product),
          )
          .length;
      await call.ws.session.food.changeDetails(
        ids,
        details,
        fields,
        products: products,
        canCommit: guard,
      );
      return writeResult(
        call,
        before,
        'Saved ${ids.length} container${ids.length == 1 ? '' : 's'}.'
        '${changes.isEmpty || scope == 0 ? '' : ' Also changes $scope other containers.'}',
        const [],
        containerIds: ids,
        extra: {'alsoChanges': changes.isEmpty ? 0 : scope},
      );
    },
    requiresPlan: true,
    planWhen: (args) =>
        (args['id'] as List).length > 1 ||
        ['name', 'brand', 'size'].any(args.containsKey),
  ),
  AgentCommand(
    'food add-another',
    'Add containers like an existing one (same product), as in the row menu.',
    CommandKind.write,
    [
      const AgentArg(
        'id',
        'string',
        'Existing container.',
        required: true,
        positional: true,
      ),
      const AgentArg('count', 'integer', 'Number of containers (default 1).'),
      const AgentArg('expiry', 'string', 'Expiry date YYYY-MM-DD, or "none".'),
      const AgentArg('location', 'string', 'Location.'),
      const AgentArg(
        'request-id',
        'string',
        'UUID making a retried add idempotent.',
      ),
    ],
    (call) async {
      final source = foodContainer(call, call.require('id'));
      final store = call.ws.session.food;
      final known = {for (final c in store.state.containers) c.id};
      final count = call.integer('count') ?? 1;
      final before = ownHead(call);
      await store.add(
        _withChanges(source.details, call),
        count,
        ids: requestIds(call, count),
      );
      return writeResult(
        call,
        before,
        'Added $count ${source.details.name}.',
        const [],
        containerIds: [
          for (final c in store.state.containers)
            if (!known.contains(c.id)) c.id,
        ],
      );
    },
  ),
  AgentCommand(
    'products set',
    'Set a product\'s store link and minimum to keep.',
    CommandKind.write,
    const [
      AgentArg('id', 'string', 'Product.', required: true, positional: true),
      AgentArg(
        'if-rev',
        'string',
        'Current rev of the product.',
        required: true,
      ),
      AgentArg('link', 'string', 'Store link (https://…), or "none".'),
      AgentArg('min', 'string', 'Minimum to keep (whole number), or "none".'),
    ],
    (call) async {
      final products = foodState(call).products;
      final id = resolveId(call.require('id'), products.keys, 'product');
      final product = products[id]!;
      String rev(dynamic p) => productJson(p)['rev'] as String;
      if (rev(product) != call.require('if-rev')) {
        throw AgentFailure(
          'stale',
          'Product ${shortId(id)} changed. Read it again.',
          details: {
            'id': id,
            'rev': rev(product),
            'expected': call.require('if-rev'),
          },
        );
      }
      final changes = <String, Object?>{};
      final link = call.string('link');
      if (link != null) {
        if (link != 'none' && !isFoodStoreLink(link)) {
          throw const AgentFailure(
            'validation',
            'Enter a web address starting with https://.',
            details: {'field': 'link', 'error': 'invalid'},
          );
        }
        changes['links'] = [
          if (link != 'none') link,
          ...product.links.skip(1).where((l) => l != link),
        ];
      }
      final min = call.string('min');
      if (min != null) {
        final value = min == 'none' ? null : int.tryParse(min);
        if (min != 'none' && (value == null || value < 0)) {
          throw const AgentFailure(
            'validation',
            'Minimum must be a whole number.',
            details: {'field': 'min', 'error': 'invalid'},
          );
        }
        changes['minimum'] = value;
      }
      final before = ownHead(call);
      final store = call.ws.session.food;
      await store.changeDetails(
        _productContainers(call, [id]),
        const FoodDetails(name: ''),
        const [],
        products: FoodProductChange(roots: [id], changes: changes),
        canCommit: () {
          final now = foodState(call).products[id];
          return now != null && rev(now) == call.require('if-rev');
        },
      );
      final now = foodState(call).products[id];
      return AgentResult({
        'actions': newActions(call, before),
        'product': now == null ? null : productJson(now),
      }, now == null ? 'Saved.' : 'Saved ${productLine(now)}');
    },
  ),
  AgentCommand(
    'products merge',
    'Merge one product into another (containers and purchases move).',
    CommandKind.write,
    const [
      AgentArg(
        'source',
        'string',
        'Product to merge away.',
        required: true,
        positional: true,
      ),
      AgentArg('into', 'string', 'Product to keep.', required: true),
      AgentArg(
        'keep',
        'string',
        'Whose name/brand/size remain (default target).',
        choices: ['source', 'target'],
      ),
      _revs,
    ],
    (call) async {
      final products = foodState(call).products;
      final source = resolveId(
        call.require('source'),
        products.keys,
        'product',
      );
      final target = resolveId(call.require('into'), products.keys, 'product');
      if (source == target) {
        throw const AgentFailure(
          'validation',
          'Choose two different products.',
        );
      }
      final revs = _requireRevs(
        call,
        [source, target],
        products.keys,
        'product',
      );
      String rev(String id) =>
          productJson(foodState(call).products[id])['rev'] as String;
      for (final e in revs.entries) {
        if (rev(e.key) != e.value) {
          throw AgentFailure(
            'stale',
            'Product ${shortId(e.key)} changed. Read it again.',
            details: {'id': e.key, 'rev': rev(e.key), 'expected': e.value},
          );
        }
      }
      final keep = products[call.string('keep') == 'source' ? source : target]!;
      final before = ownHead(call);
      await call.ws.session.food.changeDetails(
        _productContainers(call, [source, target]),
        const FoodDetails(name: ''),
        const [],
        products: FoodProductChange(
          roots: call.string('keep') == 'source' ? [source, target] : [source],
          changes: {'name': keep.name, 'brand': keep.brand, 'size': keep.size},
        ),
        canCommit: () => revs.entries.every(
          (e) =>
              foodState(call).products[e.key] != null && rev(e.key) == e.value,
        ),
      );
      return AgentResult({
        'actions': newActions(call, before),
      }, 'Merged ${shortId(source)} into ${shortId(target)}.');
    },
    requiresPlan: true,
  ),
  AgentCommand(
    'purchases plan',
    'Turn loose receipt lines into an immutable purchase-import plan file.',
    CommandKind.read,
    const [
      AgentArg(
        'lines',
        'string',
        'JSON file: array of lines.',
        required: true,
        positional: true,
      ),
      AgentArg(
        'out',
        'string',
        'Where to write the plan (default <lines>.plan.json).',
      ),
    ],
    (call) async {
      final path = call.require('lines');
      final bytes = await File(path).readAsBytes();
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! List) {
        throw const AgentFailure(
          'validation',
          'The lines file must be a JSON array.',
          details: {'field': 'lines', 'error': 'invalid'},
        );
      }
      final sourceSha = sha256.convert(bytes).toString();
      final space = call.ws.session.history.manifest.space;
      final lines = <FoodPurchaseLine>[];
      final suggestions = <Map<String, Object?>>[];
      final state = foodState(call);
      for (var i = 0; i < raw.length; i++) {
        final j = Map<String, dynamic>.from(raw[i] as Map);
        j.putIfAbsent('currency', () => 'USD');
        try {
          lines.add(FoodPurchaseLine.fromJson(j));
        } on FormatException catch (e) {
          throw AgentFailure(
            'validation',
            'Line ${i + 1}: ${e.message}',
            details: {'field': 'lines[$i]', 'error': e.message},
          );
        }
        if (j['product'] == null) {
          final terms = '${j['name']} ${j['brand'] ?? ''}'
              .toLowerCase()
              .split(RegExp(r'\s+'))
              .where((t) => t.length > 2)
              .toSet();
          final likely = state.products.values
              .where(
                (p) => terms.any('${p.name} ${p.brand}'.toLowerCase().contains),
              )
              .take(3)
              .map(
                (p) => {
                  'product': p.id,
                  'name': p.name,
                  'brand': p.brand,
                  'size': p.size,
                },
              )
              .toList();
          if (likely.isNotEmpty) {
            suggestions.add({'line': i + 1, 'likely': likely});
          }
        }
      }
      final plan = FoodPurchaseImportPlan(
        space: space,
        importId: const Uuid().v5(space, 'purchase-import:$sourceSha'),
        sourceSha256: sourceSha,
        lines: lines,
      );
      final out = call.string('out') ?? '$path.plan.json';
      await File(out).writeAsString(plan.canonicalJson);
      return AgentResult(
        {
          'plan': out,
          'planHash': plan.planHash,
          'lines': lines.length,
          'suggestions': suggestions,
        },
        [
          'Wrote $out (${lines.length} lines, planHash ${plan.planHash.substring(0, 8)}).',
          for (final s in suggestions)
            'line ${s['line']}: existing products ${(s['likely'] as List).map((p) => '${p['name']} ${p['brand']} ${p['size']} (${shortId(p['product'] as String)})').join('; ')} — set "product" to link instead of creating a new one',
          'Next: tandemlog-cli purchases import $out --dry-run',
        ].join('\n'),
      );
    },
  ),
  AgentCommand(
    'purchases import',
    'Record purchases from a plan as one action (dry run first).',
    CommandKind.write,
    const [
      AgentArg(
        'plan',
        'string',
        'Plan file from purchases plan.',
        required: true,
        positional: true,
      ),
    ],
    (call) async {
      final plan = FoodPurchaseImportPlan.decode(
        await File(call.require('plan')).readAsString(),
      );
      final store = call.ws.session.food;
      final dry = call.flag('dry-run');
      if (!dry && call.string('expect-plan') != plan.planHash) {
        throw AgentFailure(
          'plan_changed',
          'Pass --expect-plan ${plan.planHash} from the dry run.',
          details: {'field': 'expect-plan', 'planHash': plan.planHash},
        );
      }
      final before = ownHead(call);
      final report = dry
          ? await store.dryRunPurchaseImport(plan)
          : await store.commitPurchaseImport(plan);
      final names = {
        for (final p in foodState(call).products.values) p.id: p.name,
      };
      final lines = [
        for (final l in report.lines)
          {
            'purchase': l.purchase,
            'product': l.product,
            'productName': names[l.product],
            'status': l.status.name,
            'newProduct': l.newProduct,
            'matched': l.matched,
            'created': l.created,
          },
      ];
      return AgentResult(
        {
          'dryRun': dry,
          'planHash': report.planHash,
          'status': report.status.name,
          'lines': lines,
          if (!dry) 'actions': newActions(call, before),
        },
        [
          '${dry ? 'Dry run' : 'Imported'}: ${report.status.name} · planHash ${report.planHash}',
          for (final l in lines)
            '${l['status']} ${l['productName'] ?? shortId(l['product'] as String)}${l['newProduct'] == true ? ' (new product)' : ''} · matched ${(l['matched'] as List).length} · Inbox +${(l['created'] as List).length}',
        ].join('\n'),
      );
    },
    ownDryRun: true,
  ),
];
