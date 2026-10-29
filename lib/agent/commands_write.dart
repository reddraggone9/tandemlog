import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../application/task_text_session.dart';
import '../application/text_save_command.dart';
import '../application/workspace_session.dart';
import '../domain/schedule.dart';
import '../food/inventory.dart';
import '../storage/local_profile_database.dart';
import '../storage/local_settings.dart';
import '../storage/log_folder.dart';
import '../storage/profile_lock.dart';
import 'agent_profile.dart';
import 'agent_workspace.dart';
import 'command.dart';
import 'commands_read.dart';
import 'render.dart';
import 'overlay_folder.dart';
import 'text_undo.dart';
import '../storage/unified_record.dart' show UnifiedRecord;

const _ifRev = AgentArg(
  'if-rev',
  'string',
  'Current rev of the item (from list/show). Required for existing items.',
  required: true,
);
const _requestId = AgentArg(
  'request-id',
  'string',
  'UUID making a retried create idempotent; new IDs derive from it.',
);

/// IDs derived from `--request-id`, so a retried create is a no-op.
List<String>? requestIds(
  AgentCall call,
  int count, [
  String kind = 'container',
]) {
  final request = call.string('request-id');
  if (request == null) return null;
  if (!Uuid.isValidUUID(fromString: request)) {
    throw const AgentFailure(
      'validation',
      '--request-id must be a UUID.',
      details: {'field': 'request-id', 'error': 'invalid'},
    );
  }
  return [for (var i = 0; i < count; i++) const Uuid().v5(request, '$kind:$i')];
}

/// Own canonical action IDs (`writer:sequence`) appended since [before].
List<String> newActions(AgentCall call, int before) {
  final own =
      call.ws.session.history.snapshot.recordsByWriter[call.ws.writer] ??
      const [];
  return [
    for (final r in own)
      if (r.sequence > before) '${r.writer}:${r.sequence}',
  ];
}

int ownHead(AgentCall call) =>
    call
        .ws
        .session
        .history
        .snapshot
        .recordsByWriter[call.ws.writer]
        ?.lastOrNull
        ?.sequence ??
    0;

String _taskId(AgentCall call, String input) => resolveId(
  input,
  call.ws.session.tasks.rows
      .where((r) => r['kind'] == 'task')
      .map((r) => r['id'] as String),
  'task',
);

/// Fail fast on a stale or missing rev; the same check repeats inside the
/// store's serialized append so a peer arrival in between is also caught.
bool Function() taskGuard(AgentCall call, Map<String, String> expected) {
  for (final e in expected.entries) {
    final actual = taskRev(call, e.key);
    if (actual != e.value) {
      throw AgentFailure(
        'stale',
        'Task ${shortId(e.key)} changed (rev $actual, expected ${e.value}). Read it again.',
        details: {'id': e.key, 'rev': actual, 'expected': e.value},
      );
    }
  }
  return call.commitGuard(
    () => expected.entries.every((e) => taskRev(call, e.key) == e.value),
  );
}

/// Own records appended since [before].
List<UnifiedRecord> newRecords(AgentCall call, int before) => [
  for (final r
      in call.ws.session.history.snapshot.recordsByWriter[call.ws.writer] ??
          const <UnifiedRecord>[])
    if (r.sequence > before) r,
];

/// Task entities and Food targets (containers, products, purchases) whose
/// current revisions an Undo of [record] must name.
({Set<String> tasks, Set<String> food}) undoScope(UnifiedRecord record) {
  final tasks = <String>{}, food = <String>{};
  for (final e in record.effects) {
    if (e.task != null) tasks.add(e.task!.entity);
    final f = e.food;
    if (f != null) {
      food.addAll(f.operation.targets);
      if (f.operation.into != null) food.add(f.operation.into!);
    }
  }
  return (tasks: tasks, food: food);
}

const _creations = {
  'task.created',
  'task.createdWithText',
  'user.created',
  'checklist.itemCreated',
};
const _undoTypes = {
  'task.operationUndone',
  'task.textEditUndone',
  'task.recurringCompletionUndone',
};

/// Why an Undo of [record] is refused whole, or null if it can be undone.
String? undoRefusal(UnifiedRecord record) {
  final task = [
    for (final e in record.effects)
      if (e.task != null) e.task!,
  ];
  final food = [
    for (final e in record.effects)
      if (e.food != null) e.food!,
  ];
  if (task.any((e) => _undoTypes.contains(e.type)) ||
      food.any((r) => r.operation.action == FoodAction.undo)) {
    return 'This action is itself an Undo and is not undone again; redo the change instead. Nothing was changed.';
  }
  if (task.isNotEmpty && food.isNotEmpty) {
    return 'Mixed Task and Food actions cannot be undone as one unit yet. Nothing was changed.';
  }
  if (task.any((e) => _creations.contains(e.type))) {
    return 'Creating an item is not undone; delete it instead. Nothing was changed.';
  }
  if (task.any((e) => e.type == 'task.textEdited') && task.length != 1) {
    return 'This action mixes text with other operations. Nothing was changed.';
  }
  return null;
}

String _revText(String? rev) => rev ?? 'none';

/// Current rev of a Task entity or Food target named by an action.
String? currentRev(AgentCall call, String id, {required bool task}) =>
    task ? taskRev(call, id) : foodTargetRev(foodState(call), id);

/// Write output: action IDs, every affected item with its new rev, and the
/// complete Undo command (with current revs) when the action can be undone.
AgentResult writeResult(
  AgentCall call,
  int before,
  String summary,
  List<String> taskIds, {
  List<String> containerIds = const [],
  Map<String, Object?> extra = const {},
  int exitCode = 0,
}) {
  final actions = newActions(call, before);
  final records = newRecords(call, before);
  final state = foodState(call);
  final affected = <Map<String, Object?>>[];
  final seen = <String>{};
  void addTask(String id) {
    if (seen.add(id)) affected.add({'id': id, 'rev': taskRev(call, id)});
  }

  void addFood(String id) {
    final rev = foodTargetRev(state, id);
    if (rev != null && seen.add(id)) affected.add({'id': id, 'rev': rev});
  }

  taskIds.forEach(addTask);
  containerIds.forEach(addFood);
  for (final r in records) {
    final scope = undoScope(r);
    scope.tasks.forEach(addTask);
    scope.food.forEach(addFood);
  }
  String? undo;
  if (records.length == 1 && undoRefusal(records.single) == null) {
    final scope = undoScope(records.single);
    undo = [
      'tandemlog-cli undo ${actions.single}',
      for (final id in scope.tasks) '--rev=$id=${_revText(taskRev(call, id))}',
      for (final id in scope.food)
        '--rev=$id=${_revText(foodTargetRev(state, id))}',
    ].join(' ');
  }
  return AgentResult(
    {'actions': actions, 'affected': affected, 'undo': ?undo, ...extra},
    [
      summary,
      for (final a in affected) '${shortId(a['id'] as String)} rev ${a['rev']}',
      if (undo != null) 'undo: $undo',
    ].join('\n'),
    exitCode: exitCode,
  );
}

Map<String, String> _scheduleFields = const {
  'start': 'startDate',
  'start-time': 'startTime',
  'due': 'dueDate',
  'due-time': 'dueTime',
  'occurrence': 'scheduledDate',
  'occurrence-time': 'scheduledTime',
  'zone': 'timeZone',
  'repeat': 'recurrence',
};

List<AgentCommand> writeCommands() => [
  AgentCommand(
    'people add',
    'Add a person (as in the app\'s "Who is using Tandemlog?").',
    CommandKind.write,
    const [
      AgentArg('name', 'string', 'Name.', required: true, positional: true),
      _requestId,
    ],
    (call) async {
      final name = call.require('name').trim();
      if (name.isEmpty) {
        throw const AgentFailure(
          'validation',
          'Enter a name.',
          details: {'field': 'name', 'error': 'empty'},
        );
      }
      final request = call.string('request-id');
      final id = request == null
          ? const Uuid().v4()
          : const Uuid().v5(request, 'person');
      final store = call.ws.session.tasks;
      final before = ownHead(call);
      if (!store.hasEntity(id)) {
        await store.command(id, 'user.created', {'name': name});
      }
      return writeResult(
        call,
        before,
        'Added $name (${shortId(id)}).',
        const [],
        extra: {'id': id},
      );
    },
  ),
  AgentCommand(
    'tasks add',
    'Capture one task per title for an assignee.',
    CommandKind.write,
    const [
      AgentArg(
        'title',
        'string',
        'Task title (repeat for several tasks).',
        required: true,
        positional: true,
        repeated: true,
      ),
      AgentArg(
        'for',
        'string',
        'Assignee name or ID (default: profile person).',
      ),
      _requestId,
    ],
    (call) async {
      final person = call.string('for') ?? call.ws.settings.user;
      if (person == null) {
        throw const AgentFailure(
          'validation',
          'Choose an assignee with --for.',
          details: {'field': 'for', 'error': 'required'},
        );
      }
      final assignee = resolvePerson(call, person);
      final titles = call.strings('title').map((t) => t.trim()).toList();
      if (titles.any((t) => t.isEmpty)) {
        throw const AgentFailure(
          'validation',
          'A task title cannot be empty.',
          details: {'field': 'title', 'error': 'empty'},
        );
      }
      final request = call.string('request-id');
      if (request != null && !Uuid.isValidUUID(fromString: request)) {
        throw const AgentFailure(
          'validation',
          '--request-id must be a UUID.',
          details: {'field': 'request-id', 'error': 'invalid'},
        );
      }
      final ids = [
        for (var i = 0; i < titles.length; i++)
          request == null
              ? const Uuid().v4()
              : const Uuid().v5(request, 'task:$i'),
      ];
      final before = ownHead(call);
      await call.ws.session.tasks.createTasks({
        for (var i = 0; i < titles.length; i++) ids[i]: titles[i],
      }, assignee);
      return writeResult(
        call,
        before,
        'Added ${titles.length} task${titles.length == 1 ? '' : 's'}.',
        ids,
      );
    },
  ),
  AgentCommand(
    'tasks complete',
    'Complete a task (a repeating task advances once).',
    CommandKind.write,
    const [
      AgentArg(
        'id',
        'string',
        'Task ID or prefix.',
        required: true,
        positional: true,
      ),
      _ifRev,
    ],
    (call) async {
      final id = _taskId(call, call.require('id'));
      final guard = taskGuard(call, {id: call.require('if-rev')});
      final before = ownHead(call);
      await call.ws.session.tasks.complete(
        id,
        observeCompletionTime: () => viewTime(call, call.options.timeZone!),
        requireIncomplete: true,
        canCommit: guard,
      );
      return writeResult(call, before, 'Completed ${shortId(id)}.', [id]);
    },
  ),
  AgentCommand(
    'tasks reopen',
    'Reopen a completed task.',
    CommandKind.write,
    const [
      AgentArg(
        'id',
        'string',
        'Task ID or prefix.',
        required: true,
        positional: true,
      ),
      _ifRev,
    ],
    (call) async {
      final id = _taskId(call, call.require('id'));
      final guard = taskGuard(call, {id: call.require('if-rev')});
      final store = call.ws.session.tasks;
      final active = store.activeCompletionIds(id);
      if (active.isEmpty) {
        throw const AgentFailure('validation', 'This task is not completed.');
      }
      final before = ownHead(call);
      await store.reopen(id, active, canCommit: guard);
      return writeResult(call, before, 'Reopened ${shortId(id)}.', [id]);
    },
  ),
  AgentCommand(
    'tasks delete',
    'Delete a task (recoverable with undo).',
    CommandKind.write,
    const [
      AgentArg(
        'id',
        'string',
        'Task ID or prefix.',
        required: true,
        positional: true,
      ),
      _ifRev,
    ],
    (call) async {
      final id = _taskId(call, call.require('id'));
      final guard = taskGuard(call, {id: call.require('if-rev')});
      final before = ownHead(call);
      await call.ws.session.tasks.deleteTask(
        id,
        expectedTaskSnapshot: null,
        canCommit: guard,
      );
      return writeResult(call, before, 'Deleted ${shortId(id)}.', [id]);
    },
    destructive: true,
  ),
  AgentCommand(
    'tasks edit',
    'Edit title, notes, schedule, assignee or tags of one task.',
    CommandKind.write,
    const [
      AgentArg(
        'id',
        'string',
        'Task ID or prefix.',
        required: true,
        positional: true,
      ),
      _ifRev,
      AgentArg('title', 'string', 'New title.'),
      AgentArg('notes', 'string', 'New notes (replaces them).'),
      AgentArg('start', 'string', 'Start date YYYY-MM-DD, or "none".'),
      AgentArg('start-time', 'string', 'Start time HH:MM, or "none".'),
      AgentArg('due', 'string', 'Due date YYYY-MM-DD, or "none".'),
      AgentArg('due-time', 'string', 'Due time HH:MM, or "none".'),
      AgentArg('occurrence', 'string', 'This occurrence date, or "none".'),
      AgentArg('occurrence-time', 'string', 'This occurrence time, or "none".'),
      AgentArg('zone', 'string', 'IANA zone for times, or "none" (floating).'),
      AgentArg(
        'repeat',
        'string',
        'Repeat rule as stored by the app, or "none".',
      ),
      AgentArg('for', 'string', 'New assignee name or ID.'),
      AgentArg('tag', 'string', 'Add a tag.', repeated: true),
      AgentArg('untag', 'string', 'Remove a tag.', repeated: true),
    ],
    (call) async {
      final store = call.ws.session.tasks;
      final id = _taskId(call, call.require('id'));
      final guard = taskGuard(call, {id: call.require('if-rev')});
      final row = taskRow(call, id)!;
      final schedule = Map<String, dynamic>.from(row['schedule'] as Map);
      var scheduleChanged = false;
      for (final e in _scheduleFields.entries) {
        final v = call.string(e.key);
        if (v == null) continue;
        schedule[e.value] = v == 'none' ? null : v;
        scheduleChanged = true;
      }
      final fields = <String, dynamic>{};
      if (scheduleChanged) {
        try {
          store.timeZonePolicy.assertScheduleAllowed(schedule);
          fields['schedule'] = TaskSchedule.fromJson(schedule).toJson();
        } on ScheduleValidationException catch (e) {
          throw AgentFailure(
            'validation',
            e.message,
            details: [
              for (final f in e.fields) {'field': f, 'error': e.message},
            ],
          );
        }
      }
      if (call.string('for') != null) {
        final assignee = resolvePerson(call, call.string('for')!);
        if (assignee != row['assignee']) fields['assignee'] = assignee;
      }
      final current = (row['tags'] as List? ?? const []).cast<String>();
      final tags = {...current, ...call.strings('tag')}
        ..removeAll(call.strings('untag'));
      final title = call.string('title')?.trim();
      if (title != null && title.isEmpty) {
        throw const AgentFailure(
          'validation',
          'A task title cannot be empty.',
          details: {'field': 'title', 'error': 'empty'},
        );
      }
      final textChanges = {
        if (title != null && title != row['title']) 'title': title,
        if (call.string('notes') != null &&
            call.string('notes') != row['description'])
          'description': call.string('notes')!,
      };
      final observedTagRefs = Map<String, String>.from(
        row['tagRefs'] as Map? ?? {},
      );
      final before = ownHead(call);
      if (textChanges.isEmpty) {
        if (fields.isEmpty &&
            tags.length == current.length &&
            tags.containsAll(current)) {
          return writeResult(call, before, 'No changes.', [id]);
        }
        await store.edit(
          id,
          fields,
          tags: tags.toList(),
          observedTagRefs: observedTagRefs,
          canCommit: guard,
        );
      } else {
        final capture = await store.captureTaskText(id);
        final session = TaskTextSession(capture);
        try {
          for (final e in textChanges.entries) {
            session.replace(e.key, e.value);
          }
          final saved = await TextSaveCommand(store, session).save(
            fields: fields,
            tags: tags.toList(),
            observedTagRefs: observedTagRefs,
            canCommit: guard,
          );
          if (saved.status == TextSaveStatus.unchanged) {
            return writeResult(call, before, 'No changes.', [id]);
          }
        } finally {
          session.cancel();
        }
      }
      return writeResult(call, before, 'Saved ${shortId(id)}.', [id]);
    },
  ),
  AgentCommand(
    'food add',
    'Add containers of one item (expiry required unless --inbox).',
    CommandKind.write,
    const [
      AgentArg('name', 'string', 'Item name.', required: true),
      AgentArg('brand', 'string', 'Brand.'),
      AgentArg('size', 'string', 'Size, e.g. "1 gal".'),
      AgentArg('expiry', 'string', 'Expiry date YYYY-MM-DD.'),
      AgentArg('inbox', 'boolean', 'Add to Inbox without an expiry.'),
      AgentArg('location', 'string', 'Location.'),
      AgentArg('count', 'integer', 'Number of containers (default 1).'),
      _requestId,
    ],
    (call) async {
      final count = call.integer('count') ?? 1;
      if (count < 1 || count > 100) {
        throw const AgentFailure(
          'validation',
          'Count must be 1–100.',
          details: {'field': 'count', 'error': 'range'},
        );
      }
      final expiry = call.string('expiry');
      if (expiry == null && !call.flag('inbox')) {
        throw const AgentFailure(
          'validation',
          'Enter an expiry date or use --inbox.',
          details: {'field': 'expiry', 'error': 'required'},
        );
      }
      final store = call.ws.session.food;
      final known = {for (final c in store.state.containers) c.id};
      final before = ownHead(call);
      await store.add(
        FoodDetails(
          name: call.require('name').trim(),
          brand: call.string('brand')?.trim() ?? '',
          size: call.string('size')?.trim() ?? '',
          expiry: expiry,
          location: call.string('location')?.trim() ?? '',
        ),
        count,
        ids: requestIds(call, count),
      );
      final added = [
        for (final c in store.state.containers)
          if (!known.contains(c.id)) c.id,
      ];
      return writeResult(
        call,
        before,
        'Added $count ${call.require('name')}.',
        const [],
        containerIds: added,
      );
    },
  ),
  AgentCommand(
    'food remove',
    'Remove containers (recoverable with restore or undo).',
    CommandKind.write,
    const [
      AgentArg(
        'id',
        'string',
        'Container ID or prefix.',
        required: true,
        positional: true,
        repeated: true,
      ),
      AgentArg(
        'if-rev',
        'string',
        'Rev of each container, in the same order.',
        required: true,
        repeated: true,
      ),
    ],
    (call) async {
      final ids = [
        for (final i in call.strings('id')) foodContainer(call, i).id,
      ];
      final guard = foodGuard(call, ids, call.strings('if-rev'));
      final before = ownHead(call);
      await call.ws.session.food.remove(ids, canCommit: guard);
      return writeResult(
        call,
        before,
        'Removed ${ids.length}.',
        const [],
        containerIds: ids,
      );
    },
    requiresPlan: true,
    planWhen: (args) => (args['id'] as List).length > 1,
    destructive: true,
  ),
  AgentCommand(
    'food restore',
    'Restore removed containers.',
    CommandKind.write,
    const [
      AgentArg(
        'id',
        'string',
        'Container ID or prefix.',
        required: true,
        positional: true,
        repeated: true,
      ),
      AgentArg(
        'if-rev',
        'string',
        'Rev of each container, in the same order.',
        required: true,
        repeated: true,
      ),
    ],
    (call) async {
      final containers = [
        for (final i in call.strings('id')) foodContainer(call, i),
      ];
      final guard = foodGuard(call, [
        for (final c in containers) c.id,
      ], call.strings('if-rev'));
      final before = ownHead(call);
      await call.ws.session.food.restore(containers, canCommit: guard);
      return writeResult(
        call,
        before,
        'Restored ${containers.length}.',
        const [],
        containerIds: [for (final c in containers) c.id],
      );
    },
    requiresPlan: true,
    planWhen: (args) => (args['id'] as List).length > 1,
  ),
  AgentCommand(
    'undo',
    'Undo one whole earlier action by this agent.',
    CommandKind.write,
    const [
      AgentArg(
        'action',
        'string',
        'Action ID from a write result (writer:sequence).',
        required: true,
        positional: true,
      ),
      AgentArg(
        'rev',
        'string',
        'Current revision of each item the action changed, as id=rev.',
        repeated: true,
      ),
    ],
    (call) => undoAction(call),
  ),
];

/// Check container revs now and again inside the store's append.
bool Function() foodGuard(AgentCall call, List<String> ids, List<String> revs) {
  if (ids.length != revs.length) {
    throw const AgentFailure(
      'validation',
      'Give one --if-rev per container, in order.',
      details: {'field': 'if-rev', 'error': 'count'},
    );
  }
  String? actual(String id) {
    for (final c in foodState(call).containers) {
      if (c.id == id) return foodRev(c);
    }
    return null;
  }

  for (var i = 0; i < ids.length; i++) {
    final rev = actual(ids[i]);
    if (rev != revs[i]) {
      throw AgentFailure(
        'stale',
        'Container ${shortId(ids[i])} changed (rev $rev, expected ${revs[i]}). Read it again.',
        details: {'id': ids[i], 'rev': rev, 'expected': revs[i]},
      );
    }
  }
  return call.commitGuard(() {
    for (var i = 0; i < ids.length; i++) {
      if (actual(ids[i]) != revs[i]) return false;
    }
    return true;
  });
}

/// Whole-action Undo of this installation's own action, across processes.
/// Text contributions are retracted selectively (text_undo.dart); anything
/// that cannot be undone refuses the whole action (`undo_unavailable`).
Future<AgentResult> undoAction(AgentCall call) async {
  final input = call.require('action');
  final parts = input.split(':');
  final seq = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (seq == null || parts[0].isEmpty) {
    throw const AgentFailure(
      'validation',
      'Use the action ID from a write result (writer:sequence).',
      details: {'field': 'action', 'error': 'invalid'},
    );
  }
  final snapshot = call.ws.session.history.snapshot;
  final writer = call.ws.writer;
  if (!writer.startsWith(parts[0].toLowerCase())) {
    throw const AgentFailure(
      'validation',
      'An agent can undo only its own actions.',
      details: {'field': 'action', 'error': 'not_own'},
    );
  }
  final record = (snapshot.recordsByWriter[writer] ?? const [])
      .where((r) => r.sequence == seq)
      .firstOrNull;
  if (record == null) throw AgentFailure('not_found', 'No action $input.');
  final refusal = undoRefusal(record);
  if (refusal != null) throw AgentFailure('undo_unavailable', refusal);
  final taskOps = [
    for (final e in record.effects)
      if (e.task != null) e.task!,
  ];
  final foodOps = [
    for (final e in record.effects)
      if (e.food != null) e.food!,
  ];
  final before = ownHead(call);
  final scope = undoScope(record);
  final guard = _undoGuard(call, scope.tasks, scope.food);
  final text = taskOps.where((e) => e.type == 'task.textEdited').toList();
  if (text.isNotEmpty) {
    final target = text.single;
    if (_undone(snapshot, target.id)) {
      return writeResult(
        call,
        before,
        'Already undone.',
        scope.tasks.toList(),
        extra: {'alreadyUndone': true},
      );
    }
    final changes = await AgentTextUndo(
      call.ws.session.tasks,
      call.ws.textEngine,
      writer,
    ).prepare(target);
    await call.ws.session.tasks.command(target.entity, 'task.textEditUndone', {
      'operation': target.id,
      'changes': changes,
    }, canCommit: guard);
  } else if (taskOps.isNotEmpty) {
    final result = await call.ws.session.tasks.undoOperations([
      for (final e in taskOps) e.id,
    ], canCommit: guard);
    if (result.error != null) throw result.error!;
  } else {
    await call.ws.session.food.undoOperations(foodOps, canCommit: guard);
  }
  if (newActions(call, before).isEmpty) {
    return writeResult(
      call,
      before,
      'Already undone.',
      scope.tasks.toList(),
      containerIds: scope.food.toList(),
      extra: {'alreadyUndone': true},
    );
  }
  return writeResult(
    call,
    before,
    'Undid $input.',
    scope.tasks.where((id) => taskRow(call, id) != null).toList(),
    containerIds: scope.food.toList(),
  );
}

bool _undone(dynamic snapshot, String operation) {
  for (final r in snapshot.records) {
    for (final e in r.effects) {
      final t = e.task;
      if (t != null &&
          (t.type == 'task.textEditUndone' ||
              t.type == 'task.operationUndone') &&
          t.data['operation'] == operation) {
        return true;
      }
    }
  }
  return false;
}

/// Undo names the current revision of everything the action changed, so it
/// never silently reverts over a change the agent has not seen. A target that
/// no longer exists (for example a retracted purchase) has rev `none`.
bool Function() _undoGuard(
  AgentCall call,
  Set<String> tasks,
  Set<String> food,
) {
  final given = <String, String>{};
  for (final pair in call.strings('rev')) {
    final eq = pair.lastIndexOf('=');
    if (eq < 1) {
      throw AgentFailure(
        'validation',
        'Write each revision as id=rev ("$pair").',
        details: {'field': 'rev', 'error': 'format'},
      );
    }
    given[resolveId(pair.substring(0, eq), {...tasks, ...food}, 'item')] = pair
        .substring(eq + 1);
  }
  String current(String id) =>
      _revText(currentRev(call, id, task: tasks.contains(id)));

  final missing = [
    for (final id in {...tasks, ...food})
      if (!given.containsKey(id)) id,
  ];
  if (missing.isNotEmpty) {
    throw AgentFailure(
      'validation',
      'Undo needs --rev for ${missing.map(shortId).join(', ')}.',
      details: {
        'field': 'rev',
        'error': 'missing',
        'revs': {for (final id in missing) id: current(id)},
      },
    );
  }
  for (final e in given.entries) {
    final now = current(e.key);
    if (now != e.value) {
      throw AgentFailure(
        'stale',
        'Item ${shortId(e.key)} changed (rev $now, expected ${e.value}). Read it again.',
        details: {'id': e.key, 'rev': now, 'expected': e.value},
      );
    }
  }
  return call.commitGuard(
    () => given.entries.every((e) => current(e.key) == e.value),
  );
}

/// Dry run: perform the command on disposable copies of the profile and the
/// workspace, report the resulting typed effects and a planHash, discard.
/// `inputHash` identifies the observed state the plan was computed from; a
/// planned commit appends only while the workspace still has that state.
Future<AgentResult> dryRunWrite(
  AgentCommand command,
  Map<String, Object?> args,
  AgentOptions options,
  AgentProfile profile, {
  ProfileLock? held,
}) async {
  await profile.requireAgentProfile();
  final lock = held ?? await profile.lock(options.wait);
  final scratch = await Directory.systemTemp.createTemp('tandemlog-cli-plan-');
  Directory? copy;
  try {
    copy = await profile.readCopy();
    // Copy-on-write: only files the command writes are copied. The profile
    // copy keeps the real workspace location, so its warm cache applies.
    final shadow = Directory('${scratch.path}/workspace');
    await shadow.create();
    final before = await AgentWorkspace.open(
      AgentProfile(copy.path),
      readOnly: false,
      wait: options.wait,
      folderFor: (location) => OverlayLogFolder(shadow.path, location),
      disposable: true,
    );
    final beforeState = _observe(AgentCall(args, before, options));
    AgentResult result;
    _Observed afterState;
    try {
      result = await command.run(
        AgentCall(
          {...args}
            ..remove('dry-run')
            ..remove('expect-plan'),
          before,
          options,
        ),
      );
      afterState = _observe(AgentCall(args, before, options));
    } finally {
      await before.close();
    }
    final effects = [
      ..._diff(beforeState.entities, afterState.entities),
      ..._orderEffects(beforeState.order, afterState.order),
    ]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final planHash = revOf({
      'command': command.name,
      'args': {...args}
        ..remove('dry-run')
        ..remove('expect-plan'),
      'effects': _stable(effects),
    });
    final outcome = {
      for (final e in result.data.entries)
        if (!const {'actions', 'affected', 'undo'}.contains(e.key))
          e.key: e.value,
    };
    return AgentResult(
      {
        ...outcome,
        'dryRun': true,
        'planHash': planHash,
        'effects': effects,
        'inputHash': beforeState.hash,
      },
      [
        'Dry run: ${command.name} (nothing written)',
        for (final e in effects)
          '${shortId(e['id'] as String)} ${e['change']}${e['fields'] == null ? '' : ' ${jsonEncode(e['fields'])}'}',
        'planHash: $planHash',
        if (result.data['affected'] == null) result.text,
      ].join('\n'),
    );
  } finally {
    if (held == null) await lock.close();
    await scratch.delete(recursive: true);
    await copy?.delete(recursive: true);
  }
}

/// Order is reported separately as moves (see [_orderEffects]); the other
/// keys are device-local or derived.
const _volatile = {'order', 'completionOrder', 'completedMicros', 'tagRefs'};

/// Observation times differ between a dry run and its commit; the plan binds
/// targets and field changes, not the clock reading.
const _clockFields = {
  'completedInstant',
  'createdAt',
  'deletedAt',
  'deletedOrder',
};

Object? _stable(Object? value) => switch (value) {
  Map m => {
    for (final e in m.entries)
      if (!_clockFields.contains(e.key)) e.key: _stable(e.value),
  },
  List l => [for (final x in l) _stable(x)],
  _ => value,
};

/// What a plan can change: task and checklist rows, the visible task order,
/// Food containers, products (including merges) and purchases.
class _Observed {
  _Observed(this.entities, this.order);
  final Map<String, Object?> entities;
  final List<String> order;
  String get hash => sha256
      .convert(utf8.encode(jsonEncode({'entities': entities, 'order': order})))
      .toString();
}

_Observed _observe(AgentCall call) {
  final rows = call.ws.session.tasks.rows;
  final state = call.ws.session.food.state;
  final catalog = state.catalog;
  return _Observed(
    {
      for (final r in rows)
        r['id'] as String: {
          for (final e in r.entries)
            if (!_volatile.contains(e.key)) e.key: e.value,
        },
      for (final c in state.containers)
        c.id: jsonDecode(jsonEncode(c.toJson())),
      for (final id in catalog.aliases.keys)
        id: {'kind': 'product', 'mergedInto': catalog.resolve(id)},
      for (final p in state.products.values)
        p.id: {
          'kind': 'product',
          'name': p.name,
          'brand': p.brand,
          'size': p.size,
          'links': p.links,
          'minimum': p.minimum,
        },
      for (final x in catalog.purchases.values)
        x.id: {'kind': 'purchase', ...x.toJson(), 'voided': x.voided},
    },
    [
      for (final r in rows)
        if (r['kind'] == 'task') r['id'] as String,
    ],
  );
}

/// Hash of everything a plan observes, for the in-append plan check.
String observedStateHash(AgentCall call) => _observe(call).hash;

List<Map<String, Object?>> _diff(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  final out = <Map<String, Object?>>[];
  final ids = {...before.keys, ...after.keys}.toList()..sort();
  for (final id in ids) {
    final a = before[id] as Map?, b = after[id] as Map?;
    if (a == null) {
      out.add({'id': id, 'change': 'created', 'fields': b});
    } else if (b == null) {
      out.add({'id': id, 'change': 'removed'});
    } else if (jsonEncode(a) != jsonEncode(b)) {
      out.add({
        'id': id,
        'change': 'changed',
        'fields': {
          for (final k in {...a.keys, ...b.keys})
            if (jsonEncode(a[k]) != jsonEncode(b[k]))
              k: {'from': a[k], 'to': b[k]},
        },
      });
    }
  }
  return out;
}

/// Tasks whose place in the visible order changed: every task outside one
/// longest kept subsequence, with the task it now precedes (`null` = end).
List<Map<String, Object?>> _orderEffects(
  List<String> before,
  List<String> after,
) {
  final position = {for (var i = 0; i < before.length; i++) before[i]: i};
  final common = [
    for (final id in after)
      if (position.containsKey(id)) id,
  ];
  // Longest increasing subsequence of old positions, in new order.
  final tails = <int>[], previous = List<int>.filled(common.length, -1);
  for (var i = 0; i < common.length; i++) {
    final p = position[common[i]]!;
    var lo = 0, hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (position[common[tails[mid]]]! < p) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0) previous[i] = tails[lo - 1];
    if (lo == tails.length) {
      tails.add(i);
    } else {
      tails[lo] = i;
    }
  }
  final kept = <String>{};
  for (var i = tails.isEmpty ? -1 : tails.last; i >= 0; i = previous[i]) {
    kept.add(common[i]);
  }
  final afterIndex = {for (var i = 0; i < after.length; i++) after[i]: i};
  String? next(List<String> list, int i) =>
      i + 1 < list.length ? list[i + 1] : null;
  return [
    for (final id in common)
      if (!kept.contains(id))
        {
          'id': id,
          'change': 'moved',
          'fields': {
            'before': {
              'from': next(before, position[id]!),
              'to': next(after, afterIndex[id]!),
            },
          },
        },
  ];
}

/// `init`: create this agent's private profile and join the workspace.
AgentCommand initCommand() => AgentCommand(
  'init',
  'Create this agent\'s profile and join a synced workspace folder.',
  CommandKind.setup,
  const [
    AgentArg(
      'workspace',
      'string',
      'The synced TandemLog folder.',
      required: true,
    ),
    AgentArg(
      'name',
      'string',
      'Writer name shown to people, e.g. "Vex".',
      required: true,
    ),
    AgentArg('person', 'string', 'Default assignee name for captures.'),
    AgentArg(
      'create',
      'boolean',
      'Allow creating a new workspace in an empty folder.',
    ),
  ],
  (call) async {
    final profile = call.profile!;
    final folder = Directory(call.require('workspace')).absolute;
    if (!await folder.exists()) {
      throw AgentFailure(
        'validation',
        'No folder at ${folder.path}.',
        details: {'field': 'workspace', 'error': 'missing'},
      );
    }
    final location = await folder.resolveSymbolicLinks();
    if (await folder.list().isEmpty && !call.flag('create')) {
      throw const AgentFailure(
        'validation',
        'The folder is empty. Pass --create to start a new workspace there.',
        details: {'field': 'workspace', 'error': 'empty'},
      );
    }
    // Load native code before creating anything. The identity lock is held
    // for the whole of init, so concurrent inits of one profile serialize and
    // all but the first find it non-empty. On failure before joining, only
    // the files this init created are removed (never the lock or a peer's).
    final engine = agentTextEngine();
    ProfileLock? lock;
    var created = false;
    LocalProfileDatabase? db;
    WorkspaceSession? session;
    String? writer;
    var joined = false;
    try {
      lock = await profile.lock(call.options.wait);
      await profile.createMarker();
      created = true;
      db = await LocalProfileDatabase.open(profile.root);
      await LocalSettings.initialize(db);
      final settings = LocalSettings(db.root, profileDatabase: db);
      await settings.load();
      settings.folder = location;
      await settings.save();
      writer = settings.writer;
      session = await WorkspaceSession.open(
        LocalLogFolder(location),
        profile: db,
        writer: settings.writer,
        textEngine: engine,
      );
      // From here the installation exists in shared history; keep its
      // profile even if a later step fails, so it is never orphaned.
      joined = true;
      await session!.history.renameDevice(call.require('name'));
      String? warning;
      final person = call.string('person');
      if (person != null) {
        final users = {
          for (final r in session.tasks.rows)
            if (r['kind'] == 'user')
              r['id'] as String: r['name'] as String? ?? '',
        };
        final match = users.entries
            .where((e) => e.value.toLowerCase() == person.toLowerCase())
            .map((e) => e.key)
            .toList();
        if (match.length == 1) {
          settings.user = match.single;
          await settings.save();
        } else {
          warning =
              'No single person named "$person"; captures need --for until `people add` and a default exist.';
        }
      }
      return AgentResult(
        {
          'profile': profile.root,
          'writer': settings.writer,
          'workspace': location,
          'warning': ?warning,
        },
        'Initialized agent profile ${profile.root}\nwriter ${settings.writer} "${call.require('name')}"\nworkspace $location${warning == null ? '' : '\n$warning'}',
      );
    } finally {
      try {
        await session?.close();
        await db?.close();
      } finally {
        engine.dispose();
        // A join may have been written even if opening failed afterwards.
        if (created &&
            !joined &&
            !(writer != null &&
                await File(
                  '$location${Platform.pathSeparator}$writer.applog',
                ).exists())) {
          await profile.removeCreated();
        }
        await lock?.close();
      }
    }
  },
);
