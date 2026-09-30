import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/projection.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory root;
  late LocalLogFolder aFolder, bFolder;
  TaskStore? a, b;
  late DateTime testNow;
  Future<void> copy(LocalLogFolder from, LocalLogFolder to) async {
    for (final f in await from.list()) {
      await File('${from.location}/${f.name}').copy('${to.location}/${f.name}');
    }
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-test');
    await Directory('${root.path}/a').create();
    await Directory('${root.path}/b').create();
    aFolder = LocalLogFolder('${root.path}/a');
    bFolder = LocalLogFolder('${root.path}/b');
    testNow = DateTime.now().toUtc();
    a = await TaskStore.open(
      aFolder,
      '${root.path}/private-a',
      now: () => testNow,
    );
    await copy(aFolder, bFolder);
    b = await TaskStore.open(
      bFolder,
      '${root.path}/private-b',
      now: () => testNow,
    );
  });
  tearDown(() async {
    await a?.close();
    await b?.close();
    await root.delete(recursive: true);
  });
  Future<String> task() async {
    final id = const Uuid().v4();
    final user = const Uuid().v4();
    await a!.command(user, 'user.created', {'name': 'Lee'});
    await a!.command(id, 'task.created', {
      'title': 'Groceries',
      'description': '',
      'assignee': user,
    });
    return id;
  }

  Map<String, dynamic> state(TaskStore store, String id) =>
      store.rows.firstWhere((r) => r['id'] == id);

  test('old provenance cache cannot bypass current closed schema', () async {
    final id = await task();
    final bytes = await aFolder.read('${a!.writer}.jsonl');
    a!.db.execute('PRAGMA user_version=4');
    a!.db.execute('UPDATE views SET raw=? WHERE id=?', [
      jsonEncode({'id': id, 'kind': 'document', 'lines': []}),
      id,
    ]);
    await a!.close();
    a = null;
    await expectLater(
      TaskStore.open(aFolder, '${root.path}/private-a'),
      throwsA(isA<FormatFailure>()),
    );
    expect(
      await aFolder.read(
        '${jsonDecode(utf8.decode(bytes).split('\n').first)['writer']}.jsonl',
      ),
      bytes,
    );
    final old =
        jsonDecode(utf8.decode(bytes).split('\n').first)
            as Map<String, dynamic>;
    old['type'] = 'import.document';
    old['data'] = {'lines': []};
    await File(
      '${aFolder.location}/${old['writer']}.jsonl',
    ).writeAsString('${jsonEncode(old)}\n');
    final rejectedBytes = await aFolder.read('${old['writer']}.jsonl');
    await expectLater(
      TaskStore.open(aFolder, '${root.path}/fresh-cache'),
      throwsA(isA<FormatFailure>()),
    );
    expect(await aFolder.read('${old['writer']}.jsonl'), rejectedBytes);
  });

  test(
    'reopen targets observed completions, is idempotent and survives restart',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      await a!.command(id, 'task.completed', {});
      await b!.command(id, 'task.completed', {});
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      final observed = a!.activeCompletionIds(id);
      expect(observed, hasLength(2));
      await a!.reopen(id, observed);
      expect(state(a!, id)['completed'], isFalse);
      final bytes = await File(
        '${aFolder.location}/${a!.writer}.jsonl',
      ).readAsString();
      await a!.reopen(id, observed);
      expect(
        await File('${aFolder.location}/${a!.writer}.jsonl').readAsString(),
        bytes,
      );
      // A completion unseen by this reopen survives synchronization.
      await b!.command(id, 'task.completed', {});
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      expect(state(a!, id)['completed'], isTrue);
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(state(a!, id), state(b!, id));
      await a!.reopen(id, a!.activeCompletionIds(id));
      await a!.close();
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['completed'], isFalse);
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(state(a!, id), state(b!, id));
    },
  );

  test('reopen refresh does not expand the observed target set', () async {
    final id = await task();
    await copy(aFolder, bFolder);
    await b!.refresh();
    await a!.command(id, 'task.completed', {});
    final observed = a!.activeCompletionIds(id);
    final unseen = await b!.command(id, 'task.completed', {});
    await File(
      '${bFolder.location}/${b!.writer}.jsonl',
    ).copy('${aFolder.location}/${b!.writer}.jsonl');
    await a!.reopen(id, observed);
    expect(a!.activeCompletionIds(id), [unseen.id]);
    expect(state(a!, id)['completed'], isTrue);
  });

  test('partial reopen retries without duplicating a committed undo', () async {
    final id = await task();
    await a!.command(id, 'task.completed', {});
    await a!.command(id, 'task.completed', {});
    final observed = a!.activeCompletionIds(id);
    await a!.close();
    final failing = _FailAfterAppendFolder(aFolder);
    a = await TaskStore.open(failing, '${root.path}/private-a');
    failing.failNext = true;
    await expectLater(a!.reopen(id, observed), throwsStateError);
    await a!.reopen(id, observed);
    expect(state(a!, id)['completed'], isFalse);
    final events = a!.db
        .select('SELECT raw FROM events')
        .map((r) => LogEvent.decode(r['raw'] as String));
    expect(
      events.where((e) => e.type == 'task.completionUndone'),
      hasLength(2),
    );
  });

  test(
    'restart retains state and unchanged files avoid parsing/replay',
    () async {
      final id = await task();
      await a!.close();
      a = null;
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['title'], 'Groceries');
      expect(a!.readFiles, 0);
    },
  );
  test(
    'cache deletion rebuilds exact projection and writer stays stable',
    () async {
      final id = await task();
      final expected = a!.rows;
      final writer = a!.writer;
      await a!.close();
      a = null;
      await File('${root.path}/private-a/cache.sqlite').delete();
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(a!.rows, expected);
      expect(a!.writer, writer);
      await a!.command(id, 'task.edited', {'title': 'Updated'});
      expect(state(a!, id)['title'], 'Updated');
    },
  );
  test(
    'offline independent fields, duplicate transport and atomic replacement converge',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      await a!.command(id, 'task.edited', {'title': 'Buy oats'});
      await b!.command(id, 'task.edited', {'description': 'Large bag'});
      // Exchange only each owning writer's stream; emulate rename replacement.
      final temp = File('${aFolder.location}/incoming.tmp');
      await File('${bFolder.location}/${b!.writer}.jsonl').copy(temp.path);
      await temp.rename('${aFolder.location}/${b!.writer}.jsonl');
      await File(
        '${aFolder.location}/${a!.writer}.jsonl',
      ).copy('${bFolder.location}/${a!.writer}.jsonl');
      await a!.refresh();
      await b!.refresh();
      await a!.refresh();
      expect(a!.rows, b!.rows);
      expect(state(a!, id)['title'], 'Buy oats');
      expect(state(a!, id)['description'], 'Large bag');
    },
  );
  test(
    'concurrent completion survives targeted undo from another user',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      final completion = await a!.command(id, 'task.completed', {});
      await b!.command(id, 'task.completed', {});
      await a!.command(id, 'task.completionUndone', {
        'completion': completion.id,
      });
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      expect(state(a!, id)['completed'], true);
    },
  );
  test(
    'unknown version blocks import without checkpoint advancement',
    () async {
      await task();
      final remote = const Uuid().v4();
      await aFolder.create(
        '$remote.jsonl',
        Uint8List.fromList(utf8.encode('{"v":99}\n')),
      );
      final before = a!.rows;
      await expectLater(a!.refresh(), throwsA(isA<FormatFailure>()));
      expect(a!.rows, before);
      expect(
        a!.db.select('SELECT * FROM streams WHERE name=?', ['$remote.jsonl']),
        isEmpty,
      );
    },
  );
  test('malformed complete records are preserved and block writes', () async {
    final id = await task();
    final remote = const Uuid().v4();
    await aFolder.create(
      '$remote.jsonl',
      Uint8List.fromList(utf8.encode('not-json\n')),
    );
    await expectLater(
      a!.command(id, 'task.completed', {}),
      throwsA(isA<FormatFailure>()),
    );
    expect(utf8.decode(await aFolder.read('$remote.jsonl')), 'not-json\n');
  });
  test('incomplete remote tail is retried after completion', () async {
    final remote = const Uuid().v4();
    final id = const Uuid().v4();
    final raw = LogEvent(
      a!.space,
      remote,
      1,
      testClock(1, 0),
      id,
      'user.created',
      {'name': 'Lee'},
    ).encode();
    await aFolder.create(
      '$remote.jsonl',
      Uint8List.fromList(utf8.encode(raw.substring(0, 20))),
    );
    await a!.refresh();
    expect(a!.rows, isEmpty);
    await aFolder.append(
      '$remote.jsonl',
      Uint8List.fromList(utf8.encode('${raw.substring(20)}\n')),
    );
    await a!.refresh();
    expect(state(a!, id)['name'], 'Lee');
  });
  test('changed same-length committed prefix fails closed', () async {
    await task();
    final f = File('${aFolder.location}/${a!.writer}.jsonl');
    await f.writeAsString(
      (await f.readAsString()).replaceFirst('Groceries', 'Xroceries'),
      flush: true,
    );
    await expectLater(a!.refresh(), throwsA(isA<FormatFailure>()));
  });
  test('missing previously seen stream blocks writes', () async {
    await task();
    await File('${aFolder.location}/${a!.writer}.jsonl').delete();
    await expectLater(a!.refresh(), throwsA(isA<FormatFailure>()));
  });
  test('owned incomplete tail is not silently truncated', () async {
    await task();
    await aFolder.append(
      '${a!.writer}.jsonl',
      Uint8List.fromList(utf8.encode('{')),
    );
    await expectLater(a!.refresh(), throwsA(isA<FormatFailure>()));
    expect(
      utf8.decode(await aFolder.read('${a!.writer}.jsonl')).endsWith('{'),
      true,
    );
  });
  test(
    'durable append before cache failure recovers once after restart',
    () async {
      final id = await task();
      final seq = 3;
      final e = LogEvent(
        a!.space,
        a!.writer,
        seq,
        EventClock.next(
          BigInt.from(testNow.microsecondsSinceEpoch) * BigInt.from(1000),
          LogEvent.decode(
            a!.db
                    .select(
                      'SELECT raw FROM events ORDER BY clock DESC LIMIT 1',
                    )
                    .first['raw']
                as String,
          ).clock,
        ),
        id,
        'task.completed',
        {},
      );
      await aFolder.append(
        '${a!.writer}.jsonl',
        Uint8List.fromList(utf8.encode('${e.encode()}\n')),
      );
      await a!.close();
      a = null;
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['completed'], true);
      expect(a!.db.select('SELECT * FROM events').length, 3);
    },
  );
  test(
    'out-of-order entity dependency is retained and projected later',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      await b!.command(id, 'task.edited', {'title': 'Changed elsewhere'});
      final third = LocalLogFolder('${root.path}/third');
      await Directory(third.location).create();
      await File(
        '${aFolder.location}/tandemlog-space.json',
      ).copy('${third.location}/tandemlog-space.json');
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${third.location}/${b!.writer}.jsonl');
      final c = await TaskStore.open(third, '${root.path}/private-c');
      try {
        expect(c.rows, isEmpty);
        await File(
          '${aFolder.location}/${a!.writer}.jsonl',
        ).copy('${third.location}/${a!.writer}.jsonl');
        await c.refresh();
        expect(state(c, id)['title'], 'Changed elsewhere');
      } finally {
        await c.close();
      }
    },
  );
  test(
    'concurrent commands and refreshes serialize without duplicate sequence',
    () async {
      final id = await task();
      await Future.wait([
        a!.command(id, 'task.edited', {'title': 'First'}),
        a!.command(id, 'task.edited', {'description': 'Second'}),
        a!.refresh(),
        a!.command(id, 'task.completed', {}),
      ]);
      expect(
        a!.db
            .select('SELECT seq FROM events WHERE writer=? ORDER BY seq', [
              a!.writer,
            ])
            .map((r) => r['seq'])
            .toList(),
        [1, 2, 3, 4, 5],
      );
      await a!.close();
      a = null;
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['title'], 'First');
      expect(state(a!, id)['completed'], true);
    },
  );
  test('invalid local commands leave canonical bytes unchanged', () async {
    final id = await task();
    final before = await aFolder.read('${a!.writer}.jsonl');
    final user = a!.rows.firstWhere((r) => r['kind'] == 'user')['id'] as String;
    await expectLater(
      a!.command(id, 'task.created', {
        'title': 'Duplicate',
        'description': '',
        'assignee': user,
      }),
      throwsA(isA<FormatFailure>()),
    );
    await expectLater(
      a!.command(user, 'task.edited', {'title': 'Invalid'}),
      throwsA(isA<FormatFailure>()),
    );
    await expectLater(
      a!.command(const Uuid().v4(), 'task.completed', {}),
      throwsA(isA<FormatFailure>()),
    );
    expect(await aFolder.read('${a!.writer}.jsonl'), before);
    await a!.command(id, 'task.edited', {'title': 'Still works'});
  });
  test(
    'manifest deletion, replacement and future format block commands',
    () async {
      final id = await task();
      final manifest = await aFolder.read('tandemlog-space.json');
      final before = await aFolder.read('${a!.writer}.jsonl');
      final file = File('${aFolder.location}/tandemlog-space.json');
      for (final replacement in [
        null,
        jsonEncode({'v': 1, 'id': const Uuid().v4()}),
        jsonEncode({'v': 99, 'id': a!.space}),
      ]) {
        if (replacement == null) {
          await file.delete();
        } else {
          await file.writeAsString(replacement);
        }
        await expectLater(
          a!.command(id, 'task.completed', {}),
          throwsA(anything),
        );
        expect(await aFolder.read('${a!.writer}.jsonl'), before);
        await file.writeAsBytes(manifest);
      }
      await a!.command(id, 'task.completed', {});
    },
  );
  test(
    'local undo requires an earlier completion of the same entity',
    () async {
      final id = await task();
      final before = await aFolder.read('${a!.writer}.jsonl');
      await expectLater(
        a!.command(id, 'task.completionUndone', {
          'completion': '${a!.writer}:99',
        }),
        throwsA(isA<FormatFailure>()),
      );
      await expectLater(
        a!.command(id, 'task.completionUndone', {
          'completion': '${a!.writer}:1',
        }),
        throwsA(isA<FormatFailure>()),
      );
      expect(await aFolder.read('${a!.writer}.jsonl'), before);
    },
  );
  test(
    'remote undo arriving before completion is revalidated when target arrives',
    () async {
      final id = await task();
      final remote = const Uuid().v4(), other = const Uuid().v4();
      final undo = LogEvent(
        a!.space,
        remote,
        1,
        testClock(10, 0),
        id,
        'task.completionUndone',
        {'completion': '$other:1'},
      );
      await aFolder.create(
        '$remote.jsonl',
        Uint8List.fromList(utf8.encode('${undo.encode()}\n')),
      );
      await a!.refresh();
      final completed = LogEvent(
        a!.space,
        other,
        1,
        testClock(9, 0),
        id,
        'task.completed',
        {},
      );
      await aFolder.create(
        '$other.jsonl',
        Uint8List.fromList(utf8.encode('${completed.encode()}\n')),
      );
      await a!.refresh();
      expect(state(a!, id)['completed'], false);
    },
  );
  test('remote undo cannot suppress a future-clock completion', () async {
    final id = await task();
    final remote = const Uuid().v4(), other = const Uuid().v4();
    final undo = LogEvent(
      a!.space,
      remote,
      1,
      testClock(10, 0),
      id,
      'task.completionUndone',
      {'completion': '$other:1'},
    );
    await aFolder.create(
      '$remote.jsonl',
      Uint8List.fromList(utf8.encode('${undo.encode()}\n')),
    );
    await a!.refresh();
    final completed = LogEvent(
      a!.space,
      other,
      1,
      testClock(11, 0),
      id,
      'task.completed',
      {},
    );
    await aFolder.create(
      '$other.jsonl',
      Uint8List.fromList(utf8.encode('${completed.encode()}\n')),
    );
    await expectLater(a!.refresh(), throwsA(isA<FormatFailure>()));
  });
  test(
    'close drains accepted work, rejects new work and is idempotent',
    () async {
      final id = await task();
      await a!.close();
      final gated = _GatedAppendFolder(aFolder);
      a = await TaskStore.open(gated, '${root.path}/private-a');
      final active = a!.command(id, 'task.edited', {
        'title': 'Saved before close',
      });
      await gated.entered.future;
      final queued = a!.refresh();
      final closing = a!.close();
      final repeatedClose = a!.close();
      final afterCloseRejected = expectLater(a!.refresh(), throwsStateError);
      var closed = false;
      closing.then((_) => closed = true);
      try {
        expect(identical(closing, repeatedClose), true);
        await Future<void>.delayed(Duration.zero);
        expect(closed, false);
        // The database must remain available to the active command until drain.
        expect(state(a!, id)['title'], 'Groceries');
      } finally {
        gated.release.complete();
      }
      await active;
      expect(await queued, false);
      await afterCloseRejected;
      await closing;
      expect(closed, true);
      await a!.close();
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['title'], 'Saved before close');
      expect(a!.db.select('SELECT * FROM events').length, 3);
    },
  );
  test(
    'pending undo is validated before its local target is appended',
    () async {
      final id = await task();
      final otherTask = await task();
      final nextSeq =
          (a!.db.select('SELECT MAX(seq) AS n FROM events WHERE writer=?', [
                a!.writer,
              ]).first['n']
              as int) +
          1;
      final remote = const Uuid().v4();
      final undo = LogEvent(
        a!.space,
        remote,
        1,
        testClock(20, 0),
        id,
        'task.completionUndone',
        {'completion': '${a!.writer}:$nextSeq'},
      );
      await aFolder.create(
        '$remote.jsonl',
        Uint8List.fromList(utf8.encode('${undo.encode()}\n')),
      );
      await a!.refresh();
      final before = await aFolder.read('${a!.writer}.jsonl');
      final eventCount = a!.db.select('SELECT * FROM events').length;
      for (final candidate in [
        (
          entity: id,
          type: 'task.edited',
          data: <String, dynamic>{'title': 'Wrong type'},
        ),
        (entity: otherTask, type: 'task.completed', data: <String, dynamic>{}),
        (entity: id, type: 'task.completed', data: <String, dynamic>{}),
      ]) {
        await expectLater(
          a!.command(candidate.entity, candidate.type, candidate.data),
          throwsA(isA<FormatFailure>()),
        );
        expect(await aFolder.read('${a!.writer}.jsonl'), before);
        expect(a!.db.select('SELECT * FROM events').length, eventCount);
      }
      // A rejected local target must not leave a poisoned canonical record.
      await a!.refresh();
      expect(state(a!, id)['completed'], false);
    },
  );
  test(
    'missing canonical folder contents do not initialize a new manifest',
    () async {
      final id = await task();
      final expected = a!.rows;
      final originalSpace = a!.space;
      final savedFiles = <String, Uint8List>{};
      for (final file in await aFolder.list()) {
        savedFiles[file.name] = await aFolder.read(file.name);
      }
      await a!.close();
      a = null;
      for (final name in savedFiles.keys) {
        await File('${aFolder.location}/$name').delete();
      }
      await expectLater(
        TaskStore.open(aFolder, '${root.path}/private-a'),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        await aFolder.list(),
        isEmpty,
        reason: 'Opening a known space must not create a replacement manifest.',
      );
      // Restoring canonical files recovers the same identity and cached state.
      for (final entry in savedFiles.entries) {
        await aFolder.create(entry.key, entry.value);
      }
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(a!.space, originalSpace);
      expect(a!.rows, expected);
      expect(state(a!, id)['title'], 'Groceries');
    },
  );
  test(
    'offline tag removal preserves unseen same-name additions and atomic edits',
    () async {
      final id = await task();
      await a!.setTags(id, ['home']);
      await copy(aFolder, bFolder);
      await b!.refresh();
      final observed = Map<String, String>.from(
        state(a!, id)['tagRefs'] as Map,
      );
      await b!.command(id, 'task.tagsChanged', {
        'add': ['home', 'other'],
        'remove': <String>[],
      });
      await a!.edit(
        id,
        {'title': 'Revised'},
        tags: [],
        observedTagRefs: observed,
      );
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(state(a!, id)['title'], 'Revised');
      expect(state(a!, id)['tags'], ['home', 'other']);
      expect(a!.rows, b!.rows);
    },
  );
  test(
    'concurrent relative moves converge and survive cache rebuild',
    () async {
      final first = await task();
      final user = state(a!, first)['assignee'];
      final second = const Uuid().v4(), third = const Uuid().v4();
      for (final id in [second, third]) {
        await a!.command(id, 'task.created', {
          'title': id,
          'description': '',
          'assignee': user,
        });
      }
      await copy(aFolder, bFolder);
      await b!.refresh();
      await a!.moveBefore(third, first);
      await b!.moveBefore(second, first);
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(a!.rows, b!.rows);
      final expected = a!.rows;
      await a!.close();
      a = null;
      await File('${root.path}/private-a/cache.sqlite').delete();
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(a!.rows, expected);
    },
  );
  test(
    'concurrent recurrence completion has one durable successor and history reopen retains edits',
    () async {
      final id = await task();
      await a!.command(id, 'task.edited', {
        'schedule': {
          'startDate': '2026-10-01',
          'scheduledDate': '2026-10-02',
          'dueDate': '2026-10-03',
          'startTime': '09:30',
          'timeZone': 'America/Chicago',
          'recurrence': 'every week when done',
        },
      });
      await copy(aFolder, bFolder);
      await b!.refresh();
      final one = await a!.complete(
        id,
        completionDay: DateTime.utc(2026, 10, 20),
      );
      await b!.complete(id, completionDay: DateTime.utc(2026, 10, 21));
      final next = const Uuid().v5(id, 'successor');
      await a!.command(next, 'task.edited', {'description': 'Successor work'});
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(a!.rows, b!.rows);
      expect(a!.rows.where((r) => r['kind'] == 'task').length, 2);
      expect(state(a!, next)['description'], 'Successor work');
      expect((state(a!, next)['schedule'] as Map)['scheduledDate'], null);
      expect(
        a!.rows.indexWhere((r) => r['id'] == next),
        lessThan(a!.rows.indexWhere((r) => r['id'] == id)),
      );
      await a!.reopen(id, a!.activeCompletionIds(id));
      expect(state(a!, id)['completed'], false);
      expect(state(a!, next)['description'], 'Successor work');
      await a!.complete(id, completionDay: DateTime.utc(2026, 10, 22));
      expect(a!.rows.where((r) => r['kind'] == 'task').length, 2);
      expect(one.data['successor'], isNotNull);
      final expected = a!.rows;
      await a!.close();
      a = null;
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(a!.rows, expected);
      expect(a!.readFiles, 0);
    },
  );
  test('protocol v1 remains untouched and explicitly rejected', () async {
    await a!.close();
    a = null;
    final old = jsonEncode({'v': 1, 'id': const Uuid().v4()});
    await File('${aFolder.location}/tandemlog-space.json').writeAsString(old);
    await expectLater(
      TaskStore.open(aFolder, '${root.path}/fresh-private'),
      throwsA(
        isA<FormatFailure>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('older prerelease'),
            contains('Preserve this folder'),
            contains('new data folder'),
          ),
        ),
      ),
    );
    expect(
      await File('${aFolder.location}/tandemlog-space.json').readAsString(),
      old,
    );
  });
  test(
    'late winning recurrence seed cannot resurrect removed successor tags',
    () async {
      final id = await task();
      await a!.setTags(id, ['seed']);
      await a!.command(id, 'task.edited', {
        'schedule': {'dueDate': '2026-10-03', 'recurrence': 'every week'},
      });
      await copy(aFolder, bFolder);
      await b!.refresh();
      final early = a!.writer.compareTo(b!.writer) < 0 ? a! : b!;
      final late = identical(early, a) ? b! : a!;
      await early.complete(id, completionDay: DateTime.utc(2026, 10, 20));
      await late.complete(id, completionDay: DateTime.utc(2026, 10, 20));
      final next = const Uuid().v5(id, 'successor');
      await late.setTags(next, []);
      expect(state(late, next)['tags'], isEmpty);
      await File(
        '${early.folder.location}/${early.writer}.jsonl',
      ).copy('${late.folder.location}/${early.writer}.jsonl');
      await late.refresh();
      expect(state(late, next)['tags'], isEmpty);
      await copy(late.folder as LocalLogFolder, early.folder as LocalLogFolder);
      await early.refresh();
      expect(early.rows, late.rows);
    },
  );
  test(
    'successor collision and invalid tag/move references fail before append',
    () async {
      final id = await task();
      await a!.setTags(id, ['tag']);
      final user = state(a!, id)['assignee'] as String;
      final next = const Uuid().v5(id, 'successor');
      await a!.command(next, 'task.created', {
        'title': 'Existing',
        'description': '',
        'assignee': user,
      });
      await a!.command(id, 'task.edited', {
        'schedule': {'dueDate': '2026-10-03', 'recurrence': 'every week'},
      });
      final bytes = await aFolder.read('${a!.writer}.jsonl');
      await expectLater(
        a!.complete(id, completionDay: DateTime.utc(2026, 10, 20)),
        throwsA(isA<FormatFailure>()),
      );
      final ref = (state(a!, id)['tagRefs'] as Map).keys.single as String;
      await expectLater(
        a!.command(next, 'task.tagsChanged', {
          'add': [],
          'remove': [ref],
        }),
        throwsA(isA<FormatFailure>()),
      );
      await expectLater(a!.moveBefore(id, user), throwsA(isA<FormatFailure>()));
      await expectLater(
        a!.moveBefore(id, const Uuid().v4()),
        throwsA(isA<FormatFailure>()),
      );
      expect(await aFolder.read('${a!.writer}.jsonl'), bytes);
      await a!.refresh();
    },
  );
  test(
    'offline schedule edits converge atomically without mixing precise date-times',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      final left = {
        'startDate': '2026-10-01',
        'scheduledDate': '2026-10-01',
        'dueDate': '2026-10-01',
        'startTime': '09:00',
        'scheduledTime': '09:30',
        'dueTime': '10:00',
        'timeZone': 'UTC',
      };
      final right = {
        'startDate': '2026-10-01',
        'scheduledDate': '2026-10-01',
        'dueDate': '2026-10-01',
        'startTime': '11:00',
        'scheduledTime': '11:30',
        'dueTime': '12:00',
        'timeZone': 'UTC',
      };
      await a!.command(id, 'task.edited', {'schedule': left});
      await b!.command(id, 'task.edited', {'schedule': right});
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(a!.rows, b!.rows);
      expect(
        state(a!, id)['schedule'],
        a!.writer.compareTo(b!.writer) > 0 ? left : right,
      );
      final bytes = await aFolder.read('${a!.writer}.jsonl');
      await expectLater(
        a!.command(id, 'task.edited', {
          'schedule': {'startDate': '2026-12-01', 'dueDate': '2026-11-01'},
        }),
        throwsA(isA<FormatFailure>()),
      );
      await expectLater(
        a!.command(id, 'task.completed', {
          'successor': {
            'id': const Uuid().v5(id, 'successor'),
            'title': 'Invalid interval',
            'description': '',
            'assignee': state(a!, id)['assignee'],
            'tags': [],
            'schedule': {
              'startDate': '2026-10-01',
              'dueDate': '2026-10-01',
              'startTime': '11:00',
              'dueTime': '10:00',
            },
          },
        }),
        throwsA(isA<FormatFailure>()),
      );
      expect(await aFolder.read('${a!.writer}.jsonl'), bytes);
    },
  );
  test(
    'completion reconciles changed timezone before selecting civil day',
    () async {
      final id = await task();
      await a!.command(id, 'task.edited', {
        'schedule': {
          'dueDate': '2026-10-01',
          'timeZone': 'UTC',
          'recurrence': 'every day when done',
        },
      });
      await copy(aFolder, bFolder);
      await b!.refresh();
      await b!.command(id, 'task.edited', {
        'schedule': {
          'dueDate': '2026-10-01',
          'timeZone': 'America/Chicago',
          'recurrence': 'every day when done',
        },
      });
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      final completion = await a!.complete(
        id,
        completionInstant: DateTime.utc(2026, 10, 20, 2),
      );
      expect(completion.data['completedAt'], '2026-10-19');
      expect(
        ((completion.data['successor'] as Map)['schedule'] as Map)['dueDate'],
        '2026-10-20',
      );
    },
  );
  test(
    'completion durable append failure recovers parent and sole successor together',
    () async {
      final id = await task();
      await a!.command(id, 'task.edited', {
        'schedule': {'dueDate': '2026-10-01', 'recurrence': 'every day'},
      });
      await a!.close();
      a = null;
      final failing = _FailAfterAppendFolder(aFolder);
      a = await TaskStore.open(failing, '${root.path}/private-a');
      failing.failNext = true;
      await expectLater(
        a!.complete(id, completionDay: DateTime.utc(2026, 10, 20)),
        throwsStateError,
      );
      await a!.close();
      a = null;
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['completed'], true);
      expect(a!.rows.where((r) => r['kind'] == 'task'), hasLength(2));
      expect(state(a!, const Uuid().v5(id, 'successor'))['completed'], false);
      expect(a!.activeCompletionIds(id), hasLength(1));
    },
  );
  test('pending future tag removal cannot poison next local append', () async {
    final id = await task();
    final seq =
        (a!.db.select('SELECT MAX(seq) AS n FROM events WHERE writer=?', [
              a!.writer,
            ]).first['n']
            as int) +
        1;
    final remote = LogEvent(
      a!.space,
      b!.writer,
      1,
      testClock(100, 0),
      id,
      'task.tagsChanged',
      {
        'add': [],
        'remove': ['${a!.writer}:$seq:0'],
      },
    );
    await aFolder.append(
      '${b!.writer}.jsonl',
      Uint8List.fromList(utf8.encode('${remote.encode()}\n')),
    );
    await a!.refresh();
    final bytes = await aFolder.read('${a!.writer}.jsonl');
    await expectLater(a!.setTags(id, ['later']), throwsA(isA<FormatFailure>()));
    expect(await aFolder.read('${a!.writer}.jsonl'), bytes);
    await a!.refresh();
  });
  test(
    'offline older high sequence loses to a later wall-clock edit',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      LogEvent? old;
      for (var i = 0; i < 30; i++) {
        old = await a!.command(id, 'task.edited', {'title': 'Older $i'});
      }
      testNow = testNow.add(const Duration(hours: 1));
      final recent = await b!.command(id, 'task.edited', {'title': 'Newer'});
      expect(old!.sequence, greaterThan(recent.sequence));
      expect(recent.clock, greaterThan(old.clock));
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(state(a!, id)['title'], 'Newer');
      expect(a!.rows, b!.rows);
    },
  );
  test(
    'observed clocks precede local writes across rollback and restart',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      final remote = await b!.command(id, 'task.edited', {
        'description': 'Remote',
      });
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      testNow = testNow.subtract(const Duration(minutes: 1));
      final local = await a!.command(id, 'task.edited', {
        'title': 'Causal later',
      });
      expect(local.clock > remote.clock, isTrue);
      expect(local.clock.value, remote.clock.value + BigInt.one);
      final expected = a!.rows;
      await a!.close();
      a = null;
      a = await TaskStore.open(
        aFolder,
        '${root.path}/private-a',
        now: () => testNow,
      );
      expect(a!.readFiles, 0);
      expect(a!.rows, expected);
      final afterRestart = await a!.command(id, 'task.edited', {
        'description': 'After restart',
      });
      expect(afterRestart.clock > local.clock, isTrue);
    },
  );

  test(
    'future records remain immutable and readable while warning permits writes',
    () async {
      final id = await task();
      final future = LogEvent(
        a!.space,
        b!.writer,
        1,
        testClock(testNow.millisecondsSinceEpoch + 3600000, 123),
        id,
        'task.edited',
        {'title': 'Future record'},
      );
      final bytes = Uint8List.fromList(utf8.encode('${future.encode()}\n'));
      await aFolder.append('${b!.writer}.jsonl', bytes);
      await a!.refresh();
      expect(state(a!, id)['title'], 'Future record');
      expect(a!.clockWarning, isNotNull);
      final later = await a!.command(id, 'task.edited', {
        'title': 'Continued edit',
      });
      expect(later.clock.value, future.clock.value + BigInt.one);
      expect(state(a!, id)['title'], 'Continued edit');
      expect(await aFolder.read('${b!.writer}.jsonl'), bytes);
      final expected = a!.rows;
      await a!.close();
      a = null;
      a = await TaskStore.open(
        aFolder,
        '${root.path}/private-a',
        now: () => testNow,
      );
      expect(a!.clockWarning, isNotNull);
      expect(a!.rows, expected);
      expect(a!.readFiles, 0);
      final restarted = await a!.command(id, 'task.edited', {
        'description': 'Still writable',
      });
      expect(restarted.clock.value, later.clock.value + BigInt.one);
      testNow = testNow.add(const Duration(hours: 2));
      await a!.refresh();
      expect(a!.clockWarning, isNull);
      expect(await aFolder.read('${b!.writer}.jsonl'), bytes);
      expect(
        a!.db.select('SELECT * FROM events WHERE writer=?', [b!.writer]),
        hasLength(1),
      );
    },
  );
  test(
    'large clock rollback warns without blocking and warning clears when caught up',
    () async {
      final id = await task();
      final previous = LogEvent.decode(
        a!.db
                .select('SELECT raw FROM events ORDER BY clock DESC LIMIT 1')
                .first['raw']
            as String,
      );
      testNow = testNow.subtract(const Duration(minutes: 6));
      final changed = await a!.command(id, 'task.edited', {
        'title': 'Continued despite rollback',
      });
      expect(a!.clockWarning, isNotNull);
      expect(changed.clock.value, previous.clock.value + BigInt.one);
      expect(state(a!, id)['title'], 'Continued despite rollback');
      testNow = testNow.add(const Duration(minutes: 6));
      await a!.refresh();
      expect(a!.clockWarning, isNull);
    },
  );
  test(
    'SQLite and canonical clock retain exact signed-64-bit nanoseconds',
    () async {
      final id = await task();
      final exact = EventClock(EventClock.maximum - BigInt.from(2));
      final remote = LogEvent(
        a!.space,
        b!.writer,
        1,
        exact,
        id,
        'task.edited',
        {'title': 'Exact large timestamp'},
      );
      await aFolder.append(
        '${b!.writer}.jsonl',
        Uint8List.fromList(utf8.encode('${remote.encode()}\n')),
      );
      await a!.refresh();
      expect(
        BigInt.from(
          a!.db.select('SELECT clock FROM events WHERE writer=?', [
                b!.writer,
              ]).single['clock']
              as int,
        ),
        exact.value,
      );
      expect(a!.clockWarning, isNotNull);
      final changed = await a!.command(id, 'task.edited', {
        'description': 'Continued',
      });
      expect(changed.clock.value, exact.value + BigInt.one);
      expect(
        jsonDecode(changed.encode())['clock'],
        (exact.value + BigInt.one).toString(),
      );
      await a!.close();
      a = null;
      a = await TaskStore.open(
        aFolder,
        '${root.path}/private-a',
        now: () => testNow,
      );
      expect(state(a!, id)['description'], 'Continued');
      final finalInRange = await a!.command(id, 'task.edited', {
        'description': 'Last representable clock',
      });
      expect(finalInRange.clock.value, EventClock.maximum);
      final bytes = await aFolder.read('${a!.writer}.jsonl');
      await expectLater(
        a!.command(id, 'task.edited', {'description': 'Overflow'}),
        throwsFormatException,
      );
      expect(await aFolder.read('${a!.writer}.jsonl'), bytes);
    },
  );
  test(
    'recurrence inserts at current parent position and later moves stay independent',
    () async {
      final monthly = await task();
      await a!.command(monthly, 'task.edited', {
        'title': 'Monthly review',
        'schedule': {'dueDate': '2026-10-01', 'recurrence': 'every month'},
      });
      final read = const Uuid().v4();
      await a!.command(read, 'task.created', {
        'title': 'Read project notes',
        'description': '',
        'assignee': state(a!, monthly)['assignee'],
      });
      List<String> order() => a!.rows
          .where((r) => r['kind'] == 'task')
          .map((r) => r['id'] as String)
          .toList();
      await a!.moveBefore(monthly, null);
      expect(order(), [read, monthly]);
      await a!.complete(monthly, completionDay: DateTime.utc(2026, 10, 20));
      final next = const Uuid().v5(monthly, 'successor');
      expect(order(), [read, next, monthly]);
      await a!.moveBefore(monthly, read);
      expect(order(), [
        monthly,
        read,
        next,
      ], reason: 'Moving completed history does not drag its successor.');
      await a!.moveBefore(next, monthly);
      expect(order(), [next, monthly, read]);
      await a!.moveBefore(monthly, null);
      expect(order(), [next, read, monthly]);
      await a!.reopen(monthly, a!.activeCompletionIds(monthly));
      await a!.complete(monthly, completionDay: DateTime.utc(2026, 10, 21));
      expect(order(), [
        next,
        read,
        monthly,
      ], reason: 'Recompletion must not reposition the existing occurrence.');
      expect(state(a!, monthly)['completedAt'], '2026-10-21');
      final events = a!.db
          .select('SELECT raw FROM events')
          .map((r) => LogEvent.decode(r['raw'] as String))
          .toList();
      expect(projectWorkspace(events.reversed.toList()), a!.rows);
      await a!.reopen(monthly, a!.activeCompletionIds(monthly));
      expect(state(a!, monthly)['completedAt'], isNull);
      final reopenedEvents = a!.db
          .select('SELECT raw FROM events')
          .map((r) => LogEvent.decode(r['raw'] as String))
          .toList();
      expect(projectWorkspace(reopenedEvents.reversed.toList()), a!.rows);
    },
  );
  test('later creation stays after an earlier move to end', () async {
    final first = await task();
    final user = state(a!, first)['assignee'];
    final second = const Uuid().v4(), third = const Uuid().v4();
    await a!.command(second, 'task.created', {
      'title': 'Second',
      'description': '',
      'assignee': user,
    });
    await a!.moveBefore(first, null);
    await a!.command(third, 'task.created', {
      'title': 'Third',
      'description': '',
      'assignee': user,
    });
    expect(a!.rows.where((r) => r['kind'] == 'task').map((r) => r['id']), [
      second,
      first,
      third,
    ]);
  });
  test(
    'late pre-completion move converges and old order cache rebuilds without log writes',
    () async {
      final monthly = await task();
      await a!.command(monthly, 'task.edited', {
        'schedule': {'dueDate': '2026-10-01', 'recurrence': 'every month'},
      });
      final read = const Uuid().v4();
      await a!.command(read, 'task.created', {
        'title': 'Read project notes',
        'description': '',
        'assignee': state(a!, monthly)['assignee'],
      });
      await copy(aFolder, bFolder);
      await b!.refresh();
      await a!.moveBefore(monthly, null);
      testNow = testNow.add(const Duration(milliseconds: 1));
      await b!.complete(monthly, completionDay: DateTime.utc(2026, 10, 20));
      final next = const Uuid().v5(monthly, 'successor');
      expect(b!.rows.where((r) => r['kind'] == 'task').map((r) => r['id']), [
        next,
        monthly,
        read,
      ]);
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(a!.rows, b!.rows);
      expect(a!.rows.where((r) => r['kind'] == 'task').map((r) => r['id']), [
        read,
        next,
        monthly,
      ]);
      final expected = a!.rows;
      final raw = await aFolder.read('${a!.writer}.jsonl');
      a!.db.execute('UPDATE positions SET rank=-rank');
      a!.db.execute("DELETE FROM metadata WHERE key='order_projection'");
      await a!.close();
      a = null;
      a = await TaskStore.open(
        aFolder,
        '${root.path}/private-a',
        now: () => testNow,
      );
      expect(a!.rows, expected);
      expect(a!.readFiles, 0);
      expect(await aFolder.read('${a!.writer}.jsonl'), raw);
      expect(
        a!.db
            .select("SELECT value FROM metadata WHERE key='order_projection'")
            .single['value'],
        '2',
      );
    },
  );
}

/// Holds an append open so shutdown tests exercise real asynchronous overlap.
class _GatedAppendFolder implements LogFolder {
  final LogFolder delegate;
  final entered = Completer<void>();
  final release = Completer<void>();
  _GatedAppendFolder(this.delegate);
  @override
  String get location => delegate.location;
  @override
  Future<List<LogFileInfo>> list() => delegate.list();
  @override
  Future<Uint8List> read(String name) => delegate.read(name);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      delegate.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    entered.complete();
    await release.future;
    await delegate.append(name, bytes);
  }
}

class _FailAfterAppendFolder implements LogFolder {
  _FailAfterAppendFolder(this.delegate);
  final LogFolder delegate;
  bool failNext = false;
  @override
  String get location => delegate.location;
  @override
  Future<List<LogFileInfo>> list() => delegate.list();
  @override
  Future<Uint8List> read(String name) => delegate.read(name);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      delegate.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    await delegate.append(name, bytes);
    if (failNext) {
      failNext = false;
      throw StateError('Injected failure after durable append');
    }
  }
}

EventClock testClock(int wallMs, int increment) => EventClock(
  BigInt.from(wallMs) * BigInt.from(1000000) + BigInt.from(increment),
);
