import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_record.dart';

const writer = '22222222-2222-4222-8222-222222222222';
const person = '33333333-3333-4333-8333-333333333333';
const container = '44444444-4444-4444-8444-444444444444';
const task = '55555555-5555-4555-8555-555555555555';

class FaultFolder extends LocalLogFolder {
  FaultFolder(super.location);
  int? cut;
  bool failBeforeCreate = false;
  @override
  Future<void> create(String name, Uint8List bytes) async {
    if (!name.endsWith('.applog')) return super.create(name, bytes);
    if (failBeforeCreate) {
      failBeforeCreate = false;
      throw const FileSystemException('Synthetic before first creation');
    }
    final n = cut;
    cut = null;
    if (n == null) return super.create(name, bytes);
    await super.create(name, Uint8List.fromList(bytes.take(n).toList()));
    throw const FileSystemException('Synthetic interrupted creation');
  }

  @override
  Future<void> append(String name, Uint8List bytes) async {
    final n = cut;
    cut = null;
    if (n == null) return super.append(name, bytes);
    await super.append(name, Uint8List.fromList(bytes.take(n).toList()));
    throw const FileSystemException('Synthetic interrupted append');
  }
}

Future<LocalProfileDatabase> profileAt(String root) async {
  final p = await LocalProfileDatabase.open(root);
  if (p.database.select('SELECT 1 FROM protected_settings').isEmpty) {
    p.transaction(
      () =>
          p.database.execute('INSERT INTO protected_settings VALUES (1,?,?)', [
            writer,
            utf8.encode(jsonEncode({'writer': writer, 'appearance': 'system'})),
          ]),
    );
  }
  return p;
}

void main() {
  late Directory root;
  late FaultFolder folder;
  late LocalProfileDatabase p;
  late UnifiedHistory h;
  TaskStore? tasks;
  FoodStore? food;
  UnifiedEffectBuilder user() =>
      (seq, clock, head) => UnifiedEffect(
        'task',
        LogEvent(h.manifest.space, writer, seq, clock, person, 'user.created', {
          'name': 'Synthetic',
        }).encode(previousHash: head),
      );
  UnifiedEffectBuilder beans() =>
      (seq, clock, head) => UnifiedEffect(
        'food',
        FoodRecord(
          space: h.manifest.space,
          writer: writer,
          sequence: seq,
          clock: clock,
          previousHash: head,
          operation: FoodOperation(
            id: '$writer:$seq',
            order: clock.value.toInt(),
            action: FoodAction.add,
            targets: [container],
            details: const FoodDetails(name: 'Beans'),
            contents: const Contents.fraction(1, 1),
            createdAt: '2026-10-20T00:00:00Z',
          ),
        ).encode(),
      );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-current-only-');
    folder = FaultFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    p = await profileAt('${root.path}/profile');
    h = await UnifiedHistory.create(folder, profile: p, writer: writer);
  });
  tearDown(() async {
    await food?.close();
    food = null;
    await tasks?.close();
    tasks = null;
    await h.close();
    await p.close();
    await root.delete(recursive: true);
  });
  test(
    'fresh workspace uses only one common writer file for both projections',
    () async {
      tasks = await TaskStore.openUnified(h);
      food = await FoodStore.openUnified(h);
      await h.appendAtomic([user(), beans()]);
      expect(tasks!.rows.single['name'], 'Synthetic');
      expect(food!.state.active.single.details.name, 'Beans');
      expect(h.snapshot.records.map((r) => r.sequence), [1]);
      expect(h.snapshot.records.single.effects.map((e) => e.sequence), [1, 2]);
      expect((await folder.list()).map((f) => f.name).toSet(), {
        'tandemlog-space.json',
        unifiedLogName(writer),
      });
      expect(h.hasPending, isFalse);
    },
  );
  for (final bad in <String, List<int>>{
    'unknown version': utf8.encode('{"v":99}\n'),
    'invalid UTF-8': [0xff, 10],
    'malformed complete JSON': utf8.encode('{broken}\n'),
  }.entries) {
    test(
      'corrupt ${bad.key} reports physical record and UTF-8 byte offset',
      () async {
        await h.appendAtomic([
          (sequence, clock, head) => UnifiedEffect(
            'task',
            LogEvent(
              h.manifest.space,
              writer,
              sequence,
              clock,
              person,
              'user.created',
              {'name': 'Synthetic café ☕'},
            ).encode(previousHash: head),
          ),
        ]);
        final name = unifiedLogName(writer);
        final before = await folder.read(name);
        expect(before.length, greaterThan(utf8.decode(before).length));
        final record = before.where((byte) => byte == 10).length + 1;
        await folder.append(name, Uint8List.fromList(bad.value));
        final damaged = await folder.read(name);
        await expectLater(
          h.refresh(),
          throwsA(
            isA<HistoryVerificationFailure>()
                .having((e) => e.fileName, 'filename', name)
                .having((e) => e.recordNumber, 'physical record', record)
                .having((e) => e.byteOffset, 'UTF-8 offset', before.length),
          ),
        );
        expect(await folder.read(name), damaged);
        expect(h.snapshot.tasks.single.data['name'], 'Synthetic café ☕');
      },
    );
  }
  test(
    'unfinished multibyte tail waits without corruption or mutation',
    () async {
      await h.appendAtomic([user()]);
      final name = unifiedLogName(writer);
      final prefix = await folder.read(name);
      await folder.append(name, Uint8List.fromList([0xf0, 0x9f]));
      final partial = await folder.read(name);
      await h.refresh();
      expect(h.snapshot.tasks.single.entity, person);
      expect(h.snapshot.incomplete, isTrue);
      expect(await folder.read(name), partial);
      expect(partial.take(prefix.length), prefix);
    },
  );
  for (final cut in [0, 1, 1500, 1000000]) {
    test(
      'restart cut=$cut admits complete actions only and never replays intent',
      () async {
        folder.cut = cut;
        await expectLater(
          h.appendAtomic([user(), beans()]),
          throwsA(isA<FileSystemException>()),
        );
        final interrupted = await folder.read(unifiedLogName(writer));
        final complete = interrupted.isNotEmpty && interrupted.last == 10;
        await h.close();
        await p.close();
        p = await profileAt('${root.path}/profile');
        h = await UnifiedHistory.open(folder, profile: p, writer: writer);
        expect(h.hasPending, isFalse);
        await h.recoverPrepared();
        await h.recoverPrepared();
        expect(await folder.read(unifiedLogName(writer)), interrupted);
        if (!complete) {
          expect(h.snapshot.effects, isEmpty);
          await h.appendAtomic([user(), beans()]);
        }
        expect(h.snapshot.records, hasLength(1));
        expect(h.snapshot.tasks.single.entity, person);
        expect(h.snapshot.food.single.targets, [container]);
        expect(h.snapshot.records.single.effects, hasLength(2));
      },
    );
  }
  test(
    'failure before first creation does not cause a restart write',
    () async {
      folder.failBeforeCreate = true;
      await expectLater(
        h.appendAtomic([user(), beans()]),
        throwsA(isA<FileSystemException>()),
      );
      await h.close();
      await p.close();
      p = await profileAt('${root.path}/profile');
      h = await UnifiedHistory.open(folder, profile: p, writer: writer);
      expect(h.hasPending, isFalse);
      await h.recoverPrepared();
      expect(h.snapshot.records, isEmpty);
      expect(
        await File('${folder.location}/${unifiedLogName(writer)}').exists(),
        isFalse,
      );
      await h.appendAtomic([user(), beans()]);
      expect(h.snapshot.records, hasLength(1));
    },
  );
  test(
    'first persisted alias revises the operation without a manifest write',
    () async {
      final before = await folder.read('tandemlog-space.json');
      await h.appendAtomic([user()]);
      await h.appendAtomic([
        (seq, clock, head) => UnifiedEffect(
          'task',
          LogEvent(h.manifest.space, writer, seq, clock, task, 'task.created', {
            'title': 'Alias task',
            'description': '',
            'assignee': person,
            'schedule': TaskSchedule(
              dueDate: '2026-11-02',
              dueTime: '09:00',
              timeZone: 'CST6CDT',
            ).toJson(),
            'tags': <String>[],
          }).encode(previousHash: head),
        ),
      ]);
      final saved = jsonDecode(h.snapshot.records.last.effect.raw) as Map;
      expect(saved['operation'], {'family': 'task.create', 'revision': 2});
      expect(await folder.read('tandemlog-space.json'), before);
    },
  );
  for (final unknownFamily in ['food', 'completion']) {
    test(
      'unknown $unknownFamily revision blocks warm writes in both modules and cold admission',
      () async {
        tasks = await TaskStore.openUnified(h);
        food = await FoodStore.openUnified(h);
        await h.appendAtomic([user()]);
        final old = h.snapshot.revision;
        final r = await h.validateInProfileQueue([
          (seq, clock, head) => UnifiedEffect(
            'task',
            LogEvent(
              h.manifest.space,
              writer,
              seq,
              clock,
              task,
              'task.created',
              {
                'title': 'Must stay invisible',
                'description': '',
                'assignee': person,
              },
            ).encode(previousHash: head),
          ),
          if (unknownFamily == 'completion')
            (seq, clock, head) => UnifiedEffect(
              'task',
              LogEvent(
                h.manifest.space,
                writer,
                seq,
                clock,
                task,
                'task.completed',
                {'completedInstant': '2026-10-26T12:00:00.123456Z'},
              ).encode(previousHash: head),
            ),
          beans(),
        ]);
        final j = jsonDecode(r.records.single.encode()) as Map<String, dynamic>;
        final op =
            jsonDecode(((j['effects'] as List)[1] as Map)['raw'])
                as Map<String, dynamic>;
        (op['operation'] as Map)['revision'] = 99;
        final body = Map<String, dynamic>.of(op)
          ..remove('contentHash')
          ..remove('referenceHash');
        op['contentHash'] = sha256
            .convert(
              utf8.encode('tandemlog:operation:v1\n${canonicalDataJson(body)}'),
            )
            .toString();
        op['referenceHash'] = op['contentHash'];
        ((j['effects'] as List)[1] as Map)['raw'] = canonicalDataJson(op);
        j.remove('hash');
        j['hash'] = sha256
            .convert(
              utf8.encode('tandemlog:app-action:v5\n${canonicalDataJson(j)}'),
            )
            .toString();
        await folder.append(
          unifiedLogName(writer),
          Uint8List.fromList(utf8.encode('${canonicalDataJson(j)}\n')),
        );
        await expectLater(food!.refresh(), throwsA(isA<FormatFailure>()));
        expect(h.snapshot.revision, old);
        await expectLater(
          tasks!.command(person, 'user.created', {'name': 'Blocked'}),
          throwsA(isA<FormatFailure>()),
        );
        await expectLater(
          food!.add(const FoodDetails(name: 'Blocked'), 1),
          throwsA(isA<FormatFailure>()),
        );
        expect(
          p.database.select(
            "SELECT name FROM sqlite_schema WHERE type='table' AND name='protected_app_outbox'",
          ),
          isEmpty,
        );
        expect(tasks!.hasEntity(task), isFalse);
        expect(food!.state.containers, isEmpty);
        final cold = await profileAt('${root.path}/cold');
        try {
          await expectLater(
            UnifiedHistory.open(folder, profile: cold, writer: writer),
            throwsA(isA<FormatFailure>()),
          );
          expect(
            cold.database.select('SELECT * FROM protected_app_heads'),
            isEmpty,
          );
        } finally {
          await cold.close();
        }
      },
    );
  }
  test(
    'unsupported existing folder is rejected without initialization',
    () async {
      final old = LocalLogFolder(
        (await Directory('${root.path}/old').create()).path,
      );
      final raw = utf8.encode(
        '{"v":3,"id":"66666666-6666-4666-8666-666666666666"}',
      );
      await old.create('tandemlog-space.json', Uint8List.fromList(raw));
      await expectLater(
        UnifiedHistory.create(old, profile: p, writer: writer),
        throwsA(isA<FormatFailure>()),
      );
      await expectLater(
        UnifiedHistory.open(old, profile: p, writer: writer),
        throwsA(isA<FormatFailure>()),
      );
      expect(await old.read('tandemlog-space.json'), raw);
      expect((await old.list()).length, 1);
    },
  );
}
