import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory root;
  late LocalLogFolder aFolder, bFolder;
  TaskStore? a, b;
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
    a = await TaskStore.open(aFolder, '${root.path}/private-a');
    await copy(aFolder, bFolder);
    b = await TaskStore.open(bFolder, '${root.path}/private-b');
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
    final raw = LogEvent(a!.space, remote, 1, 1, id, 'user.created', {
      'name': 'Lee',
    }).encode();
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
        seq,
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
        10,
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
        9,
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
      10,
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
      11,
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
        20,
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
