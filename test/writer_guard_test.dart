import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

class _Guard extends WriterGuard {
  final FileWriterGuard inner;
  bool failPrepare = false, failAcknowledgment = false;
  _Guard(this.inner);
  @override
  Future<WriterGuardState?> load(String space, String writer) =>
      inner.load(space, writer);
  @override
  Future<void> prepare(
    String space,
    String writer,
    int sequence,
    String hash,
    List<PreparedWriterRecord> records,
  ) async {
    if (failPrepare) {
      throw const FileSystemException('Injected guard preparation failure');
    }
    await inner.prepare(space, writer, sequence, hash, records);
  }

  @override
  Future<void> acknowledge(
    String space,
    String writer,
    int sequence,
    String hash,
  ) async {
    if (failAcknowledgment) {
      throw const FileSystemException('Injected guard acknowledgment failure');
    }
    await inner.acknowledge(space, writer, sequence, hash);
  }
}

class _Folder implements LogFolder, RangeLogFolder {
  final LocalLogFolder inner;
  String? alias;
  int logBytes = 0, appends = 0;
  int? completePrefix;
  Uint8List? attempted;
  bool partialTail = false, failBefore = false, failAfter = false;
  _Folder(this.inner);
  @override
  String get location => alias ?? inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) async {
    final bytes = await inner.read(name);
    if (name.endsWith('.jsonl')) logBytes += bytes.length;
    return bytes;
  }

  @override
  Future<Uint8List> readFrom(String name, int offset) async {
    final bytes = await inner.readFrom(name, offset);
    if (name.endsWith('.jsonl')) logBytes += bytes.length;
    return bytes;
  }

  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    appends++;
    attempted = Uint8List.fromList(bytes);
    if (failBefore) {
      failBefore = false;
      throw StateError('Before append');
    }
    if (completePrefix != null) {
      final count = completePrefix!;
      completePrefix = null;
      var end = 0, complete = 0;
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] == 10 && ++complete == count) {
          end = i + 1;
          break;
        }
      }
      if (partialTail) end += 20;
      await inner.append(name, Uint8List.sublistView(bytes, 0, end));
      throw StateError('Incomplete append');
    }
    await inner.append(name, bytes);
    if (failAfter) {
      failAfter = false;
      throw StateError('Lost acknowledgment');
    }
  }
}

void main() {
  late Directory root;
  late _Folder folder;
  late String owner, user, task, cache;
  late _Guard guard;
  TaskStore? store;
  Future<void> open([
    String? cachePath,
    LogFolder? dataFolder,
    String? writer,
  ]) async {
    store = await TaskStore.open(
      dataFolder ?? folder,
      cachePath ?? cache,
      writerIdentity: writer ?? owner,
      writerGuard: guard,
    );
  }

  Future<void> close() async {
    await store?.close();
    store = null;
  }

  Future<WriterGuardState> state() async =>
      (await guard.load(store!.space, owner))!;
  String title() =>
      store!.rows.firstWhere((row) => row['id'] == task)['title'] as String;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('writer-safety-');
    final shared = await Directory('${root.path}/data').create();
    folder = _Folder(LocalLogFolder(shared.path));
    cache = '${root.path}/cache';
    guard = _Guard(FileWriterGuard('${root.path}/installation'));
    owner = const Uuid().v4();
    user = const Uuid().v4();
    task = const Uuid().v4();
    await open();
    await store!.command(user, 'user.created', {'name': 'Lee'});
    await store!.command(task, 'task.created', {
      'title': 'Original',
      'description': '',
      'assignee': user,
    });
  });
  tearDown(() async {
    await close();
    await root.delete(recursive: true);
  });

  for (final alias in ['other directory', 'URI alias', 'rebuilt cache']) {
    test(
      'acknowledged head blocks old snapshot through $alias without sequence reuse',
      () async {
        final snapshot = await folder.inner.read('$owner.jsonl');
        final manifest = await folder.inner.read('tandemlog-space.json');
        final accepted = await store!.command(task, 'task.edited', {
          'title': 'Acknowledged',
        });
        final space = store!.space;
        await close();
        LogFolder target = folder;
        if (alias == 'other directory') {
          final path = await Directory('${root.path}/restored').create();
          final restored = LocalLogFolder(path.path);
          await restored.create('tandemlog-space.json', manifest);
          await restored.create('$owner.jsonl', snapshot);
          target = restored;
        } else {
          await folder.inner.file('$owner.jsonl').writeAsBytes(snapshot);
          if (alias == 'URI alias') {
            folder.alias = 'content://provider/document/alternative-id';
          }
          if (alias == 'rebuilt cache') {
            await File('$cache/cache.sqlite').delete();
          }
        }
        await expectLater(
          open(
            alias == 'rebuilt cache' ? cache : '${root.path}/another-cache',
            target,
          ),
          throwsA(
            isA<WriterGuardFailure>().having(
              (failure) => failure.message,
              'checkpoint',
              contains('acknowledged safety checkpoint'),
            ),
          ),
        );
        final retained = await guard.load(space, owner);
        expect(retained!.sequence, 3);
        expect(retained.hash, accepted.hash);
        expect(await target.read('$owner.jsonl'), snapshot);
        expect(folder.appends, 3);
      },
    );
  }

  test(
    'missing owned log is blocked even with a new cache and data directory',
    () async {
      final manifest = await folder.inner.read('tandemlog-space.json');
      final space = store!.space;
      await close();
      final restored = LocalLogFolder(
        (await Directory('${root.path}/missing').create()).path,
      );
      await restored.create('tandemlog-space.json', manifest);
      await expectLater(
        open('${root.path}/fresh', restored),
        throwsA(isA<WriterGuardFailure>()),
      );
      expect((await guard.load(space, owner))!.sequence, 2);
      expect((await restored.list()).map((entry) => entry.name), [
        'tandemlog-space.json',
      ]);
    },
  );

  test(
    'same sequence with a fully recomputed valid chain rejects against private head',
    () async {
      await store!.command(task, 'task.edited', {'title': 'Acknowledged'});
      final original = await folder.inner.read('$owner.jsonl');
      final space = store!.space;
      await close();
      var head = eventGenesisHash(space, owner);
      final changed = <String>[];
      for (final line in utf8.decode(original).trim().split('\n')) {
        final event = jsonDecode(line) as Map<String, dynamic>;
        if (event['seq'] == 3) event['data']['title'] = 'Fork';
        event['previousHash'] = head;
        event['hash'] = eventRecordHash(event);
        head = event['hash'] as String;
        changed.add(canonicalEventJson(event));
      }
      final fork = Uint8List.fromList(utf8.encode('${changed.join('\n')}\n'));
      await folder.inner.file('$owner.jsonl').writeAsBytes(fork);
      await expectLater(
        open('${root.path}/fresh'),
        throwsA(isA<WriterGuardFailure>()),
      );
      expect(await folder.inner.read('$owner.jsonl'), fork);
      expect((await guard.load(space, owner))!.sequence, 3);
    },
  );

  test(
    'an explicitly different writer can use a restored snapshot without changing original guard',
    () async {
      final snapshot = await folder.inner.read('$owner.jsonl');
      final accepted = await store!.command(task, 'task.edited', {
        'title': 'Acknowledged',
      });
      final space = store!.space;
      await close();
      await folder.inner.file('$owner.jsonl').writeAsBytes(snapshot);
      final other = const Uuid().v4();
      await open('${root.path}/new-writer-cache', folder, other);
      final event = await store!.command(task, 'task.edited', {
        'title': 'New writer',
      });
      expect(event.sequence, 1);
      expect(event.writer, other);
      expect((await guard.load(space, owner))!.hash, accepted.hash);
      expect(await folder.inner.read('$owner.jsonl'), snapshot);
    },
  );

  test(
    'guard metadata is durable before append and normal reopen/refresh reads no old history',
    () async {
      final accepted = await store!.command(task, 'task.edited', {
        'title': 'Saved',
      });
      expect((await state()).hash, accepted.hash);
      final before = await folder.inner.read('$owner.jsonl');
      await close();
      folder.logBytes = 0;
      await open();
      for (var i = 0; i < 6; i++) {
        expect(await store!.refresh(), isFalse);
      }
      expect(folder.logBytes, 0);
      expect(store!.readFiles, 0);
      guard.failPrepare = true;
      await expectLater(
        store!.command(task, 'task.edited', {'title': 'Never appended'}),
        throwsA(isA<FileSystemException>()),
      );
      expect(folder.appends, 3);
      expect(await folder.inner.read('$owner.jsonl'), before);
      expect((await state()).sequence, 3);
    },
  );

  test(
    'zero-record failed append reserves candidate across restart until exact late arrival',
    () async {
      folder.failBefore = true;
      await expectLater(
        store!.command(task, 'task.edited', {'title': 'Unwritten'}),
        throwsStateError,
      );
      final pending = await state();
      expect(pending.sequence, 2);
      expect(pending.pending.single.sequence, 3);
      await close();
      folder.logBytes = 0;
      await open('${root.path}/fresh-cache');
      expect((await state()).pending, hasLength(1));
      expect((await state()).sequence, 2);
      expect(folder.logBytes, greaterThan(0));
      for (var i = 0; i < 3; i++) {
        await store!.refresh();
      }
      final blockedReceipts = <OperationReceipt>[];
      await expectLater(
        store!.command(task, 'task.edited', {
          'title': 'Different',
        }, onPrepared: blockedReceipts.add),
        throwsA(isA<WriterGuardFailure>()),
      );
      final blockedBatch = await store!.bulkEdit(
        [task],
        BulkTaskEdit(addTags: ['Different']),
        expectedTaskSnapshot: store!.taskSnapshot,
        onPrepared: blockedReceipts.add,
      );
      expect(blockedBatch.error, isA<WriterGuardFailure>());
      expect(
        blockedReceipts,
        isEmpty,
        reason:
            'Blocked attempts must not emit duplicate reserved IDs to Undo callbacks.',
      );
      expect(folder.appends, 3);
      await folder.inner.append('$owner.jsonl', folder.attempted!);
      await store!.refresh();
      expect(title(), 'Unwritten');
      expect((await state()).pending, isEmpty);
      final retry = await store!.command(task, 'task.edited', {
        'title': 'Retry',
      }, onPrepared: blockedReceipts.add);
      expect(blockedReceipts, hasLength(1));
      expect(retry.sequence, 4);
      expect(title(), 'Retry');
    },
  );

  test(
    'lost append acknowledgment reconciles exact pending head after restart without duplicate sequence',
    () async {
      folder.failAfter = true;
      final receipts = <OperationReceipt>[];
      await expectLater(
        store!.command(task, 'task.edited', {
          'title': 'Durable',
        }, onPrepared: receipts.add),
        throwsStateError,
      );
      expect(
        (await state()).pending.single.hash,
        LogEvent.decode(receipts.single.raw).hash,
      );
      expect(store!.confirmedOperations(receipts), isEmpty);
      await close();
      await open('${root.path}/fresh-cache');
      expect(title(), 'Durable');
      expect((await state()).sequence, 3);
      expect((await state()).pending, isEmpty);
      expect(store!.confirmedOperations(receipts), {receipts.single.id});
      expect(
        (await store!.command(task, 'task.edited', {'title': 'Next'})).sequence,
        4,
      );
    },
  );

  test(
    'acknowledgment guard failure rolls cache back and blocks false confirmation until restart',
    () async {
      final receipts = <OperationReceipt>[];
      guard.failAcknowledgment = true;
      // Fail only after preparation: the pre-command refresh is unchanged and
      // must not require a new private write to acknowledge its existing head.
      guard.failAcknowledgment = false;
      final original = guard.inner;
      final failing = _FailAfterPrepareGuard(original);
      await close();
      store = await TaskStore.open(
        folder,
        cache,
        writerIdentity: owner,
        writerGuard: failing,
      );
      await expectLater(
        store!.command(task, 'task.edited', {
          'title': 'Durable',
        }, onPrepared: receipts.add),
        throwsA(isA<FileSystemException>()),
      );
      expect(title(), 'Original');
      expect(store!.confirmedOperations(receipts), isEmpty);
      expect((await original.load(store!.space, owner))!.pending, hasLength(1));
      await expectLater(
        store!.command(task, 'task.edited', {'title': 'Blocked'}),
        throwsA(isA<FileSystemException>()),
      );
      expect(folder.appends, 3);
      await close();
      await open();
      expect(title(), 'Durable');
      expect((await state()).sequence, 3);
      expect((await state()).pending, isEmpty);
      expect(store!.confirmedOperations(receipts), {receipts.single.id});
    },
  );

  for (final partial in [false, true]) {
    test(
      'batch durable prefix ${partial ? 'with partial tail blocks' : 'reconciles'} across cache replacement',
      () async {
        final one = const Uuid().v4(),
            two = const Uuid().v4(),
            three = const Uuid().v4();
        folder.completePrefix = 1;
        folder.partialTail = partial;
        final result = await store!.createTasks({
          one: 'One',
          two: 'Two',
          three: 'Three',
        }, user);
        expect(result.committedIds, partial ? isEmpty : [one]);
        final space = store!.space;
        final current = await folder.inner.read('$owner.jsonl');
        await close();
        if (partial) {
          final guardBefore = await guard.load(space, owner);
          expect(guardBefore!.sequence, 2);
          expect(guardBefore.pending, hasLength(3));
          await expectLater(
            open('${root.path}/fresh-cache'),
            throwsA(isA<FormatFailure>()),
          );
          expect(await folder.inner.read('$owner.jsonl'), current);
          expect((await guard.load(space, owner))!.pending, hasLength(3));
        } else {
          await open('${root.path}/fresh-cache');
          expect((await state()).sequence, 3);
          expect((await state()).pending, hasLength(2));
          await expectLater(
            store!.command(task, 'task.edited', {'title': 'Different'}),
            throwsA(isA<WriterGuardFailure>()),
          );
          final attempted = folder.attempted!;
          await folder.inner.append(
            '$owner.jsonl',
            Uint8List.sublistView(attempted, attempted.indexOf(10) + 1),
          );
          await store!.refresh();
          expect((await state()).pending, isEmpty);
          final retry = await store!.createTasks({
            one: 'One',
            two: 'Two',
            three: 'Three',
          }, user);
          expect(retry.succeeded, isTrue);
          expect((await state()).sequence, 5);
          final events = utf8
              .decode(await folder.inner.read('$owner.jsonl'))
              .trim()
              .split('\n')
              .map(LogEvent.decode)
              .toList();
          expect(events.map((event) => event.sequence), [1, 2, 3, 4, 5]);
        }
      },
    );
  }

  test(
    'valid cache12 upgrades once without changing canonical bytes or writer guard',
    () async {
      final expected = store!.rows;
      final canonical = await folder.inner.read('$owner.jsonl');
      final checkpoint = await state();
      store!.db.execute('PRAGMA user_version=12');
      await close();
      folder.logBytes = 0;
      await open();
      expect(
        store!.db.select('PRAGMA user_version').single['user_version'],
        13,
      );
      expect(store!.rows, expected);
      expect(folder.logBytes, canonical.length);
      expect((await state()).hash, checkpoint.hash);
      expect(await folder.inner.read('$owner.jsonl'), canonical);
      final backups = await Directory(
        cache,
      ).list().where((entry) => entry.path.contains('cache-v12-')).toList();
      expect(backups, hasLength(1));
      final retained = sqlite3.open(
        backups.single.path,
        mode: OpenMode.readOnly,
      );
      try {
        expect(
          retained.select('PRAGMA user_version').single['user_version'],
          12,
        );
      } finally {
        retained.close();
      }
      await close();
      folder.logBytes = 0;
      await open();
      expect(folder.logBytes, 0);
      expect(store!.readFiles, 0);
    },
  );

  for (final version in [10, 11, 12]) {
    for (final retired in ['separate tag event', 'generic recurring Undo']) {
      test(
        'cache$version retains old materialization and rejects $retired on upgrade',
        () async {
          if (retired == 'generic recurring Undo') {
            await store!.command(task, 'task.edited', {
              'schedule': {'dueDate': '2030-01-01', 'recurrence': 'every day'},
            });
            await store!.complete(
              task,
              completionDay: DateTime.utc(2030, 1, 1),
            );
          }
          final checkpoint = await state();
          final previous = LogEvent.decode(
            store!.db.select(
                  'SELECT raw FROM events WHERE writer=? ORDER BY seq DESC LIMIT 1',
                  [owner],
                ).single['raw']
                as String,
          );
          final event = LogEvent(
            store!.space,
            owner,
            previous.sequence + 1,
            EventClock(previous.clock.value + BigInt.one),
            task,
            retired == 'separate tag event'
                ? 'task.tagsChanged'
                : 'task.operationUndone',
            retired == 'separate tag event'
                ? {
                    'add': ['Old'],
                    'remove': <String>[],
                  }
                : {'operation': previous.id},
          );
          final raw = event.encode(previousHash: previous.hash);
          final map = jsonDecode(raw) as Map<String, dynamic>;
          await folder.inner.append(
            '$owner.jsonl',
            Uint8List.fromList(utf8.encode('$raw\n')),
          );
          final canonical = await folder.inner.read('$owner.jsonl');
          store!.db.execute('INSERT INTO events VALUES (?,?,?,?,?,?)', [
            event.id,
            task,
            owner,
            event.sequence,
            event.clock.value.toInt(),
            raw,
          ]);
          store!.db.execute('DELETE FROM stream_ranges WHERE name=?', [
            '$owner.jsonl',
          ]);
          store!.db.execute(
            'UPDATE streams SET offset=?,hash_offset=?,hash=?,chain_head=?,last_seq=?,last_clock=?,stamp=? WHERE name=?',
            [
              canonical.length,
              canonical.length,
              sha256.convert(canonical).toString(),
              map['hash'],
              event.sequence,
              event.clock.value.toInt(),
              '',
              '$owner.jsonl',
            ],
          );
          store!.db.execute('PRAGMA user_version=$version');
          final originalView = store!.db.select(
            'SELECT raw FROM views WHERE id=?',
            [task],
          ).single['raw'];
          final space = store!.space;
          await close();
          await expectLater(open(), throwsA(isA<FormatFailure>()));
          expect(await folder.inner.read('$owner.jsonl'), canonical);
          expect((await guard.load(space, owner))!.hash, checkpoint.hash);
          final backups = await Directory(cache)
              .list()
              .where((entry) => entry.path.contains('cache-v$version-'))
              .toList();
          expect(backups, hasLength(1));
          final retained = sqlite3.open(
            backups.single.path,
            mode: OpenMode.readOnly,
          );
          try {
            expect(
              retained.select('SELECT raw FROM events WHERE id=?', [
                event.id,
              ]).single['raw'],
              raw,
            );
            expect(
              retained.select('SELECT raw FROM views WHERE id=?', [
                task,
              ]).single['raw'],
              originalView,
            );
          } finally {
            retained.close();
          }
        },
      );
    }
  }

  test(
    'noninteger pending sequence is rejected without normalizing private metadata',
    () async {
      final space = store!.space;
      final file = File(
        '${root.path}/installation/writer-guards/$space.$owner.json',
      );
      final metadata =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      metadata['pending'] = [
        {'sequence': 3.0, 'hash': '0' * 64},
      ];
      final invalid = jsonEncode(metadata);
      await file.writeAsString(invalid);
      await expectLater(
        guard.load(space, owner),
        throwsA(isA<WriterGuardFailure>()),
      );
      expect(await file.readAsString(), invalid);
      expect(folder.appends, 2);
    },
  );

  test(
    'guard instances serialize candidate reservation for the same installation identity',
    () async {
      final checkpoint = await state();
      final other = FileWriterGuard('${root.path}/installation');
      final candidates = [PreparedWriterRecord(3, '1' * 64)];
      final outcomes = await Future.wait([
        guard
            .prepare(
              store!.space,
              owner,
              checkpoint.sequence,
              checkpoint.hash,
              candidates,
            )
            .then<Object?>((_) => null, onError: (Object failure) => failure),
        other
            .prepare(
              store!.space,
              owner,
              checkpoint.sequence,
              checkpoint.hash,
              [PreparedWriterRecord(3, '2' * 64)],
            )
            .then<Object?>((_) => null, onError: (Object failure) => failure),
      ]);
      expect(outcomes.where((outcome) => outcome == null), hasLength(1));
      expect(outcomes.whereType<WriterGuardFailure>(), hasLength(1));
      expect((await state()).pending, hasLength(1));
      expect(folder.appends, 2);
    },
  );

  test(
    'malformed private guard is preserved and never rebuilt from disposable cache',
    () async {
      final space = store!.space;
      await close();
      final checkpoint = File(
        '${root.path}/installation/writer-guards/$space.$owner.json',
      );
      const corrupt = '{"v":99}';
      await checkpoint.writeAsString(corrupt);
      await expectLater(
        open('${root.path}/fresh-cache'),
        throwsA(isA<WriterGuardFailure>()),
      );
      expect(await checkpoint.readAsString(), corrupt);
      expect(folder.appends, 2);
    },
  );
}

class _FailAfterPrepareGuard implements WriterGuard {
  final FileWriterGuard inner;
  bool prepared = false;
  _FailAfterPrepareGuard(this.inner);
  @override
  Future<WriterGuardState?> load(String space, String writer) =>
      inner.load(space, writer);
  @override
  Future<void> prepare(
    String space,
    String writer,
    int sequence,
    String hash,
    List<PreparedWriterRecord> records,
  ) async {
    await inner.prepare(space, writer, sequence, hash, records);
    prepared = true;
  }

  @override
  Future<void> acknowledge(
    String space,
    String writer,
    int sequence,
    String hash,
  ) async {
    if (prepared) {
      throw const FileSystemException('Injected guard acknowledgment failure');
    }
    await inner.acknowledge(space, writer, sequence, hash);
  }
}
