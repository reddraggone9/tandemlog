import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/text_context.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/text/recurring_text.dart';
import 'package:tandemlog/text/shared_text_history.dart';

class _DeliveryFixture {
  _DeliveryFixture(
    this.root,
    this.folder,
    this.engine,
    this.store,
    this.user,
    this.parent,
  );
  final Directory root;
  final LocalLogFolder folder;
  final NativeTextEngine engine;
  TaskStore store;
  final String user, parent;
  final _streams = <String, List<LogEvent>>{};
  int _remoteClock = 1000;
  static Future<_DeliveryFixture> create() async {
    final root = await Directory.systemTemp.createTemp('checklist-delivery-');
    final folder = LocalLogFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    final engine = NativeTextEngine(
      libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    final store = await TaskStore.open(
      folder,
      '${root.path}/profile',
      textEngine: engine,
    );
    final user = const Uuid().v4(), parent = const Uuid().v4();
    await store.command(user, 'user.created', {'name': 'Synthetic'});
    await store.command(parent, 'task.created', {
      'title': 'Scalar parent',
      'description': '',
      'assignee': user,
      'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
    });
    return _DeliveryFixture(root, folder, engine, store, user, parent);
  }

  Map<String, dynamic> seed(String title, String notes) => {
    'codec': 'yrs-v1',
    'adapter': 1,
    'seeds': {
      'title': sha256.convert(engine.seedText(title).bytes).toString(),
      'description': sha256.convert(engine.seedText(notes).bytes).toString(),
    },
  };
  Map<String, dynamic> creation(
    String owner,
    String title, {
    String? before,
    String notes = '',
  }) => {
    'parent': owner,
    'title': title,
    'description': notes,
    'before': before,
    'text': seed(title, notes),
  };
  LogEvent raw(
    String entity,
    String type,
    Map<String, dynamic> data, {
    String? writer,
  }) {
    final author = writer ?? const Uuid().v4();
    final stream = _streams.putIfAbsent(author, () => []);
    final maximum =
        store.db.select('SELECT MAX(clock) AS n FROM events').single['n']
            as int? ??
        0;
    if (_remoteClock <= maximum) _remoteClock = maximum + 1;
    final event = LogEvent.decode(
      LogEvent(
        store.space,
        author,
        stream.length + 1,
        EventClock(BigInt.from(_remoteClock++)),
        entity,
        type,
        data,
      ).encode(
        previousHash: stream.isEmpty
            ? eventGenesisHash(store.space, author)
            : stream.last.hash,
      ),
    );
    stream.add(event);
    return event;
  }

  Future<void> deliver(LogEvent event) async {
    await File('${folder.location}/${event.writer}.jsonl').writeAsString(
      '${_streams[event.writer]!.map((record) => record.canonicalRaw!).join('\n')}\n',
    );
    await store.refresh();
  }

  List<LogEvent> get records => store.db
      .select('SELECT raw FROM events ORDER BY clock,writer,seq')
      .map((row) => LogEvent.decode(row['raw'] as String))
      .toList();
  Map<String, dynamic> get frontiers {
    final heads = <String, LogEvent>{};
    for (final event in records) {
      if (event.sequence > (heads[event.writer]?.sequence ?? 0))
        heads[event.writer] = event;
    }
    return {
      for (final event in heads.values)
        event.writer: {'seq': event.sequence, 'hash': event.hash},
    };
  }

  List<Map<String, dynamic>> items(String task) =>
      (store.rows.singleWhere((row) => row['id'] == task)['checklist']
                  as List? ??
              [])
          .cast<Map<String, dynamic>>();
  Map<String, dynamic> cached() => {
    'views': store.db
        .select('SELECT id,raw FROM views ORDER BY id')
        .map((row) => Map<String, dynamic>.from(row))
        .toList(),
    'events': store.db
        .select('SELECT id,raw FROM events ORDER BY id')
        .map((row) => Map<String, dynamic>.from(row))
        .toList(),
    'streams': store.db
        .select(
          'SELECT name,offset,hash,chain_head,last_seq,last_clock FROM streams ORDER BY name',
        )
        .map((row) => Map<String, dynamic>.from(row))
        .toList(),
  };
  Future<Map<String, String>> canonical() async => {
    for (final file in await folder.list())
      file.name: sha256
          .convert(await File('${folder.location}/${file.name}').readAsBytes())
          .toString(),
  };
  Future<String> add(String title, {String? owner, String notes = ''}) async {
    final id = const Uuid().v4();
    await store.command(
      id,
      'checklist.itemCreated',
      creation(owner ?? parent, title, notes: notes),
    );
    return id;
  }

  Map<String, dynamic> copyItem(String successor, LogEvent source) {
    final graph = SharedTextHistoryGraph();
    return {
      'id': const Uuid().v5(successor, 'checklist:${source.entity}'),
      'source': source.entity,
      'title': source.data['title'],
      'description': source.data['description'],
      'fields': {
        for (final field in ['title', 'description'])
          field: (() {
            final context = TextFieldContext.fromCreation(source, field);
            final update = engine.seedText(source.data[field] as String);
            return {
              'parentContext': context.hash,
              'seedHash': context.seedHash,
              'historyHash': graph.root(context.hash, update).hash,
            };
          })(),
      },
    };
  }

  Map<String, dynamic> payload(List<String> sourceIds, {String? task}) {
    final owner = task ?? parent, child = const Uuid().v5(owner, 'successor');
    final history = records;
    final fields = {
      for (final id in sourceIds)
        id: RecurringTextResolver(engine, history).resolve(id),
    };
    return {
      'completedAt': '2030-05-10',
      'successor': {
        'id': child,
        'title': 'Scalar parent',
        'description': '',
        'assignee': user,
        'tags': <String>[],
        'schedule': {'dueDate': '2030-05-11', 'recurrence': 'every day'},
      },
      'checklist': {
        'codec': 'yrs-v1',
        'adapter': 2,
        'frontiers': frontiers,
        'items': [
          for (final id in sourceIds)
            {
              'id': const Uuid().v5(child, 'checklist:$id'),
              'source': id,
              'title': fields[id]!['title']!.text,
              'description': fields[id]!['description']!.text,
              'fields': {
                for (final entry in fields[id]!.entries)
                  entry.key: {
                    'parentContext': entry.value.context.hash,
                    'seedHash': entry.value.context.seedHash,
                    'historyHash': entry.value.historyReference!.hash,
                  },
              },
            },
        ],
      },
    };
  }

  Future<void> close() async {
    await store.close();
    engine.dispose();
  }
}

void main() {
  late _DeliveryFixture f;
  setUp(() async => f = await _DeliveryFixture.create());
  tearDown(() async => f.close());

  test(
    'remote item waits for missing task parent then attaches once without appearing as a task',
    () async {
      final owner = const Uuid().v4(), item = const Uuid().v4();
      await f.deliver(
        f.raw(
          item,
          'checklist.itemCreated',
          f.creation(owner, 'Deferred item'),
        ),
      );
      expect(f.store.rows.any((row) => row['id'] == item), false);
      await f.deliver(
        f.raw(owner, 'task.created', {
          'title': 'Late parent',
          'description': '',
          'assignee': f.user,
        }),
      );
      expect(f.items(owner).single['id'], item);
      expect(f.items(owner).single['title'], 'Deferred item');
      final before = jsonEncode(f.cached());
      await f.store.refresh();
      expect(jsonEncode(f.cached()), before);
    },
  );

  for (final wrongKind in ['user', 'item']) {
    test(
      'late $wrongKind parent invalidates retained item transactionally',
      () async {
        final owner = const Uuid().v4(), item = const Uuid().v4();
        await f.deliver(
          f.raw(item, 'checklist.itemCreated', f.creation(owner, 'Waiting')),
        );
        final before = jsonEncode(f.cached());
        final invalid = wrongKind == 'user'
            ? f.raw(owner, 'user.created', {'name': 'Wrong kind'})
            : f.raw(
                owner,
                'checklist.itemCreated',
                f.creation(f.parent, 'Nested parent'),
              );
        await expectLater(f.deliver(invalid), throwsA(isA<FormatFailure>()));
        expect(jsonEncode(f.cached()), before);
      },
    );
  }

  test(
    'late same-parent creation anchor settles item order and duplicates do not add items',
    () async {
      final first = const Uuid().v4(), anchor = const Uuid().v4();
      await f.deliver(
        f.raw(
          first,
          'checklist.itemCreated',
          f.creation(f.parent, 'First', before: anchor),
        ),
      );
      await f.deliver(
        f.raw(anchor, 'checklist.itemCreated', f.creation(f.parent, 'Anchor')),
      );
      expect(f.items(f.parent).map((row) => row['id']), [first, anchor]);
      final before = jsonEncode(f.cached());
      await f.store.refresh();
      expect(jsonEncode(f.cached()), before);
    },
  );

  test(
    'late cross-parent move anchor rolls back arrival without changing the pending source item',
    () async {
      final first = await f.add('First'),
          anchor = const Uuid().v4(),
          other = const Uuid().v4();
      await f.store.command(other, 'task.created', {
        'title': 'Other',
        'description': '',
        'assignee': f.user,
      });
      await f.deliver(f.raw(first, 'checklist.itemMoved', {'before': anchor}));
      final before = jsonEncode(f.cached());
      await expectLater(
        f.deliver(
          f.raw(
            anchor,
            'checklist.itemCreated',
            f.creation(other, 'Foreign anchor'),
          ),
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(jsonEncode(f.cached()), before);
    },
  );

  for (final wrongKind in ['user', 'task']) {
    test(
      'late $wrongKind creation anchor rejects with transactional rollback',
      () async {
        final anchor = const Uuid().v4(), item = const Uuid().v4();
        await f.deliver(
          f.raw(
            item,
            'checklist.itemCreated',
            f.creation(f.parent, 'Waiting for anchor', before: anchor),
          ),
        );
        final before = jsonEncode(f.cached());
        final invalid = wrongKind == 'user'
            ? f.raw(anchor, 'user.created', {'name': 'Wrong anchor'})
            : f.raw(anchor, 'task.created', {
                'title': 'Wrong anchor',
                'description': '',
                'assignee': f.user,
              });
        await expectLater(f.deliver(invalid), throwsA(isA<FormatFailure>()));
        expect(jsonEncode(f.cached()), before);
      },
    );
  }

  test(
    'copy contribution waits for its source frontier then reconstructs unchecked native item exactly',
    () async {
      final source = f.raw(
        const Uuid().v4(),
        'checklist.itemCreated',
        f.creation(f.parent, 'Deferred source', notes: 'Original notes'),
      );
      final child = const Uuid().v5(f.parent, 'successor');
      final copy = f.copyItem(child, source);
      final descriptor = {
        'completedAt': '2030-05-10',
        'successor': {
          'id': child,
          'title': 'Scalar parent',
          'description': '',
          'assignee': f.user,
          'tags': <String>[],
          'schedule': {'dueDate': '2030-05-11', 'recurrence': 'every day'},
        },
        'checklist': {
          'codec': 'yrs-v1',
          'adapter': 2,
          'frontiers': {
            ...f.frontiers,
            source.writer: {'seq': source.sequence, 'hash': source.hash},
          },
          'items': [copy],
        },
      };
      await f.deliver(
        f.raw(f.parent, 'task.completedWithChecklist', descriptor),
      );
      // No native text context is guessed from a missing source proof.
      expect(
        f.store.db.select('SELECT 1 FROM text_fields WHERE entity=?', [
          copy['id'],
        ]),
        isEmpty,
      );
      await f.deliver(source);
      expect(f.items(child).single['id'], copy['id']);
      expect(f.items(child).single['title'], 'Deferred source');
      expect(f.items(child).single['description'], 'Original notes');
      expect(f.items(child).single['completed'], false);
      final capture = await f.store.captureTaskText(copy['id'] as String);
      expect(capture.fields['title']!.document.read().text, 'Deferred source');
      f.store.releaseTextCapture(capture);
      final warm = jsonEncode(f.store.rows), bytes = await f.canonical();
      await f.store.close();
      f.store = await TaskStore.open(
        f.folder,
        '${f.root.path}/cold',
        textEngine: f.engine,
      );
      expect(jsonEncode(f.store.rows), warm);
      expect(await f.canonical(), bytes);
    },
  );

  for (final corruption in [
    'membership',
    'order',
    'visible text',
    'history proof',
    'source parent',
  ]) {
    test(
      'forged $corruption copy rejects before receipt and leaves canonical history untouched',
      () async {
        final first = await f.add('First', notes: 'Notes'),
            second = await f.add('Second');
        final data = f.payload([first, second]);
        // A valid descriptor must be admitted before testing the specific forgery.
        // Unknown event/type admission cannot make a forged-proof gate pass.
        final accepted = await f.store.command(
          f.parent,
          'task.completedWithChecklist',
          data,
        );
        expect(accepted.type, 'task.completedWithChecklist');
        final descriptor = data['checklist'] as Map,
            copied = (descriptor['items'] as List).cast<Map>();
        switch (corruption) {
          case 'membership':
            descriptor['items'] = [copied.first];
          case 'order':
            descriptor['items'] = copied.reversed.toList();
          case 'visible text':
            copied.first['title'] = 'Forged words';
          case 'history proof':
            copied.first['fields']['title']['historyHash'] = 'f' * 64;
          case 'source parent':
            final other = const Uuid().v4();
            await f.store.command(other, 'task.created', {
              'title': 'Other',
              'description': '',
              'assignee': f.user,
            });
            final foreign = await f.add('Foreign source', owner: other);
            final foreignData = f.payload([foreign]);
            descriptor['frontiers'] =
                (foreignData['checklist'] as Map)['frontiers'];
            descriptor['items'] = (foreignData['checklist'] as Map)['items'];
        }
        final cache = jsonEncode(f.cached()), bytes = await f.canonical();
        var prepared = false;
        await expectLater(
          f.store.command(
            f.parent,
            'task.completedWithChecklist',
            data,
            onPrepared: (_) => prepared = true,
          ),
          throwsA(isA<FormatFailure>()),
        );
        expect(prepared, false);
        expect(jsonEncode(f.cached()), cache);
        expect(await f.canonical(), bytes);
        expect(f.store.db.select('SELECT * FROM text_outbox'), isEmpty);
      },
    );
  }

  for (final kind in ['task', 'item']) {
    test(
      'copied ID collision with independent $kind rejects before receipt',
      () async {
        final source = await f.add('Source');
        final child = const Uuid().v5(f.parent, 'successor'),
            copy = const Uuid().v5(child, 'checklist:$source');
        if (kind == 'task') {
          await f.store.command(copy, 'task.created', {
            'title': 'Independent task',
            'description': '',
            'assignee': f.user,
          });
        } else {
          await f.store.command(
            copy,
            'checklist.itemCreated',
            f.creation(f.parent, 'Independent item'),
          );
        }
        final sources = f
                .items(f.parent)
                .map((row) => row['id'] as String)
                .toList(),
            data = f.payload(sources);
        final cache = jsonEncode(f.cached()), bytes = await f.canonical();
        var prepared = false;
        await expectLater(
          f.store.command(
            f.parent,
            'task.completedWithChecklist',
            data,
            onPrepared: (_) => prepared = true,
          ),
          throwsA(isA<FormatFailure>()),
        );
        expect(prepared, false);
        expect(jsonEncode(f.cached()), cache);
        expect(await f.canonical(), bytes);
      },
    );
  }

  test(
    'late duplicate copy contribution preserves child-owned ordering and check state',
    () async {
      final first = await f.add('First'), second = await f.add('Second');
      await f.deliver(
        f.raw(
          f.parent,
          'task.completedWithChecklist',
          f.payload([first, second]),
        ),
      );
      final child = const Uuid().v5(f.parent, 'successor');
      final copyFirst = const Uuid().v5(child, 'checklist:$first'),
          copySecond = const Uuid().v5(child, 'checklist:$second');
      await f.store.command(copyFirst, 'checklist.itemMoved', {'before': null});
      await f.store.command(copySecond, 'checklist.itemEdited', {
        'completed': true,
      });
      await f.store.command(second, 'checklist.itemMoved', {'before': first});
      final secondPayload = f.payload([second, first]);
      final late = f.raw(
        f.parent,
        'task.completedWithChecklist',
        secondPayload,
      );
      // The copied descriptor observes a prefix before its completion record.
      final heads = (secondPayload['checklist'] as Map)['frontiers'] as Map;
      final maximum = f.records
          .map((record) => record.clock.value)
          .reduce((a, b) => a > b ? a : b);
      final corrected = LogEvent.decode(
        LogEvent(
          late.space,
          late.writer,
          late.sequence,
          EventClock(maximum + BigInt.one),
          late.entity,
          late.type,
          late.data,
        ).encode(previousHash: late.previousHash!),
      );
      f._streams[late.writer] = [corrected];
      expect(heads, isNotEmpty);
      await f.deliver(corrected);
      expect(f.items(child).map((row) => row['id']), [copySecond, copyFirst]);
      expect(f.items(child).first['completed'], true);
      final before = jsonEncode(f.cached());
      await f.deliver(corrected);
      expect(jsonEncode(f.cached()), before);
      expect(f.items(child), hasLength(2));
    },
  );

  test(
    'parent recurrence preserves live item private draft and later source Save does not flow into copied notes',
    () async {
      final item = await f.add('Source', notes: 'Original notes');
      final capture = await f.store.captureTaskText(item);
      final session = TaskTextSession(
        capture,
        registerDraftActor: (field, allocation, actor) =>
            f.store.registerTextDraftActor(capture, field, allocation, actor),
      );
      try {
        session.replace('description', 'Private old notes');
        final originalState =
            capture.fields['description']!.document.fullState.encoded;
        await f.store.complete(f.parent, completionDay: DateTime(2030, 5, 10));
        final child = const Uuid().v5(f.parent, 'successor');
        expect(f.items(child).single['description'], 'Original notes');
        expect(
          capture.fields['description']!.document.fullState.encoded,
          originalState,
        );
        final saved = await TextSaveCommand(
          f.store,
          session,
        ).save(fields: {}, tags: [], observedTagRefs: {});
        expect(saved.receipt, isNotNull);
        expect(saved.undoError, isNull);
        expect(f.items(f.parent).single['description'], 'Private old notes');
        expect(f.items(child).single['description'], 'Original notes');
        session.cancel();
        expect(
          (await f.store.undoOperations([saved.receipt!.id])).remaining,
          isEmpty,
        );
        expect(f.items(f.parent).single['description'], 'Original notes');
        expect(f.items(child).single['description'], 'Original notes');
      } finally {
        session.cancel();
        f.store.releaseTextCapture(capture);
      }
    },
  );

  test(
    'item private drafts, pre-append Save cancellation and scoped Undo preserve another item',
    () async {
      final first = await f.add('First', notes: 'Notes'),
          second = await f.add('Second', notes: 'Other notes');
      final capture = await f.store.captureTaskText(first);
      final session = TaskTextSession(
        capture,
        registerDraftActor: (field, allocation, actor) =>
            f.store.registerTextDraftActor(capture, field, allocation, actor),
      );
      try {
        final bytes = await f.canonical();
        session.replace('description', 'Private notes');
        expect(
          f
              .items(f.parent)
              .singleWhere((row) => row['id'] == first)['description'],
          'Notes',
        );
        expect(await f.canonical(), bytes);
        await expectLater(
          TextSaveCommand(f.store, session).save(
            fields: {},
            tags: [],
            observedTagRefs: {},
            canCommit: () => false,
          ),
          throwsA(isA<StaleTaskSnapshot>()),
        );
        expect(await f.canonical(), bytes);
        session.restart();
        session.replace('description', 'Saved notes');
        final saved = await TextSaveCommand(
          f.store,
          session,
        ).save(fields: {}, tags: [], observedTagRefs: {});
        expect(saved.receipt, isNotNull);
        expect(saved.undoError, isNull);
        final checked = await f.store.command(second, 'checklist.itemEdited', {
          'completed': true,
        });
        session.replace('description', 'Unpublished after Save');
        session.cancel();
        final undone = await f.store.undoOperations([saved.receipt!.id]);
        expect(undone.remaining, isEmpty);
        expect(
          f
              .items(f.parent)
              .singleWhere((row) => row['id'] == first)['description'],
          'Notes',
        );
        expect(
          f
              .items(f.parent)
              .singleWhere((row) => row['id'] == second)['description'],
          'Other notes',
        );
        expect(
          f
              .items(f.parent)
              .singleWhere((row) => row['id'] == second)['completed'],
          true,
        );
        expect(
          f.store.confirmedOperations([
            OperationReceipt(checked.id, checked.canonicalRaw!, second),
          ]),
          contains(checked.id),
        );
      } finally {
        session.cancel();
        f.store.releaseTextCapture(capture);
      }
    },
  );
}
