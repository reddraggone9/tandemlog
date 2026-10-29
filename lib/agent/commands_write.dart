import 'dart:convert';
import 'dart:io';

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
import 'text_undo.dart';
import '../storage/task_store.dart' show StaleTaskSnapshot;

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
  return () => expected.entries.every((e) => taskRev(call, e.key) == e.value);
}

AgentResult writeResult(
  AgentCall call,
  int before,
  String summary,
  List<String> taskIds, {
  List<String> containerIds = const [],
  Map<String, Object?> extra = const {},
}) {
  final actions = newActions(call, before);
  final containers = {for (final c in foodState(call).containers) c.id: c};
  final affected = [
    for (final id in taskIds) {'id': id, 'rev': taskRev(call, id)},
    for (final id in containerIds)
      if (containers[id] != null) {'id': id, 'rev': foodRev(containers[id]!)},
  ];
  final undo = actions.length == 1
      ? 'tandemlog-cli undo ${actions.single}'
      : null;
  return AgentResult(
    {'actions': actions, 'affected': affected, 'undo': ?undo, ...extra},
    [
      summary,
      for (final a in affected) '${shortId(a['id'] as String)} rev ${a['rev']}',
      if (undo != null) 'undo: $undo',
    ].join('\n'),
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
  return () {
    for (var i = 0; i < ids.length; i++) {
      if (actual(ids[i]) != revs[i]) return false;
    }
    return true;
  };
}

/// Whole-action Undo of this installation's own action. Text contributions
/// are not yet retractable across processes, so such actions are refused
/// whole (`undo_unavailable`) rather than partially undone.
Future<AgentResult> undoAction(AgentCall call) async {
  final input = call.require('action');
  final parts = input.split(':');
  final seq = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (seq == null) {
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
  final taskOps = [
    for (final e in record.effects)
      if (e.task != null) e.task!,
  ];
  final foodOps = [
    for (final e in record.effects)
      if (e.food != null) e.food!,
  ];
  if (taskOps.isNotEmpty && foodOps.isNotEmpty) {
    throw const AgentFailure(
      'undo_unavailable',
      'Mixed Task and Food actions cannot be undone as one unit yet.',
    );
  }
  final created = taskOps.where(
    (e) =>
        e.type == 'task.created' ||
        e.type == 'task.createdWithText' ||
        e.type == 'user.created' ||
        e.type == 'checklist.itemCreated',
  );
  if (created.isNotEmpty) {
    throw const AgentFailure(
      'undo_unavailable',
      'Creating an item is not undone; delete it instead. Nothing was changed.',
    );
  }
  final before = ownHead(call);
  final affected = <String>{for (final e in taskOps) e.entity};
  final containers = <String>{for (final r in foodOps) ...r.operation.targets};
  final guard = _undoGuard(call, affected, containers);
  final text = taskOps.where((e) => e.type == 'task.textEdited').toList();
  if (text.isNotEmpty) {
    if (taskOps.length != 1) {
      throw const AgentFailure(
        'undo_unavailable',
        'This action mixes text with other operations. Nothing was changed.',
      );
    }
    final target = text.single;
    if (_undone(snapshot, target.id)) {
      return writeResult(
        call,
        before,
        'Already undone.',
        affected.toList(),
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
    if (!guard()) throw StaleTaskSnapshot();
    final result = await call.ws.session.tasks.undoOperations([
      for (final e in taskOps) e.id,
    ]);
    if (result.error != null) throw result.error!;
    if (newActions(call, before).isEmpty) {
      return writeResult(
        call,
        before,
        'Already undone.',
        affected.toList(),
        extra: {'alreadyUndone': true},
      );
    }
  } else {
    if (!guard()) throw StaleTaskSnapshot();
    await call.ws.session.food.undoOperations(foodOps);
    if (newActions(call, before).isEmpty) {
      return writeResult(
        call,
        before,
        'Already undone.',
        const [],
        extra: {'alreadyUndone': true},
      );
    }
  }
  return writeResult(
    call,
    before,
    'Undid $input.',
    affected.where((id) => taskRow(call, id) != null).toList(),
    containerIds: [for (final r in foodOps) ...r.operation.targets],
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
/// never silently reverts over a change the agent has not seen.
bool Function() _undoGuard(
  AgentCall call,
  Set<String> tasks,
  Set<String> containers,
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
    given[resolveId(pair.substring(0, eq), {...tasks, ...containers}, 'item')] =
        pair.substring(eq + 1);
  }
  String? current(String id) {
    if (tasks.contains(id)) return taskRev(call, id);
    for (final c in foodState(call).containers) {
      if (c.id == id) return foodRev(c);
    }
    return null;
  }

  final missing = [
    for (final id in {...tasks, ...containers})
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
  return () => given.entries.every((e) => current(e.key) == e.value);
}

/// Dry run: perform the command on disposable copies of the profile and the
/// workspace, report the resulting typed effects and a planHash, discard.
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
  try {
    final copy = await profile.readCopy();
    final probe = await LocalProfileDatabase.open(copy.path);
    final settings = LocalSettings(probe.root, profileDatabase: probe);
    await settings.load();
    await probe.close();
    final source = Directory(settings.folder!);
    final shadow = Directory('${scratch.path}/workspace');
    await shadow.create();
    await for (final f in source.list(followLinks: false)) {
      if (f is File) {
        await f.copy('${shadow.path}/${f.uri.pathSegments.last}');
      }
    }
    // Rebind the copied profile to the shadow folder without touching the
    // real profile.
    final shadowProfile = AgentProfile(copy.path);
    await _rebind(shadowProfile, shadow.path);
    final before = await AgentWorkspace.open(
      shadowProfile,
      readOnly: false,
      wait: options.wait,
    );
    final beforeState = _observable(AgentCall(args, before, options));
    AgentResult result;
    Map<String, Object?> afterState;
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
      afterState = _observable(AgentCall(args, before, options));
    } finally {
      await before.close();
    }
    final effects = _diff(beforeState, afterState);
    final planHash = revOf({
      'command': command.name,
      'args': {...args}
        ..remove('dry-run')
        ..remove('expect-plan'),
      'effects': _stable(effects),
    });
    await copy.delete(recursive: true);
    return AgentResult(
      {'dryRun': true, 'planHash': planHash, 'effects': effects},
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
  }
}

Future<void> _rebind(AgentProfile profile, String folder) async {
  final db = await LocalProfileDatabase.open(profile.root);
  try {
    final settings = LocalSettings(db.root, profileDatabase: db);
    await settings.load();
    settings.folder = folder;
    await settings.save();
  } finally {
    await db.close();
  }
}

const _volatile = {'order', 'completionOrder', 'completedMicros', 'tagRefs'};

/// Observation times differ between a dry run and its commit; the plan binds
/// targets and field changes, not the clock reading.
const _clockFields = {'completedInstant', 'createdAt', 'deletedAt'};

Object? _stable(Object? value) => switch (value) {
  Map m => {
    for (final e in m.entries)
      if (!_clockFields.contains(e.key)) e.key: _stable(e.value),
  },
  List l => [for (final x in l) _stable(x)],
  _ => value,
};

Map<String, Object?> _observable(AgentCall call) => {
  for (final r in call.ws.session.tasks.rows)
    r['id'] as String: {
      for (final e in r.entries)
        if (!_volatile.contains(e.key)) e.key: e.value,
    },
  for (final c in call.ws.session.food.state.containers)
    c.id: jsonDecode(jsonEncode(c.toJson())),
};

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
    // Load native code before creating anything, then remove this fresh
    // profile again if joining fails so a retry starts clean.
    final engine = agentTextEngine();
    try {
      await profile.createMarker();
    } catch (_) {
      engine.dispose();
      rethrow;
    }
    LocalProfileDatabase? db;
    WorkspaceSession? session;
    var joined = false;
    try {
      db = await LocalProfileDatabase.open(profile.root);
      await LocalSettings.initialize(db);
      final settings = LocalSettings(db.root, profileDatabase: db);
      await settings.load();
      settings.folder = location;
      await settings.save();
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
      await session?.close();
      await db?.close();
      engine.dispose();
      if (!joined) await Directory(profile.root).delete(recursive: true);
    }
  },
);
