import 'package:timezone/timezone.dart' as tz;

import '../domain/task_view.dart';
import '../domain/timed_view.dart';
import '../domain/wall_time.dart';
import '../food/inventory.dart';
import '../food/food_rows.dart';
import 'agent_profile.dart';
import 'command.dart';
import 'render.dart';

ViewTime viewTime(AgentCall call, String zone) {
  final instant = DateTime.now().toUtc();
  return ViewTime(
    instant: instant,
    localZoneId: zone,
    localOffset: tz.TZDateTime.from(
      instant,
      timeZoneLocation(zone),
    ).timeZoneOffset,
  );
}

/// People are `user` rows; `--for`/assignee accept a name or ID prefix.
Map<String, String> people(AgentCall call) =>
    peopleIn(call.ws.session.tasks.rows);

/// [people] from already-read Task rows; decoding the rows dominates.
Map<String, String> peopleIn(List<Map<String, dynamic>> rows) => {
  for (final r in rows)
    if (r['kind'] == 'user' && r['deleted'] != true)
      r['id'] as String: r['name'] as String? ?? '',
};

String resolvePerson(
  AgentCall call,
  String input, {
  Map<String, String>? names,
}) {
  final all = names ?? people(call);
  final byName = all.entries
      .where((e) => e.value.toLowerCase() == input.toLowerCase())
      .map((e) => e.key)
      .toList();
  if (byName.length == 1) return byName.single;
  if (byName.length > 1) {
    throw AgentFailure('ambiguous_id', 'Several people are named "$input".');
  }
  return resolveId(input, all.keys, 'person');
}

Map<String, dynamic>? taskRow(AgentCall call, String id) {
  for (final r in call.ws.session.tasks.rows) {
    if (r['id'] == id && r['kind'] == 'task') return r;
  }
  return null;
}

/// Revision of a task: its admitted operation IDs, the completion that
/// created it (recurring successor), and the operations of its checklist
/// items, sorted. Items are those created under it and those it inherited
/// from its predecessor's completion (as `hasDurableChecklistActivity`).
/// A checklist item's rev also covers the completions that seeded it, so an
/// inherited item re-seeded with other content after Undo + re-complete (same
/// deterministic ID, no events of its own) gets a new rev. The unary `+` on
/// the completion type keeps both completion lookups on the successor index
/// instead of scanning every checklist completion through the type index.
/// Any admitted change, including one that restores identical visible fields
/// or only touches the checklist (which completion reads), changes it.
String taskRev(AgentCall call, String id) {
  final store = call.ws.session.tasks;
  final ids = [
    for (final r in store.db.select(
      taskRevSql(store.tables.events, store.tables.views),
      [id],
    ))
      r['id'] as String,
  ];
  return revOf(ids);
}

/// The [taskRev] query over a profile's [events] and [views] tables (`?1` is
/// the task or item ID); every lookup is an index search.
String taskRevSql(String events, String views) =>
    "SELECT id FROM $events WHERE entity=?1 "
    "OR json_extract(semantic,'\$.data.successor.id')=?1 "
    "OR entity IN (SELECT entity FROM $events WHERE json_extract(semantic,'\$.type')='checklist.itemCreated' AND json_extract(semantic,'\$.data.parent')=?1) "
    "OR entity IN (SELECT json_extract(item.value,'\$.id') FROM $events, json_each($events.semantic,'\$.data.checklist.items') AS item WHERE json_extract($events.semantic,'\$.data.successor.id')=?1 AND +json_extract($events.semantic,'\$.type')='task.completedWithChecklist') "
    "OR id IN (SELECT seed.id FROM $events AS seed WHERE json_extract(seed.semantic,'\$.data.successor.id')=(SELECT json_extract(raw,'\$.parent') FROM $views WHERE id=?1 AND json_extract(raw,'\$.kind')='checklistItem') AND +json_extract(seed.semantic,'\$.type')='task.completedWithChecklist' AND EXISTS (SELECT 1 FROM json_each(seed.semantic,'\$.data.checklist.items') AS item WHERE json_extract(item.value,'\$.id')=?1)) "
    "ORDER BY id";

/// [names] is [people] when the caller already has it (one map per call).
Map<String, Object?> taskJson(
  AgentCall call,
  Map<String, dynamic> t, {
  bool full = false,
  Map<String, String>? names,
}) {
  names ??= people(call);
  final notes = t['description'] as String? ?? '';
  return {
    'id': t['id'],
    'rev': taskRev(call, t['id'] as String),
    'title': t['title'],
    'notes': full ? notes : clip(notes, 200),
    if (!full && notes.length > 200) 'notesTruncated': true,
    'assignee': t['assignee'],
    'assigneeName': names[t['assignee']],
    'tags': t['tags'],
    'schedule': t['schedule'],
    'completed': t['completed'] == true,
    'completedInstant': t['completedInstant'],
    'inbox': t['inbox'] == true,
    'deleted': t['deleted'] == true,
    if (t['checklist'] != null)
      'checklist': [
        for (final item in t['checklist'] as List)
          if (item is Map)
            {...item, 'rev': taskRev(call, item['id'] as String)},
      ],
  };
}

String taskLine(
  AgentCall call,
  Map<String, dynamic> t,
  int year, {
  Map<String, String>? names,
  String? rev,
}) {
  names ??= people(call);
  final parts = <String>[
    '${shortId(t['id'] as String)} ${clip(t['title'] as String? ?? '', 120)}',
    taskScheduleText(Map<String, dynamic>.from(t['schedule'] as Map), year),
    [
      if (names[t['assignee']] != null) '@${names[t['assignee']]}',
      for (final tag in (t['tags'] as List? ?? const [])) '#$tag',
    ].join(' '),
    if (t['completed'] == true) 'done',
    'rev ${rev ?? taskRev(call, t['id'] as String)}',
  ];
  return parts.where((p) => p.isNotEmpty).join(' · ');
}

const _taskListArgs = [
  AgentArg('for', 'string', 'Assignee name or ID (default: everyone).'),
  AgentArg(
    'status',
    'string',
    'Open or completed tasks (default open).',
    choices: ['open', 'completed'],
  ),
  AgentArg('upcoming', 'boolean', 'Include upcoming (not yet started) tasks.'),
  AgentArg('tag', 'string', 'Only tasks with this tag.', repeated: true),
];

Future<AgentResult> _tasks(AgentCall call, {String? query}) async {
  final zone = call.options.timeZone!;
  final time = viewTime(call, zone);
  final rows = call.ws.session.tasks.rows;
  final names = peopleIn(rows);
  final assignee = call.string('for') == null
      ? null
      : resolvePerson(call, call.string('for')!, names: names);
  final view = projectTaskView(
    rows,
    time,
    assignee: assignee,
    includeUpcoming: call.flag('upcoming') || query != null,
    tags: call.strings('tag').toSet(),
    searchQuery: query,
  ).value;
  final completed = call.string('status') == 'completed';
  // Search ignores filters and lists completed matches last, as in the app.
  final List<TaskViewEntry> entries = query != null
      ? [...view.open, ...view.completed]
      : completed
      ? view.completed
      : view.open;
  final heading = query != null
      ? 'Search "$query"'
      : '${completed ? 'Completed' : 'Open'} tasks'
            '${assignee == null ? '' : ' for ${names[assignee]}'}'
            '${call.strings('tag').isEmpty ? '' : ' tagged ${call.strings('tag').map((t) => '#$t').join(' ')}'}';
  final page = Page.of(
    entries,
    limit: call.integer('limit'),
    cursor: call.string('cursor'),
    query: '$heading|${call.flag('upcoming')}',
  );
  final year = tz.TZDateTime.from(time.instant, timeZoneLocation(zone)).year;
  final tasks = [
    for (final e in page.rows) taskJson(call, e.task, names: names),
  ];
  // The text form is built after the workspace closes: no store reads here.
  return AgentResult.lazy(
    {'view': heading, 'total': page.total, 'tasks': tasks, 'next': page.next},
    () => capText(
      [
        for (var i = 0; i < page.rows.length; i++)
          taskLine(
            call,
            page.rows[i].task,
            year,
            names: names,
            rev: tasks[i]['rev'] as String,
          ),
      ],
      header: '$heading · ${page.total}',
      page: page,
    ),
    nextAfter: page.after,
  );
}

FoodState foodState(AgentCall call) => call.ws.session.food.state;

FoodContainer foodContainer(AgentCall call, String input) {
  final all = {for (final c in foodState(call).containers) c.id: c};
  return all[resolveId(input, all.keys, 'container')]!;
}

const _foodFilterArgs = [
  AgentArg(
    'view',
    'string',
    'Stock (with Inbox and Running low), retained or deleted.',
    choices: ['stock', 'retained', 'deleted'],
  ),
  AgentArg('brand', 'string', 'Brand filter (OR within).', repeated: true),
  AgentArg(
    'location',
    'string',
    'Location filter (OR within).',
    repeated: true,
  ),
  AgentArg('reason', 'string', 'Retention reason (OR within).', repeated: true),
];

Future<AgentResult> _food(AgentCall call, {String? query}) async {
  final view = switch (call.string('view')) {
    'retained' => FoodView.retained,
    'deleted' => FoodView.deleted,
    _ => FoodView.inventory,
  };
  final rows = FoodRows(
    state: foodState(call),
    view: view,
    query: query ?? '',
    reasons: call.strings('reason').toSet(),
    brands: call.strings('brand').toSet(),
    locations: call.strings('location').toSet(),
  );
  final tagged = [
    for (final g in rows.inbox) ('inbox', g),
    for (final g in rows.groups)
      (view.name == 'inventory' ? 'stock' : view.name, g),
    for (final g in rows.deletedGroups) ('deleted', g),
  ];
  final heading = query != null
      ? 'Food search "$query"'
      : 'Food ${call.string('view') ?? 'stock'}';
  final page = Page.of(
    tagged,
    limit: call.integer('limit'),
    cursor: call.string('cursor'),
    query:
        '$heading|${([for (final e in call.args.entries)
          if (e.key != 'cursor' && e.key != 'limit') '${e.key}=${e.value}']..sort()).join('&')}',
    rowKey: (r) => revOf('${r.$1}|${r.$2.key}'),
  );
  final year = tz.TZDateTime.from(
    DateTime.now().toUtc(),
    timeZoneLocation(call.options.timeZone!),
  ).year;
  final low = view == FoodView.inventory && query == null
      ? foodState(call).runningLow
      : const [];
  return AgentResult(
    {
      'view': heading,
      'total': page.total,
      'rows': [
        for (final (i, (section, g)) in page.rows.indexed)
          {
            'section': section,
            ...foodGroupJson(g, from: i == 0 ? page.memberOffset : 0),
          },
      ],
      if (low.isNotEmpty)
        'runningLow': [
          for (final p in low)
            {
              'product': p.id,
              'name': p.name,
              'onHand': p.onHand,
              'minimum': p.minimum,
            },
        ],
      'next': page.next,
    },
    capText(
      [
        if (low.isNotEmpty)
          'Running low: ${low.map((p) => '${p.name} ${p.onHand}/${p.minimum}').join(', ')}',
        for (final (section, g) in page.rows)
          '${section == 'stock' ? '' : '[$section] '}${foodGroupLine(g, year)}',
      ],
      header: '$heading · ${page.total} rows',
      page: page,
      leading: low.isNotEmpty ? 1 : 0,
    ),
    nextAfter: page.after,
    nextWithinFirst: page.within,
    membersField: 'containers',
  );
}

Map<String, Object?> productJson(dynamic p) => {
  'id': p.id,
  'name': p.name,
  'brand': p.brand,
  'size': p.size,
  'links': p.links,
  'minimum': p.minimum,
  'onHand': p.onHand,
  'containers': p.containers,
  'runningLow': p.runningLow,
  'rev': productRev(p),
  if (p.last != null)
    'lastPurchase': {
      'date': p.last.date,
      'store': p.last.store,
      'amount': p.last.amount,
      'currency': p.last.currency,
      'quantity': p.last.quantity,
    },
};

/// A product's rev hashes its described fields (name, brand, size, links,
/// minimum); a Food container's hashes its projected state. Both are
/// projected-state revisions, unlike a task's admitted operation IDs (see the
/// feasibility record).
String productRev(dynamic p) =>
    revOf([p.id, p.name, p.brand, p.size, p.links, p.minimum]);

/// Current rev of any Food target an action can name: a container, a live or
/// merged-away product, or a purchase. Null when the ID names none of them.
String? foodTargetRev(FoodState state, String id) {
  for (final c in state.containers) {
    if (c.id == id) return foodRev(c);
  }
  final product = state.products[id];
  if (product != null) return productRev(product);
  final catalog = state.catalog;
  if (catalog.aliases.containsKey(id)) {
    final root = state.products[catalog.resolve(id)];
    return revOf([
      'merged',
      id,
      catalog.resolve(id),
      catalog.products[id],
      root == null ? null : productRev(root),
    ]);
  }
  final purchase = catalog.purchases[id];
  if (purchase != null) {
    return revOf(['purchase', id, purchase.toJson(), purchase.voided]);
  }
  return null;
}

String productLine(dynamic p) => [
  '${shortId(p.id as String)} ${p.name}',
  if ((p.brand as String).isNotEmpty) p.brand,
  if ((p.size as String).isNotEmpty) p.size,
  'on hand ${p.onHand}${p.minimum == null ? '' : '/min ${p.minimum}'}',
  if (p.runningLow == true) 'running low',
  if ((p.links as List).isNotEmpty) (p.links as List).first,
].join(' · ');

String _eventTime(BigInt clock) {
  try {
    return DateTime.fromMicrosecondsSinceEpoch(
      (clock ~/ BigInt.from(1000)).toInt(),
      isUtc: true,
    ).toIso8601String();
  } catch (_) {
    return clock.toString();
  }
}

List<AgentCommand> readCommands() => [
  AgentCommand(
    'context',
    'People, tags, Food vocabulary, counts, Running low, writers and versions.',
    CommandKind.read,
    const [],
    (call) async {
      final s = call.ws.session;
      final names = people(call);
      final tasks = s.tasks.rows.where(
        (r) => r['kind'] == 'task' && r['deleted'] != true,
      );
      final tags = <String>{
        for (final t in tasks)
          ...(t['tags'] as List? ?? const []).cast<String>(),
      }.toList()..sort();
      final food = s.food.state;
      final snapshot = s.history.snapshot;
      final writers = {
        for (final r in snapshot.records)
          r.writer: snapshot.deviceLabel(r.writer),
      };
      final counts = {
        'openTasks': tasks.where((t) => t['completed'] != true).length,
        'completedTasks': tasks.where((t) => t['completed'] == true).length,
        'foodStock': food
            .view(FoodView.inventory)
            .fold<int>(0, (n, g) => n + g.containers.length),
        'foodInbox': food
            .view(FoodView.inbox)
            .fold<int>(0, (n, g) => n + g.containers.length),
        'foodRetained': food
            .view(FoodView.retained)
            .fold<int>(0, (n, g) => n + g.containers.length),
        'products': food.products.length,
      };
      final data = {
        'people': [
          for (final e in names.entries) {'id': e.key, 'name': e.value},
        ],
        'tags': tags,
        'brands': food.brands,
        'locations': food.locations,
        'reasons': food.reasons,
        'counts': counts,
        'runningLow': [
          for (final p in food.runningLow)
            {
              'product': p.id,
              'name': p.name,
              'onHand': p.onHand,
              'minimum': p.minimum,
            },
        ],
        'writers': [
          for (final e in writers.entries)
            {'id': e.key, 'name': e.value, 'self': e.key == call.ws.writer},
        ],
        'timeZone': call.options.timeZone,
      };
      return AgentResult(
        data,
        [
          'People: ${names.entries.map((e) => '${e.value} (${shortId(e.key)})').join(', ')}',
          'Tags: ${tags.map((t) => '#$t').join(' ')}',
          'Food: ${counts['foodStock']} in stock, ${counts['foodInbox']} in Inbox, ${counts['foodRetained']} retained; ${counts['products']} products',
          if (food.runningLow.isNotEmpty)
            'Running low: ${food.runningLow.map((p) => '${p.name} ${p.onHand}/${p.minimum}').join(', ')}',
          'Locations: ${food.locations.join(', ')}',
          'Brands: ${food.brands.join(', ')}',
          'Tasks: ${counts['openTasks']} open, ${counts['completedTasks']} completed',
          'Writers: ${writers.entries.map((e) => '${e.value}${e.key == call.ws.writer ? ' (me)' : ''}').join(', ')}',
          'Time zone: ${call.options.timeZone}',
        ].join('\n'),
      );
    },
  ),
  AgentCommand(
    'tasks list',
    'Tasks as the app shows them, with the app\'s filters.',
    CommandKind.read,
    _taskListArgs,
    (call) => _tasks(call),
    paged: true,
  ),
  AgentCommand(
    'tasks search',
    'Search titles and notes; ignores filters, completed matches last.',
    CommandKind.read,
    const [
      AgentArg(
        'query',
        'string',
        'Search text.',
        required: true,
        positional: true,
      ),
    ],
    (call) => _tasks(call, query: call.require('query')),
    paged: true,
  ),
  AgentCommand(
    'tasks show',
    'One task with full notes and checklist.',
    CommandKind.read,
    const [
      AgentArg(
        'id',
        'string',
        'Task ID or unique 8+ character prefix.',
        required: true,
        positional: true,
      ),
    ],
    (call) async {
      final ids = call.ws.session.tasks.rows
          .where((r) => r['kind'] == 'task')
          .map((r) => r['id'] as String);
      final id = resolveId(call.require('id'), ids, 'task');
      final t = taskRow(call, id)!;
      final json = taskJson(call, t, full: true);
      final year = DateTime.now().year;
      final checklist = t['checklist'] as List? ?? const [];
      return AgentResult(
        json,
        [
          taskLine(call, t, year),
          'id ${t['id']}',
          if ((t['description'] as String? ?? '').isNotEmpty)
            '\n${t['description']}',
          for (final item in checklist)
            if (item is Map)
              '${item['completed'] == true ? '[x]' : '[ ]'} ${shortId(item['id'] as String)} ${item['title'] ?? ''} · rev ${taskRev(call, item['id'] as String)}',
        ].join('\n'),
      );
    },
  ),
  AgentCommand(
    'food list',
    'Food rows: Running low, Inbox and Stock (or Retained/Deleted).',
    CommandKind.read,
    _foodFilterArgs,
    (call) => _food(call),
    paged: true,
  ),
  AgentCommand(
    'food search',
    'Search Food, including Deleted last.',
    CommandKind.read,
    [
      const AgentArg(
        'query',
        'string',
        'Search text.',
        required: true,
        positional: true,
      ),
      ..._foodFilterArgs,
    ],
    (call) => _food(call, query: call.require('query')),
    paged: true,
  ),
  AgentCommand(
    'food show',
    'One container with its row and product.',
    CommandKind.read,
    const [
      AgentArg(
        'id',
        'string',
        'Container ID or unique 8+ character prefix.',
        required: true,
        positional: true,
      ),
    ],
    (call) async {
      final c = foodContainer(call, call.require('id'));
      final product = foodState(call).products[c.product];
      final data = {
        'id': c.id,
        'rev': foodRev(c),
        'details': c.details.toJson(),
        'contents': c.contents.toString(),
        'deleted': c.deleted,
        'product': product == null ? null : productJson(product),
      };
      return AgentResult(
        data,
        [
          foodGroupLine(FoodGroup([c]), DateTime.now().year),
          'id ${c.id} · rev ${foodRev(c)}',
          if (product != null) 'product ${productLine(product)}',
        ].join('\n'),
      );
    },
  ),
  AgentCommand(
    'products list',
    'Products with on-hand counts; --running-low for those below minimum.',
    CommandKind.read,
    const [
      AgentArg('running-low', 'boolean', 'Only products below their minimum.'),
    ],
    (call) async {
      final state = foodState(call);
      final all =
          (call.flag('running-low')
                  ? state.runningLow
                  : (state.products.values.toList()..sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    )))
              .toList();
      final page = Page.of(
        all,
        limit: call.integer('limit'),
        cursor: call.string('cursor'),
        query: 'products|${call.flag('running-low')}',
      );
      return AgentResult(
        {
          'total': page.total,
          'products': [for (final p in page.rows) productJson(p)],
          'next': page.next,
        },
        capText(
          [for (final p in page.rows) productLine(p)],
          header:
              '${call.flag('running-low') ? 'Running low' : 'Products'} · ${page.total}',
          page: page,
        ),
        nextAfter: page.after,
      );
    },
    paged: true,
  ),
  AgentCommand(
    'products search',
    'Find products by name, brand or size.',
    CommandKind.read,
    const [
      AgentArg(
        'query',
        'string',
        'Search text.',
        required: true,
        positional: true,
      ),
    ],
    (call) async {
      final terms = call
          .require('query')
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty);
      final all = foodState(call).products.values.where((p) {
        final text = '${p.name} ${p.brand} ${p.size}'.toLowerCase();
        return terms.every(text.contains);
      }).toList();
      final page = Page.of(
        all,
        limit: call.integer('limit'),
        cursor: call.string('cursor'),
        query: 'psearch|${call.args['query']}',
      );
      return AgentResult(
        {
          'total': page.total,
          'products': [for (final p in page.rows) productJson(p)],
          'next': page.next,
        },
        capText(
          [for (final p in page.rows) productLine(p)],
          header: 'Products matching "${call.args['query']}" · ${page.total}',
          page: page,
        ),
        nextAfter: page.after,
      );
    },
    paged: true,
  ),
  AgentCommand(
    'products show',
    'One product with links, minimum and purchases.',
    CommandKind.read,
    const [
      AgentArg(
        'id',
        'string',
        'Product ID or unique 8+ character prefix.',
        required: true,
        positional: true,
      ),
    ],
    (call) async {
      final products = foodState(call).products;
      final p =
          products[resolveId(call.require('id'), products.keys, 'product')]!;
      return AgentResult(
        {
          ...productJson(p),
          'purchases': [
            for (final x in p.purchases)
              {
                'id': x.id,
                'date': x.date,
                'store': x.store,
                'amount': x.amount,
                'currency': x.currency,
                'quantity': x.quantity,
                'source': x.source,
              },
          ],
        },
        [
          productLine(p),
          'id ${p.id}',
          for (final x in p.purchases)
            '${x.date} ${x.store} ${x.quantity}× ${(x.amount / 100).toStringAsFixed(2)} ${x.currency}',
        ].join('\n'),
      );
    },
  ),
  AgentCommand(
    'purchases list',
    'Recorded purchases, newest first.',
    CommandKind.read,
    const [AgentArg('product', 'string', 'Only this product.')],
    (call) async {
      final state = foodState(call);
      final names = {for (final p in state.products.values) p.id: p.name};
      var all = state.catalog.purchases.values.where((x) => !x.voided).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      if (call.string('product') != null) {
        final id = resolveId(
          call.string('product')!,
          state.products.keys,
          'product',
        );
        all = all.where((x) => x.product == id).toList();
      }
      final page = Page.of(
        all,
        limit: call.integer('limit'),
        cursor: call.string('cursor'),
        query: 'purchases|${call.args['product']}',
      );
      return AgentResult(
        {
          'total': page.total,
          'purchases': [
            for (final x in page.rows)
              {
                'id': x.id,
                'product': x.product,
                'productName': names[x.product],
                'date': x.date,
                'store': x.store,
                'amount': x.amount,
                'currency': x.currency,
                'quantity': x.quantity,
                'source': x.source,
              },
          ],
          'next': page.next,
        },
        capText(
          [
            for (final x in page.rows)
              '${x.date} · ${names[x.product] ?? shortId(x.product)} · ${x.store} · ${x.quantity}× ${(x.amount / 100).toStringAsFixed(2)} ${x.currency}',
          ],
          header: 'Purchases · ${page.total}',
          page: page,
        ),
        nextAfter: page.after,
      );
    },
    paged: true,
  ),
  AgentCommand(
    'history',
    'Operations on one task, container or product, with writer names.',
    CommandKind.read,
    const [
      AgentArg(
        'id',
        'string',
        'Entity ID or unique 8+ character prefix.',
        required: true,
        positional: true,
      ),
    ],
    (call) async {
      final snapshot = call.ws.session.history.snapshot;
      final entities = <String>{};
      for (final r in snapshot.records) {
        for (final e in r.effects) {
          if (e.task != null) entities.add(e.task!.entity);
          if (e.food != null) entities.addAll(e.food!.operation.targets);
        }
      }
      final id = resolveId(call.require('id'), entities, 'entity');
      final ops = <Map<String, Object?>>[];
      for (final r in snapshot.records) {
        for (final e in r.effects) {
          final type = e.task?.entity == id
              ? e.task!.type
              : e.food != null && e.food!.operation.targets.contains(id)
              ? 'food.${e.food!.operation.action.name}'
              : null;
          if (type == null) continue;
          ops.add({
            'action': '${r.writer}:${r.sequence}',
            'type': type,
            'writer': r.writer,
            'writerName': snapshot.deviceLabel(r.writer),
            'at': _eventTime(r.clock.value),
          });
        }
      }
      return AgentResult(
        {'id': id, 'operations': ops},
        capText([
          for (final o in ops)
            '${o['at']} · ${o['type']} · ${o['writerName']} · action ${shortId(o['writer'] as String)}:${(o['action'] as String).split(':').last}',
        ], header: 'History of ${shortId(id)} · ${ops.length}'),
      );
    },
  ),
  AgentCommand(
    'verify',
    'Full read-only integrity audit (Settings → Check data integrity).',
    CommandKind.read,
    const [],
    (call) async {
      final store = call.ws.session.tasks;
      await store.verifyHistory();
      final v = store.lastHistoryVerification!;
      return AgentResult(
        {
          'passed': true,
          'logs': v.checkedLogCount,
          'records': v.checkedRecordCount,
          'bytes': v.checkedByteCount,
        },
        'Data integrity check passed: ${v.checkedLogCount} logs, ${v.checkedRecordCount} records, ${v.checkedByteCount} bytes.',
      );
    },
  ),
];
