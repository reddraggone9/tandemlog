import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

/// Counts actual bytes returned by real seek/full operations, not bytes after
/// slicing a whole-file read. Handles are freshly opened on every operation.
class _MeasuredFolder implements LogFolder, RangeLogFolder {
  _MeasuredFolder(this.inner);
  final LocalLogFolder inner;
  bool knownSize = true, seekable = true;
  int fullBytes = 0, suffixBytes = 0, fullReads = 0;
  final offsets = <int>[];
  Future<void> Function(String)? beforeRange;
  Future<void> Function(String, Uint8List)? afterAppend;
  void reset() {
    fullBytes = suffixBytes = fullReads = 0;
    offsets.clear();
  }

  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() async => [
    for (final info in await inner.list())
      LogFileInfo(info.name, '', size: knownSize ? info.size : null),
  ];
  @override
  Future<Uint8List> read(String name) async {
    final bytes = await inner.read(name);
    if (name.endsWith('.jsonl')) {
      fullReads++;
      fullBytes += bytes.length;
    }
    return bytes;
  }

  @override
  Future<Uint8List?> readFrom(String name, int offset) async {
    offsets.add(offset);
    await beforeRange?.call(name);
    if (!seekable) return null;
    final bytes = await inner.readFrom(name, offset);
    suffixBytes += bytes.length;
    return bytes;
  }

  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    await inner.append(name, bytes);
    await afterAppend?.call(name, bytes);
  }
}

void main() {
  late Directory root;
  late _MeasuredFolder folder;
  TaskStore? store;
  late String space, remote, user, task, owner;
  late String cache;
  int sequence = 0;
  String? chainHead;
  Uint8List record(String type, Map<String, dynamic> data, {String? entity}) {
    sequence++;
    final event = LogEvent(
      space,
      remote,
      sequence,
      EventClock(BigInt.from(sequence)),
      entity ?? task,
      type,
      data,
    );
    final raw = event.encode(previousHash: chainHead);
    chainHead = LogEvent.decode(raw).hash;
    return Uint8List.fromList(utf8.encode('$raw\n'));
  }

  File log() => folder.inner.file('$remote.jsonl');
  Future<void> seed([int minimumBytes = 0]) async {
    final builder = BytesBuilder(copy: false);
    builder.add(record('user.created', {'name': '李 👩🏽‍💻'}, entity: user));
    builder.add(
      record('task.created', {
        'title': 'Original',
        'description': '',
        'assignee': user,
      }),
    );
    while (builder.length < minimumBytes) {
      builder.add(record('task.edited', {'description': 'x' * 9000}));
    }
    await folder.create('$remote.jsonl', builder.takeBytes());
  }

  Future<void> open() async {
    store = await TaskStore.open(folder, cache, writerIdentity: owner);
  }

  Future<void> reopen() async {
    await store!.close();
    store = null;
    folder.reset();
    await open();
  }

  int offset() =>
      store!.db.select('SELECT offset FROM streams WHERE name=?', [
            '$remote.jsonl',
          ]).single['offset']
          as int;
  String title() =>
      store!.rows.firstWhere((r) => r['id'] == task)['title'] as String;
  Future<void> replace(Uint8List bytes) async {
    final tmp = folder.inner.file('replacement.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(log().path);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('incremental-history-');
    folder = _MeasuredFolder(
      LocalLogFolder((await Directory('${root.path}/shared').create()).path),
    );
    cache = '${root.path}/private';
    space = const Uuid().v4();
    remote = const Uuid().v4();
    user = const Uuid().v4();
    task = const Uuid().v4();
    owner = const Uuid().v4();
    sequence = 0;
    chainHead = null;
    await folder.create(
      'tandemlog-space.json',
      Uint8List.fromList(
        utf8.encode(jsonEncode({'v': protocolVersion, 'id': space})),
      ),
    );
  });
  tearDown(() async {
    await store?.close();
    await root.delete(recursive: true);
  });

  for (final size in [10 * 1024, 1024 * 1024]) {
    test(
      'cache reopen and repeated unchanged refresh read zero log bytes at $size bytes',
      () async {
        await seed(size);
        await open();
        final snapshot = store!.taskSnapshot;
        final initialLength = await log().length();
        expect(folder.suffixBytes, initialLength);
        await reopen();
        expect(store!.taskSnapshot, snapshot);
        for (var i = 0; i < 12; i++) {
          expect(await store!.refresh(), isFalse);
        }
        expect(folder.fullBytes, 0);
        expect(folder.suffixBytes, 0);
        expect(folder.offsets, isEmpty);
        expect(store!.readFiles, 0);
        final tail = record('task.edited', {'title': 'Appended'});
        await folder.inner.append('$remote.jsonl', tail);
        expect(await store!.refresh(), isTrue);
        expect(folder.offsets, [initialLength]);
        expect(folder.suffixBytes, tail.length);
        expect(folder.fullBytes, 0);
        expect(title(), 'Appended');
        expect(
          store!.db
              .select('SELECT * FROM stream_ranges')
              .single['start_offset'],
          initialLength,
        );
        await reopen();
        expect(folder.fullBytes + folder.suffixBytes, 0);
        expect(title(), 'Appended');
      },
    );
  }

  test(
    'same-length historical rewrite stays cached until explicit verification; fresh cache rejects invalid selfhash',
    () async {
      await seed();
      await open();
      final original = await log().readAsString();
      await replace(
        Uint8List.fromList(
          utf8.encode(original.replaceFirst('Original', 'Replaced')),
        ),
      );
      await reopen();
      expect(title(), 'Original');
      expect(folder.fullBytes + folder.suffixBytes, 0);
      await expectLater(store!.verifyHistory(), throwsA(isA<FormatFailure>()));
      expect(title(), 'Original');
      await expectLater(
        TaskStore.open(
          folder,
          '${root.path}/fresh',
          writerIdentity: const Uuid().v4(),
        ),
        throwsA(isA<HistoryVerificationFailure>()),
      );
    },
  );

  test(
    'explicit verification checks newly observed ranges after append and reopen',
    () async {
      await seed();
      await open();
      final tail = record('task.edited', {'title': 'NewTitle'});
      await folder.inner.append('$remote.jsonl', tail);
      await store!.refresh();
      final ranges = store!.db.select('SELECT * FROM stream_ranges');
      expect(ranges.length, 1);
      expect(ranges.single['hash'], sha256.convert(tail).toString());
      await replace(
        Uint8List.fromList(
          utf8.encode(
            (await log().readAsString()).replaceFirst('NewTitle', 'BadTitle'),
          ),
        ),
      );
      await reopen();
      expect(title(), 'NewTitle');
      await expectLater(store!.verifyHistory(), throwsA(isA<FormatFailure>()));
      expect(store!.db.select('SELECT * FROM stream_ranges').length, 1);
    },
  );

  test(
    'successful explicit verification compacts checked ranges into a new whole-prefix baseline',
    () async {
      await seed();
      await open();
      await folder.inner.append(
        '$remote.jsonl',
        record('task.edited', {'title': 'Next'}),
      );
      await store!.refresh();
      folder.reset();
      expect(await store!.verifyHistory(), isFalse);
      expect(folder.fullBytes, await log().length());
      expect(store!.db.select('SELECT * FROM stream_ranges'), isEmpty);
      final row = store!.db.select('SELECT * FROM streams').single;
      expect(row['hash_offset'], row['offset']);
      expect(row['hash'], sha256.convert(await log().readAsBytes()).toString());
      await reopen();
      expect(folder.fullBytes + folder.suffixBytes, 0);
    },
  );

  for (final mode in ['missing', 'truncated']) {
    test(
      '$mode admitted log fails on resume and cold reopen without content reads',
      () async {
        await seed();
        await open();
        if (mode == 'missing') {
          await log().delete();
        } else {
          await log().writeAsBytes(
            (await log().readAsBytes()).sublist(0, offset() - 1),
          );
        }
        folder.reset();
        await expectLater(store!.refresh(), throwsA(isA<FormatFailure>()));
        expect(folder.fullBytes + folder.suffixBytes, 0);
        await store!.close();
        store = null;
        await expectLater(open(), throwsA(isA<FormatFailure>()));
        expect(folder.fullBytes + folder.suffixBytes, 0);
      },
    );
  }

  test(
    'truncation between size observation and fresh seek fails without advancing cache',
    () async {
      await seed();
      await open();
      final checkpoint = offset();
      await folder.inner.append(
        '$remote.jsonl',
        record('task.edited', {'title': 'Never admitted'}),
      );
      folder.beforeRange = (_) async {
        await log().writeAsBytes(
          (await log().readAsBytes()).sublist(0, checkpoint - 1),
        );
      };
      await expectLater(store!.refresh(), throwsA(isA<FolderAccessFailure>()));
      expect(offset(), checkpoint);
      expect(title(), 'Original');
    },
  );

  test(
    'atomic replacement with growth reads only new suffix and audits changed old prefix explicitly',
    () async {
      await seed();
      await open();
      final checkpoint = offset();
      final prior = await log().readAsString();
      final tail = record('task.edited', {'title': 'Latest'});
      await replace(
        Uint8List.fromList([
          ...utf8.encode(prior.replaceFirst('Original', 'Replaced')),
          ...tail,
        ]),
      );
      folder.reset();
      await store!.refresh();
      expect(folder.offsets, [checkpoint]);
      expect(folder.fullBytes, 0);
      expect(folder.suffixBytes, tail.length);
      expect(title(), 'Latest');
      await expectLater(store!.verifyHistory(), throwsA(isA<FormatFailure>()));
    },
  );

  test(
    'partial remote tail advances only complete records, then admits completed tail exactly once',
    () async {
      await seed();
      await open();
      final checkpoint = offset();
      final tail = record('task.edited', {'title': 'Completed tail'});
      final split = tail.length ~/ 2;
      await folder.inner.append(
        '$remote.jsonl',
        Uint8List.sublistView(tail, 0, split),
      );
      folder.reset();
      expect(await store!.refresh(), isFalse);
      expect(offset(), checkpoint);
      expect(store!.db.select('SELECT * FROM stream_ranges'), isEmpty);
      await folder.inner.append(
        '$remote.jsonl',
        Uint8List.sublistView(tail, split),
      );
      folder.reset();
      expect(await store!.refresh(), isTrue);
      expect(folder.offsets, [checkpoint]);
      expect(folder.suffixBytes, tail.length);
      expect(title(), 'Completed tail');
      expect(
        store!.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
        3,
      );
      folder.reset();
      expect(await store!.refresh(), isFalse);
      expect(folder.fullBytes + folder.suffixBytes, 0);
    },
  );

  test(
    'new records remain strict and a failed batch leaves ranges and offset unchanged',
    () async {
      await seed();
      await open();
      final checkpoint = offset();
      final valid = record('task.edited', {'title': 'Uncommitted'});
      final invalid =
          jsonDecode(utf8.decode(record('task.edited', {'title': 'Future'})))
              as Map<String, dynamic>;
      invalid['v'] = 99;
      await folder.inner.append(
        '$remote.jsonl',
        Uint8List.fromList([
          ...valid,
          ...utf8.encode('${jsonEncode(invalid)}\n'),
        ]),
      );
      await expectLater(store!.refresh(), throwsA(isA<FormatFailure>()));
      expect(offset(), checkpoint);
      expect(title(), 'Original');
      expect(store!.db.select('SELECT * FROM stream_ranges'), isEmpty);
      await expectLater(reopen(), throwsA(isA<FormatFailure>()));
    },
  );

  for (final invalid in [
    'space',
    'writer',
    'sequence',
    'clock',
    'blank',
    'undo reference',
    'tag reference',
    'move reference',
  ]) {
    test(
      'seeked new $invalid rejects transactionally without advancing admitted bytes',
      () async {
        await seed();
        await open();
        final checkpoint = offset();
        final event =
            jsonDecode(
                  utf8.decode(record('task.edited', {'title': 'Rejected'})),
                )
                as Map<String, dynamic>;
        switch (invalid) {
          case 'space':
            event['space'] = const Uuid().v4();
          case 'writer':
            event['writer'] = const Uuid().v4();
          case 'sequence':
            event['seq'] = sequence + 1;
          case 'clock':
            event['clock'] = '1';
          case 'undo reference':
            event['type'] = 'task.completionUndone';
            event['data'] = {'completion': '$remote:1'};
          case 'tag reference':
            event['type'] = 'task.tagsChanged';
            event['data'] = {
              'add': <String>[],
              'remove': ['$remote:1:0'],
            };
          case 'move reference':
            event['type'] = 'task.moved';
            event['data'] = {'before': user};
        }
        event['hash'] = eventRecordHash(event);
        await folder.inner.append(
          '$remote.jsonl',
          Uint8List.fromList(
            utf8.encode(
              invalid == 'blank' ? '\n' : '${canonicalEventJson(event)}\n',
            ),
          ),
        );
        folder.reset();
        await expectLater(store!.refresh(), throwsA(isA<FormatFailure>()));
        expect(folder.offsets, [checkpoint]);
        expect(folder.fullBytes, 0);
        expect(offset(), checkpoint);
        expect(store!.db.select('SELECT * FROM stream_ranges'), isEmpty);
        expect(
          store!.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
          2,
        );
        expect(title(), 'Original');
      },
    );
  }

  test('oversized remote incomplete tail fails before admission', () async {
    await seed();
    await open();
    final checkpoint = offset();
    await folder.inner.append('$remote.jsonl', Uint8List(1024 * 1024 + 1));
    await expectLater(store!.refresh(), throwsA(isA<FormatFailure>()));
    expect(offset(), checkpoint);
    expect(store!.db.select('SELECT * FROM stream_ranges'), isEmpty);
  });

  test(
    'explicit verification fails visibly when cached range coverage is incomplete',
    () async {
      await seed();
      await open();
      await folder.inner.append(
        '$remote.jsonl',
        record('task.edited', {'title': 'Admitted'}),
      );
      await store!.refresh();
      store!.db.execute('DELETE FROM stream_ranges');
      await expectLater(store!.verifyHistory(), throwsA(isA<FormatFailure>()));
    },
  );

  for (final capability in ['unknown size', 'unseekable']) {
    test(
      '$capability provider honestly full-reads and verifies every refresh',
      () async {
        await seed();
        folder.knownSize = capability != 'unknown size';
        folder.seekable = capability != 'unseekable';
        await open();
        final length = await log().length();
        folder.reset();
        expect(await store!.refresh(), isFalse);
        expect(folder.fullBytes, length);
        expect(folder.suffixBytes, 0);
        await log().writeAsString(
          (await log().readAsString()).replaceFirst('Original', 'Replaced'),
        );
        await expectLater(store!.refresh(), throwsA(isA<FormatFailure>()));
      },
    );
  }

  test(
    'cache 10 migration keeps materializations/baseline and reads no historical bytes',
    () async {
      await seed(1024 * 1024);
      await open();
      final baseline = sha256.convert(await log().readAsBytes()).toString();
      final checkpoint = offset();
      final snapshot = store!.taskSnapshot;
      // Recreate the actual v10 streams schema, not a newer schema with an old PRAGMA.
      store!.db.execute('ALTER TABLE streams RENAME TO newer_streams');
      store!.db.execute(
        'CREATE TABLE streams (name TEXT PRIMARY KEY, offset INTEGER NOT NULL, hash TEXT NOT NULL, stamp TEXT NOT NULL)',
      );
      store!.db.execute(
        'INSERT INTO streams SELECT name,offset,?,stamp FROM newer_streams',
        [baseline],
      );
      store!.db.execute('DROP TABLE newer_streams');
      store!.db.execute('DROP TABLE stream_ranges');
      store!.db.execute('PRAGMA user_version=10');
      await reopen();
      expect(folder.offsets, [checkpoint]);
      expect(folder.fullBytes + folder.suffixBytes, 0);
      expect(store!.taskSnapshot, snapshot);
      final row = store!.db.select('SELECT * FROM streams').single;
      expect(row['hash'], baseline);
      expect(row['hash_offset'], checkpoint);
      expect(
        store!.db.select('PRAGMA user_version').single['user_version'],
        12,
      );
      await log().writeAsString(
        (await log().readAsString()).replaceFirst('Original', 'Replaced'),
      );
      await expectLater(store!.verifyHistory(), throwsA(isA<FormatFailure>()));
    },
  );

  test(
    'obsolete-cache replay preserves baseline guards through failed migration and retry',
    () async {
      await seed();
      await open();
      await folder.inner.append(
        '$remote.jsonl',
        record('task.edited', {'title': 'Admitted'}),
      );
      await store!.refresh();
      final original = await log().readAsBytes();
      store!.db.execute('PRAGMA user_version=9');
      await store!.close();
      store = null;
      await log().writeAsString(
        utf8.decode(original).replaceFirst('Admitted', 'Replaced'),
      );
      await expectLater(open(), throwsA(isA<FormatFailure>()));
      await log().writeAsBytes(original);
      await open();
      expect(title(), 'Admitted');
      expect(store!.db.select('SELECT * FROM stream_ranges'), isEmpty);
      expect(await log().readAsBytes(), original);
      expect(
        await Directory(
          cache,
        ).list().where((f) => f.path.contains('cache-v9-')).length,
        1,
      );
    },
  );

  test(
    'owned incomplete append is visible after cold reopen and cannot confirm receipt',
    () async {
      await seed();
      await open();
      await store!.command(task, 'task.edited', {'title': 'Owned'});
      final receipt = <OperationReceipt>[];
      folder.afterAppend = (name, bytes) async {
        final file = folder.inner.file(name);
        final all = await file.readAsBytes();
        await file.writeAsBytes(all.sublist(0, all.length - 1));
      };
      await expectLater(
        store!.command(task, 'task.edited', {
          'title': 'Incomplete',
        }, onPrepared: receipt.add),
        throwsA(isA<FormatFailure>()),
      );
      expect(store!.confirmedOperations(receipt), isEmpty);
      await expectLater(reopen(), throwsA(isA<FormatFailure>()));
    },
  );

  test(
    'new raw receipt cannot confirm a transport rewrite with equivalent JSON meaning',
    () async {
      await seed();
      await open();
      await store!.command(task, 'task.edited', {'title': 'Owned'});
      final receipt = <OperationReceipt>[];
      folder.afterAppend = (name, bytes) async {
        folder.afterAppend = null;
        final file = folder.inner.file(name);
        final all = await file.readAsBytes();
        await file.writeAsBytes([
          ...all.sublist(0, all.length - bytes.length),
          ...utf8.encode(' ${utf8.decode(bytes).trim()} \n'),
        ]);
      };
      await expectLater(
        store!.command(task, 'task.edited', {
          'title': 'Intended',
        }, onPrepared: receipt.add),
        throwsA(isA<HistoryVerificationFailure>()),
      );
      expect(title(), 'Owned');
      expect(store!.confirmedOperations(receipt), isEmpty);
      expect(
        store!.db.select('SELECT raw FROM events WHERE id=?', [
          receipt.single.id,
        ]),
        isEmpty,
      );
    },
  );

  test(
    'seeked command receipts reject changed new raw bytes and durable retry is idempotent',
    () async {
      await seed();
      await open();
      await store!.command(task, 'task.edited', {'title': 'Owned'});
      final receipt = <OperationReceipt>[];
      folder.afterAppend = (name, bytes) async {
        folder.afterAppend = null;
        final file = folder.inner.file(name);
        final all = await file.readAsBytes();
        final changed = utf8.decode(bytes).replaceFirst('Intended', 'Replaced');
        final temp = folder.inner.file('owned-replacement.tmp');
        await temp.writeAsBytes([
          ...all.sublist(0, all.length - bytes.length),
          ...utf8.encode(changed),
        ]);
        await temp.rename(file.path);
      };
      await expectLater(
        store!.command(task, 'task.edited', {
          'title': 'Intended',
        }, onPrepared: receipt.add),
        throwsA(isA<HistoryVerificationFailure>()),
      );
      expect(store!.confirmedOperations(receipt), isEmpty);
      expect(title(), 'Owned');
      // Recovery restores the exact submitted bytes; no automatic repair occurs.
      final owned = folder.inner.file('$owner.jsonl');
      final previous = await owned.readAsBytes();
      final checkpoint =
          store!.db.select('SELECT offset FROM streams WHERE name=?', [
                '$owner.jsonl',
              ]).single['offset']
              as int;
      await owned.writeAsBytes([
        ...previous.sublist(0, checkpoint),
        ...utf8.encode('${receipt.single.raw}\n'),
      ]);
      await store!.refresh();
      expect(title(), 'Intended');
      final created = const Uuid().v4();
      expect(
        (await store!.createTasks({created: 'Capture'}, user)).succeeded,
        isTrue,
      );
      final count = store!.db
          .select('SELECT COUNT(*) AS n FROM events')
          .single['n'];
      await reopen();
      expect(
        (await store!.createTasks({created: 'Capture'}, user)).committedIds,
        [created],
      );
      expect(
        store!.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
        count,
      );
      expect(folder.fullBytes + folder.suffixBytes, 0);
    },
  );

  for (final defect in ['selfhash', 'previousHash']) {
    test(
      'new suffix $defect has exact diagnostic and never advances cache',
      () async {
        await seed();
        await open();
        final checkpoint = offset();
        final event =
            jsonDecode(
                  utf8.decode(record('task.edited', {'title': 'Rejected'})),
                )
                as Map<String, dynamic>;
        if (defect == 'selfhash') {
          event['data']['title'] = 'Changed';
        } else {
          event['previousHash'] = '0' * 64;
          event['hash'] = eventRecordHash(event);
        }
        final invalid = Uint8List.fromList(
          utf8.encode('${canonicalEventJson(event)}\n'),
        );
        await folder.inner.append('$remote.jsonl', invalid);
        await expectLater(
          store!.refresh(),
          throwsA(
            isA<HistoryVerificationFailure>()
                .having((f) => f.fileName, 'file', '$remote.jsonl')
                .having((f) => f.recordNumber, 'record', 3)
                .having((f) => f.byteOffset, 'offset', checkpoint)
                .having(
                  (f) => f.reason,
                  'reason',
                  contains(
                    defect == 'selfhash'
                        ? 'hash mismatch'
                        : 'Previous record hash',
                  ),
                ),
          ),
        );
        expect(offset(), checkpoint);
        expect(title(), 'Original');
        expect(
          store!.db
              .select('SELECT chain_head,last_seq FROM streams')
              .single['last_seq'],
          2,
        );
        expect((await log().readAsBytes()).sublist(checkpoint), invalid);
      },
    );
  }

  test(
    'fresh replay checks genesis even when every selfhash is valid',
    () async {
      final event = LogEvent(
        space,
        remote,
        1,
        EventClock(BigInt.one),
        user,
        'user.created',
        {'name': 'Lee'},
      );
      final wrong = event.encode(previousHash: '0' * 64);
      expect(LogEvent.decode(wrong).hash, isNotNull);
      await folder.create(
        '$remote.jsonl',
        Uint8List.fromList(utf8.encode('$wrong\n')),
      );
      await expectLater(
        open(),
        throwsA(
          isA<HistoryVerificationFailure>()
              .having((f) => f.recordNumber, 'record', 1)
              .having((f) => f.byteOffset, 'offset', 0)
              .having(
                (f) => f.reason,
                'reason',
                contains('Previous record hash'),
              ),
        ),
      );
    },
  );

  test(
    'full verification reports exact changed record with UTF8 byte offset',
    () async {
      await seed();
      await open();
      final original = await log().readAsBytes();
      final secondRecord = original.indexOf(10) + 1;
      await replace(
        Uint8List.fromList(
          utf8.encode(
            utf8.decode(original).replaceFirst('Original', 'Replaced'),
          ),
        ),
      );
      await expectLater(
        store!.verifyHistory(),
        throwsA(
          isA<HistoryVerificationFailure>()
              .having((f) => f.fileName, 'file', '$remote.jsonl')
              .having((f) => f.recordNumber, 'record', 2)
              .having((f) => f.byteOffset, 'offset', secondRecord),
        ),
      );
      expect(store!.lastHistoryVerification, isNull);
      expect(title(), 'Original');
    },
  );

  test(
    'successful full verification counts records and bytes without appending an event',
    () async {
      await seed();
      await open();
      final bytes = await log().readAsBytes();
      expect(await store!.verifyHistory(), isFalse);
      final report = store!.lastHistoryVerification!;
      expect(report.checkedLogCount, 1);
      expect(report.checkedRecordCount, 2);
      expect(report.checkedByteCount, bytes.length);
      expect(report.importedEventCount, 0);
      expect(await log().readAsBytes(), bytes);
      final tail = record('task.edited', {'title': 'Verified growth'});
      await folder.inner.append('$remote.jsonl', tail);
      expect(await store!.verifyHistory(), isTrue);
      expect(store!.lastHistoryVerification!.checkedRecordCount, 3);
      expect(store!.lastHistoryVerification!.importedEventCount, 1);
      expect(
        store!.db
            .select('SELECT chain_head,last_seq FROM streams')
            .single['chain_head'],
        chainHead,
      );
    },
  );

  test(
    'retained baseline detects recomputed chain while a fresh cache cannot authenticate it',
    () async {
      await seed();
      await open();
      final prior = (await log().readAsString())
          .trim()
          .split('\n')
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      prior[1]['data']['title'] = 'Replaced';
      var head = eventGenesisHash(space, remote);
      final changed = <String>[];
      for (final event in prior) {
        event['previousHash'] = head;
        event['hash'] = eventRecordHash(event);
        head = event['hash'] as String;
        changed.add(canonicalEventJson(event));
      }
      await replace(Uint8List.fromList(utf8.encode('${changed.join('\n')}\n')));
      await expectLater(
        store!.verifyHistory(),
        throwsA(isA<HistoryVerificationFailure>()),
      );
      final fresh = await TaskStore.open(
        folder,
        '${root.path}/fresh',
        writerIdentity: const Uuid().v4(),
      );
      try {
        expect(
          fresh.rows.firstWhere((r) => r['id'] == task)['title'],
          'Replaced',
        );
      } finally {
        await fresh.close();
      }
    },
  );

  test(
    'known final-record removal fails verification while fresh valid prefix remains admissible',
    () async {
      await seed();
      final tail = record('task.edited', {'title': 'Removed'});
      await folder.inner.append('$remote.jsonl', tail);
      await open();
      final all = await log().readAsBytes();
      final prefix = Uint8List.fromList(
        all.sublist(0, all.length - tail.length),
      );
      await replace(prefix);
      await expectLater(
        store!.verifyHistory(),
        throwsA(
          isA<HistoryVerificationFailure>()
              .having((f) => f.recordNumber, 'removed record', 3)
              .having((f) => f.byteOffset, 'offset', prefix.length),
        ),
      );
      final fresh = await TaskStore.open(
        folder,
        '${root.path}/fresh',
        writerIdentity: const Uuid().v4(),
      );
      try {
        expect(
          fresh.rows.firstWhere((r) => r['id'] == task)['title'],
          'Original',
        );
      } finally {
        await fresh.close();
      }
    },
  );

  test(
    'old v2 canonical history and cache are retained without migration',
    () async {
      await seed();
      await open();
      store!.db.execute('PRAGMA user_version=11');
      await store!.close();
      store = null;
      final cacheFile = File('$cache/cache.sqlite');
      final cacheBefore = await cacheFile.readAsBytes();
      final manifest = Uint8List.fromList(
        utf8.encode(jsonEncode({'v': 2, 'id': space})),
      );
      await folder.inner.file('tandemlog-space.json').writeAsBytes(manifest);
      final oldFixture = await File(
        'test/fixtures/recurring_operation_undone_v2.jsonl',
      ).readAsBytes();
      await log().writeAsBytes(oldFixture);
      await expectLater(
        open(),
        throwsA(
          isA<FormatFailure>().having(
            (f) => f.message,
            'old protocol',
            contains('older prerelease format (v2)'),
          ),
        ),
      );
      expect(await cacheFile.readAsBytes(), cacheBefore);
      expect(await log().readAsBytes(), oldFixture);
      expect(
        await folder.inner.file('tandemlog-space.json').readAsBytes(),
        manifest,
      );
    },
  );

  for (final field in ['chain_head', 'last_seq', 'last_clock']) {
    test(
      'full verification retains and rejects inconsistent cached $field',
      () async {
        await seed();
        await open();
        final canonical = await log().readAsBytes();
        final replacement = field == 'chain_head' ? '0' * 64 : 99;
        store!.db.execute('UPDATE streams SET $field=? WHERE name=?', [
          replacement,
          '$remote.jsonl',
        ]);
        await expectLater(
          store!.verifyHistory(),
          throwsA(
            isA<HistoryVerificationFailure>().having(
              (f) => f.reason,
              'checkpoint',
              contains('Cached chain checkpoint is inconsistent'),
            ),
          ),
        );
        expect(
          store!.db.select('SELECT $field FROM streams').single[field],
          replacement,
        );
        expect(await log().readAsBytes(), canonical);
        expect(store!.lastHistoryVerification, isNull);
      },
    );
  }

  test(
    'oversized partial suffix identifies exact absolute record and offset',
    () async {
      await seed();
      await open();
      final checkpoint = offset();
      final complete = record('task.edited', {'title': 'Uncommitted'});
      await folder.inner.append(
        '$remote.jsonl',
        Uint8List.fromList([...complete, ...Uint8List(1024 * 1024 + 1)]),
      );
      await expectLater(
        store!.refresh(),
        throwsA(
          isA<HistoryVerificationFailure>()
              .having((f) => f.recordNumber, 'record', 4)
              .having(
                (f) => f.byteOffset,
                'offset',
                checkpoint + complete.length,
              ),
        ),
      );
      expect(offset(), checkpoint);
      expect(title(), 'Original');
    },
  );

  test(
    'semantic failure identifies invalid move before later unrelated event',
    () async {
      await seed();
      await open();
      final checkpoint = offset();
      final invalid = record('task.moved', {'before': user});
      final later = record('task.edited', {'title': 'Later'});
      await folder.inner.append(
        '$remote.jsonl',
        Uint8List.fromList([...invalid, ...later]),
      );
      await expectLater(
        store!.refresh(),
        throwsA(
          isA<HistoryVerificationFailure>()
              .having((f) => f.recordNumber, 'record', 3)
              .having((f) => f.byteOffset, 'offset', checkpoint)
              .having(
                (f) => f.reason,
                'reason',
                contains('Task order anchor is not a task'),
              ),
        ),
      );
      expect(offset(), checkpoint);
      expect(title(), 'Original');
    },
  );
}
