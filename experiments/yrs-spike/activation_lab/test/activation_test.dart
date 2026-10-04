// Synthetic acceptance tests frozen BEFORE the activation coordinator exists.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/schedule.dart' hide validateSchedule;
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import '../../editor_lab/lib/native_bridge.dart';
import '../lib/activation.dart';
import '../lib/flutter_draft.dart';

const space = '11111111-1111-4111-8111-111111111111';
const a = '22222222-2222-4222-8222-222222222222';
const b = '33333333-3333-4333-8333-333333333333';
const user = '44444444-4444-4444-8444-444444444444';
const task = '66666666-6666-4666-8666-666666666666';
const cfg = LabConfig(
  space: space,
  issuer: a,
  activationRef: 'owner-baseline-1',
);
final labs = <ActivationLab>[];

class Chain {
  final heads = <String, String>{};
  final sequences = <String, int>{};
  String emit(
    String writer,
    String entity,
    String type,
    Map<String, dynamic> data, {
    int clock = 100,
  }) {
    final sequence = (sequences[writer] ?? 0) + 1;
    final event = LogEvent(
      space,
      writer,
      sequence,
      EventClock(BigInt.from(clock)),
      entity,
      type,
      data,
    );
    final raw = event.encode(
      previousHash: heads[writer] ?? eventGenesisHash(space, writer),
    );
    sequences[writer] = sequence;
    heads[writer] = LogEvent.decode(raw).hash!;
    return raw;
  }

  List<String> base() => [
    emit(a, user, 'user.created', {'name': 'Synthetic user'}),
    emit(a, task, 'task.created', {
      'title': 'Buy oats',
      'description': 'Note',
      'assignee': user,
    }, clock: 101),
  ];
}

ActivationLab replica(
  String name,
  String writer, {
  LabConfig? config = cfg,
  Directory? directory,
}) {
  final lab = ActivationLab(
    name: name,
    writer: writer,
    config: config,
    directory: directory,
    nowNs: () => BigInt.from(1000),
  );
  labs.add(lab);
  return lab;
}

({
  ActivationLab x,
  ActivationLab y,
  Chain chain,
  List<String> base,
  String activation,
})
pair() {
  final chain = Chain();
  final base = chain.base();
  final x = replica('x', a)..ingestAll(base);
  final activation = x.activate();
  final y = replica('y', b)..ingestAll([...base, activation]);
  return (x: x, y: y, chain: chain, base: base, activation: activation);
}

String edit(
  ActivationLab lab,
  String batch,
  String text, {
  String entity = task,
  String field = 'title',
}) {
  final draft = lab.begin(entity, field, batch: batch);
  draft.change(DraftValue(text));
  return lab.save(draft);
}

Iterable<List<T>> permutations<T>(List<T> values) sync* {
  if (values.isEmpty) {
    yield [];
    return;
  }
  for (var i = 0; i < values.length; i++) {
    final rest = [...values]..removeAt(i);
    for (final suffix in permutations(rest)) {
      yield [values[i], ...suffix];
    }
  }
}

String altered(String raw, Map<String, dynamic> fields) => ActivationLab.seal(
  {...jsonDecode(raw) as Map<String, dynamic>, ...fields}..remove('checksum'),
);

void main() {
  setUp(() => NativeBridge().call('reset'));
  tearDown(() {
    for (final lab in labs) {
      lab.close();
    }
    labs.clear();
  });

  test(
    'B01 actual production frozen-v3 replay/cache reopen remains unchanged',
    () async {
      const fixture = 'test/fixtures/stable-v3-2026.10.0';
      final root = await Directory.systemTemp.createTemp('activation-v3-');
      TaskStore? store;
      try {
        final shared = await Directory('${root.path}/shared').create();
        final hashes = <String, String>{};
        for (final file in Directory(fixture).listSync().whereType<File>()) {
          if (file.path.endsWith('.jsonl') ||
              file.path.endsWith('tandemlog-space.json')) {
            final name = file.uri.pathSegments.last;
            hashes[name] = sha256.convert(file.readAsBytesSync()).toString();
            await file.copy('${shared.path}/$name');
          }
        }
        store = await TaskStore.open(
          LocalLogFolder(shared.path),
          '${root.path}/profile',
        );
        expect(
          store.rows,
          jsonDecode(File('$fixture/expected-rows.json').readAsStringSync()),
        );
        await store.verifyHistory();
        expect(store.lastHistoryVerification!.checkedRecordCount, 22);
        final writer = store.writer;
        await store.close();
        store = await TaskStore.open(
          LocalLogFolder(shared.path),
          '${root.path}/profile',
        );
        expect(store.writer, writer);
        expect(store.readFiles, 0);
        for (final entry in hashes.entries) {
          expect(
            sha256
                .convert(File('${shared.path}/${entry.key}').readAsBytesSync())
                .toString(),
            entry.value,
          );
        }
      } finally {
        await store?.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'B02 uncovered legacy values lose regardless of scalar clock; bytes retained',
    () {
      for (final clock in [99, 102, 9000000000000000000]) {
        final p = pair();
        final old = p.chain.emit(b, task, 'task.edited', {
          'title': 'LEGACY',
          'description': 'OLD NOTE',
        }, clock: clock);
        p.x.ingest(old);
        expect(p.x.text(task, 'title'), 'Buy oats');
        expect(p.x.text(task, 'description'), 'Note');
        expect(p.x.excludedTextEvents, contains('$b:1'));
        expect(p.x.evidence, contains(old));
        p.x.close();
        p.y.close();
      }
    },
  );
  test('B03 baseline/update/legacy permutations and duplicates converge', () {
    final p = pair();
    final update = edit(p.x, 'one', 'Buy oats and fruit');
    final old = p.chain.emit(b, task, 'task.edited', {
      'title': 'OLD',
    }, clock: 9000);
    for (final order in permutations([...p.base, p.activation, update, old])) {
      final r = replica('arrival', b)..ingestAll([...order, ...order]);
      expect(r.text(task, 'title'), 'Buy oats and fruit');
      expect(r.excludedTextEvents, {'$b:1'});
      expect(r.records.length, 5);
      r.close();
    }
  });
  test(
    'B04 verified prefix and original Undo determine seed; missing prefix pending',
    () {
      final c = Chain();
      final base = c.base();
      final replace = c.emit(a, task, 'task.edited', {
        'title': 'Temporary',
      }, clock: 102);
      final undo = c.emit(a, task, 'task.operationUndone', {
        'operation': '$a:3',
      }, clock: 103);
      final issuer = replica('issuer', a)..ingestAll([...base, replace, undo]);
      final activation = issuer.activate();
      expect(issuer.text(task, 'title'), 'Buy oats');
      final receiver = replica('waiting', b)
        ..ingestAll([...base, undo, activation]);
      expect(receiver.isActive, isFalse);
      expect(
        () => receiver.begin(task, 'title', batch: 'blocked'),
        throwsStateError,
      );
      receiver.ingest(replace);
      expect(receiver.text(task, 'title'), 'Buy oats');
      final corrupt = altered(activation, {'seedDigest': '0' * 64});
      final bad = replica('bad', b)..ingestAll([...base, replace, undo]);
      expect(() => bad.ingest(corrupt), throwsA(anything));
      expect(bad.isBlocked, isTrue);
      expect(bad.evidence, contains(corrupt));
    },
  );
  test(
    'B05 only text loses; valid schedule/tag/completion survive, invalid records block',
    () {
      final p = pair();
      final old = p.chain.emit(b, task, 'task.edited', {
        'title': 'OLD',
        'schedule': TaskSchedule(dueDate: '2026-10-06').toJson(),
        'tagChanges': {
          'add': ['work'],
          'remove': <String>[],
        },
      }, clock: 200);
      p.x.ingest(old);
      p.x.ingest(
        p.chain.emit(b, task, 'task.completed', {
          'completedAt': '2026-10-04',
        }, clock: 201),
      );
      expect(p.x.text(task, 'title'), 'Buy oats');
      expect((p.x.row(task)['schedule'] as Map)['dueDate'], '2026-10-06');
      expect(p.x.row(task)['tags'], ['work']);
      expect(p.x.row(task)['completed'], isTrue);
      final bad = p.chain.emit(b, task, 'task.edited', {
        'title': 'BAD',
      }, clock: 202);
      final broken = bad.replaceFirst('BAD', 'BROKEN');
      expect(() => p.x.ingest(broken), throwsA(anything));
      expect(p.x.isBlocked, isTrue);
      expect(p.x.evidence, contains(broken));
      expect(p.x.text(task, 'title'), 'Buy oats');
    },
  );
  test(
    'B06 late legacy Undo changes valid nontext meaning without touching native text',
    () {
      final p = pair();
      edit(p.x, 'new', 'Buy oats and fruit');
      p.x.ingest(
        p.chain.emit(b, task, 'task.edited', {
          'title': 'OLD',
          'schedule': TaskSchedule(dueDate: '2026-10-06').toJson(),
        }, clock: 200),
      );
      p.x.ingest(
        p.chain.emit(b, task, 'task.operationUndone', {
          'operation': '$b:1',
        }, clock: 201),
      );
      expect(p.x.text(task, 'title'), 'Buy oats and fruit');
      expect((p.x.row(task)['schedule'] as Map)['dueDate'], isNull);
    },
  );
  test(
    'B07 unrelated writer heads do not change independent field initialization',
    () {
      final p = pair();
      p.y.ingest(
        p.chain.emit(
          b,
          '55555555-5555-4555-8555-555555555555',
          'user.created',
          {'name': 'Other'},
          clock: 300,
        ),
      );
      expect(p.x.context(task, 'title'), p.y.context(task, 'title'));
      final x = edit(p.x, 'append-a', 'Buy oats A');
      final y = edit(p.y, 'append-b', 'Buy oats B');
      p.x.ingest(y);
      p.y.ingest(x);
      expect(p.x.text(task, 'title'), p.y.text(task, 'title'));
      expect(p.x.text(task, 'title'), contains(' A'));
      expect(p.x.text(task, 'title'), contains(' B'));
      expect('Buy oats'.allMatches(p.x.text(task, 'title')).length, 1);
    },
  );
  test(
    'B08 awaiting baseline never promotes an earlier private scalar draft',
    () {
      final p = pair();
      final waiting = replica('unactivated', b)..ingestAll(p.base);
      final draft = waiting.captureLegacyDraft(
        task,
        'title',
        base: 'Buy oats',
        value: const DraftValue('Private old draft'),
      );
      expect(() => waiting.save(draft), throwsStateError);
      waiting.ingest(p.activation);
      expect(draft.value.text, 'Private old draft');
      expect(() => waiting.save(draft), throwsStateError);
      expect(waiting.text(task, 'title'), 'Buy oats');
    },
  );
  test(
    'B09 authority is explicitly configured, not inferred from current writers',
    () {
      final c = Chain();
      final base = c.base();
      final missing = replica('no-authority', a, config: null)..ingestAll(base);
      expect(() => missing.activate(), throwsStateError);
      final nonissuer = replica('not-issuer', b)..ingestAll(base);
      expect(() => nonissuer.activate(), throwsStateError);
      final issuer = replica('issuer', a)..ingestAll(base);
      final good = issuer.activate();
      expect(
        () => nonissuer.ingest(altered(good, {'issuer': b})),
        throwsA(anything),
      );
      expect(nonissuer.isBlocked, isTrue);
    },
  );
  test(
    'B10 incompatible upgraded root is preserved as evidence, never a silent loser',
    () {
      final p = pair();
      final other = replica(
        'wrong-root',
        b,
        config: const LabConfig(
          space: space,
          issuer: b,
          activationRef: 'other-root',
        ),
      )..ingestAll(p.base);
      other.ingest(
        p.chain.emit(b, task, 'task.edited', {
          'title': 'Buy fruit',
        }, clock: 200),
      );
      final badRoot = other.activate();
      final genuine = edit(other, 'wrong-native', 'Buy fruit and milk');
      expect(() => p.x.ingest(badRoot), throwsA(anything));
      expect(() => p.x.ingest(genuine), throwsA(anything));
      expect(p.x.evidence, containsAll([badRoot, genuine]));
      expect(p.x.isBlocked, isTrue);
      expect(() => p.x.begin(task, 'title', batch: 'no-ack'), throwsStateError);
      expect(p.x.text(task, 'title'), 'Buy oats');
    },
  );
  test(
    'B11 acknowledged native edits and delayed parents survive duplicates/order',
    () {
      final p = pair();
      final x = edit(p.x, 'replace', 'Buy milk');
      final y = edit(p.y, 'append', 'Buy oats and fruit');
      p.x.ingest(y);
      p.y.ingest(x);
      expect(p.x.text(task, 'title'), 'Buy milk and fruit');
      expect(p.y.text(task, 'title'), 'Buy milk and fruit');
      final next = edit(p.y, 'causal-child', 'Buy milk and fruit!');
      final receiver = replica('delayed', a)
        ..ingestAll([...p.base, p.activation, next]);
      expect(receiver.fieldPending(task, 'title'), isTrue);
      receiver.ingest(y);
      receiver.ingest(x);
      receiver.ingest(next);
      expect(receiver.text(task, 'title'), 'Buy milk and fruit!');
      expect(receiver.fieldPending(task, 'title'), isFalse);
      expect(receiver.evidence, containsAll([x, y, next]));
    },
  );
  test(
    'B12 exact prepared bytes persist across interruption/restart/idempotent retry',
    () async {
      final dir = await Directory.systemTemp.createTemp('activation-journal-');
      try {
        final c = Chain();
        final r = replica('durable', a, directory: dir)..ingestAll(c.base());
        final activation = r.activate();
        final draft = r.begin(task, 'title', batch: 'durable-save');
        draft.change(const DraftValue('Buy oats and fruit'));
        final prepared = r.prepareSave(draft);
        expect(r.text(task, 'title'), 'Buy oats');
        expect(() => r.save(draft, failAfterAppend: true), throwsStateError);
        expect(draft.value.text, 'Buy oats and fruit');
        final before = File('${dir.path}/records.jsonl').readAsBytesSync();
        r.close();
        final reopened = replica('restart', a, directory: dir);
        expect(reopened.outboxRecords, contains(prepared));
        expect(reopened.text(task, 'title'), 'Buy oats and fruit');
        expect(reopened.retryPrepared(prepared), prepared);
        expect(reopened.retryPrepared(prepared), prepared);
        expect(reopened.records.where((r) => r == activation).length, 1);
        expect(reopened.records.where((r) => r == prepared).length, 1);
        expect(File('${dir.path}/records.jsonl').readAsBytesSync(), before);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'B13 full pending checkpoint and fresh-process replay preserve canonical bytes',
    () async {
      final p = pair();
      final parent = edit(p.x, 'parent', 'Buy oats1');
      p.y.ingest(parent);
      final child = edit(p.y, 'child', 'Buy oats12');
      final dir = await Directory.systemTemp.createTemp('activation-cache-');
      try {
        final r = replica('cached', a, directory: dir)
          ..ingestAll([...p.base, p.activation, child]);
        expect(r.fieldPending(task, 'title'), isTrue);
        r.writeCache();
        r.close();
        final reopened = replica('restored', a, directory: dir);
        expect(reopened.fieldPending(task, 'title'), isTrue);
        reopened.ingest(parent);
        expect(reopened.text(task, 'title'), 'Buy oats12');
        reopened.writeCache();
        reopened.close();
        final before = File('${dir.path}/records.jsonl').readAsBytesSync();
        File(
          '${dir.path}/cache.json',
        ).writeAsStringSync('{"cacheVersion":999}', flush: true);
        final rebuilt = replica('bad-cache', a, directory: dir);
        expect(rebuilt.text(task, 'title'), 'Buy oats12');
        expect(File('${dir.path}/records.jsonl').readAsBytesSync(), before);
        final dart = Platform.environment['DART_EXECUTABLE'];
        expect(
          dart,
          isNotNull,
          reason: 'Configure official SDK Dart for a real subprocess',
        );
        final proc = await Process.run(dart!, [
          '--packages=.dart_tool/package_config.json',
          'experiments/yrs-spike/activation_lab/bin/replay_probe.dart',
          dir.path,
        ]);
        expect(proc.exitCode, 0, reason: '${proc.stderr}');
        final evidence = jsonDecode(proc.stdout as String) as Map;
        expect(evidence['title'], 'Buy oats12');
        expect(evidence['canonicalSha256'], sha256.convert(before).toString());
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'B14 actual old TaskStore stops on new required event without checkpoint advance',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'activation-old-reader-',
      );
      TaskStore? store;
      try {
        final shared = await Directory('${root.path}/shared').create();
        final c = Chain();
        final base = c.base();
        File(
          '${shared.path}/tandemlog-space.json',
        ).writeAsStringSync(jsonEncode({'v': 3, 'id': space}));
        File(
          '${shared.path}/$a.jsonl',
        ).writeAsStringSync('${base.join('\n')}\n');
        store = await TaskStore.open(
          LocalLogFolder(shared.path),
          '${root.path}/profile',
        );
        final before = store.db
            .select('SELECT * FROM streams')
            .map((r) => Map<String, Object?>.from(r))
            .toList();
        final unknown = LogEvent(
          space,
          b,
          1,
          EventClock(BigInt.from(300)),
          task,
          'lab.textActivated',
          {'reference': 'owner-baseline-1'},
        ).encode();
        final bytes = utf8.encode('$unknown\n');
        File('${shared.path}/$b.jsonl').writeAsBytesSync(bytes);
        await expectLater(store.refresh(), throwsA(isA<FormatFailure>()));
        expect(
          store.db
              .select('SELECT * FROM streams')
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
          before,
        );
        expect(
          store.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
          2,
        );
        expect(File('${shared.path}/$b.jsonl').readAsBytesSync(), bytes);
      } finally {
        await store?.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'B15 same strings in different fields/entities/successor identities do not alias',
    () {
      final c = Chain();
      final base = c.base();
      const successor = '77777777-7777-4777-8777-777777777777';
      base.add(
        c.emit(a, successor, 'task.created', {
          'title': 'Buy oats',
          'description': 'Buy oats',
          'assignee': user,
        }, clock: 102),
      );
      final r = replica('fields', a)..ingestAll(base);
      r.activate();
      expect(r.context(task, 'title'), isNot(r.context(successor, 'title')));
      expect(
        r.context(successor, 'title'),
        isNot(r.context(successor, 'description')),
      );
      edit(r, 'parent-title', 'New title');
      expect(r.text(successor, 'title'), 'Buy oats');
      expect(r.text(successor, 'description'), 'Buy oats');
      final fixture = Directory('test/fixtures/stable-v3-2026.10.0');
      final recurring = replica('recurring', a);
      for (final f in fixture.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.jsonl'),
      )) {
        recurring.ingestAll(f.readAsLinesSync());
      }
      recurring.activate();
      const derived = 'dba417bc-410a-5e4f-b0ea-b1af8a767a5d';
      expect(recurring.text(derived, 'title'), isNotEmpty);
      expect(
        recurring.context(derived, 'title'),
        isNot(recurring.context(task, 'title')),
      );
    },
  );
  test('B16 losing scalar clocks remain immutable observed event metadata', () {
    final p = pair();
    final old = p.chain.emit(b, task, 'task.edited', {
      'title': 'OLD',
    }, clock: 9000000000000000000);
    p.x.ingest(old);
    expect(p.x.maximumObserved, BigInt.parse('9000000000000000000'));
    final next = edit(p.x, 'after-future', 'Buy oats!');
    expect((jsonDecode(next) as Map)['clock'], '9000000000000000001');
    expect(p.x.evidence, contains(old));
    expect(LogEvent.decode(old).clock.toJson(), '9000000000000000000');
  });
  test(
    'B17 appended native Undo compensation preserves remote and original updates',
    () {
      final p = pair();
      final original = edit(p.x, 'local', 'Buy oats milk');
      final remote = edit(p.y, 'remote', 'REMOTE Buy oats');
      p.x.ingest(remote);
      p.y.ingest(original);
      final compensation = p.x.undo(task, 'title');
      p.y.ingest(compensation);
      expect(p.x.text(task, 'title'), 'REMOTE Buy oats');
      expect(p.y.text(task, 'title'), 'REMOTE Buy oats');
      expect(p.x.records, containsAll([original, remote, compensation]));
    },
  );
  test(
    'B18 designated device proceeds without all-device stop; second uses shared basis',
    () {
      final p = pair();
      final native = edit(p.x, 'offline-native', 'Buy oats!');
      p.x.ingest(
        p.chain.emit(b, task, 'task.edited', {
          'title': 'Offline old edit',
        }, clock: 300),
      );
      expect(p.x.text(task, 'title'), 'Buy oats!');
      p.y.ingest(native);
      final second = edit(p.y, 'second', 'Buy oats!!');
      p.x.ingest(second);
      expect(p.x.text(task, 'title'), 'Buy oats!!');
    },
  );
  test(
    'B19 new text editing is gated before verified issuer/nonissuer baseline',
    () {
      final c = Chain();
      final base = c.base();
      for (final writer in [a, b]) {
        final r = replica('gated', writer)..ingestAll(base);
        expect(
          () => r.begin(task, 'title', batch: 'too-early'),
          throwsStateError,
        );
        expect(r.records, base);
      }
    },
  );
  test(
    'B20 different-base draft value/selection/composition survive incoming activation',
    () {
      final c = Chain();
      final base = c.base();
      final waiting = replica('old-draft', b)..ingestAll(base);
      final draft = waiting.captureLegacyDraft(
        task,
        'title',
        base: 'Buy oats',
        value: const DraftValue(
          'Private oats',
          selectionStart: 3,
          selectionEnd: 7,
          composingStart: 2,
          composingEnd: 8,
        ),
      );
      final controller = LabDraftController(draft);
      final before = controller.value;
      final issuer = replica('new-base', a)
        ..ingestAll([
          ...base,
          c.emit(a, task, 'task.edited', {
            'title': 'Buy fruit and milk',
          }, clock: 200),
        ]);
      waiting.ingestAll(issuer.records);
      waiting.ingest(issuer.activate());
      waiting.ingest(
        edit(issuer, 'remote-new-base', 'REMOTE Buy fruit and milk'),
      );
      expect(controller.value, before);
      expect(draft.capturedScalarBase, 'Buy oats');
      expect(() => waiting.save(draft), throwsStateError);
      expect(waiting.text(task, 'title'), 'REMOTE Buy fruit and milk');
      controller.dispose();
    },
  );
  test('B21 equal scalar string is not a native captured identity', () {
    final p = pair();
    final draft = p.y.captureLegacyDraft(
      task,
      'title',
      base: 'Buy oats',
      value: const DraftValue('Buy oats'),
    );
    expect(() => p.y.prepareSave(draft), throwsStateError);
    expect(draft.nativeContext, isNull);
    expect(draft.value.text, 'Buy oats');
  });
  test(
    'B22 explicit new controller captures native base and composing Save cannot publish',
    () {
      final p = pair();
      final old = p.x.captureLegacyDraft(
        task,
        'title',
        base: 'Old',
        value: const DraftValue('Preserved old draft'),
      );
      final draft = p.x.begin(task, 'title', batch: 'explicit-new');
      final controller = LabDraftController(draft);
      controller.value = const TextEditingValue(
        text: 'Buy oats milk',
        selection: TextSelection.collapsed(offset: 13),
        composing: TextRange(start: 9, end: 13),
      );
      expect(() => p.x.save(draft), throwsStateError);
      final remote = edit(p.y, 'remote-prefix', 'REMOTE Buy oats');
      p.x.ingest(remote);
      expect(controller.value.text, 'Buy oats milk');
      expect(controller.value.composing, const TextRange(start: 9, end: 13));
      controller.value = controller.value.copyWith(composing: TextRange.empty);
      final saved = p.x.save(draft);
      p.y.ingest(saved);
      expect(p.x.text(task, 'title'), 'REMOTE Buy oats milk');
      expect(old.value.text, 'Preserved old draft');
      final undone = p.x.undo(task, 'title');
      p.y.ingest(undone);
      expect(p.y.text(task, 'title'), 'REMOTE Buy oats');
      controller.dispose();
    },
  );
}
