// Approved offline-native creation acceptance. Written before implementation.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import '../../editor_lab/lib/native_bridge.dart';
import '../lib/activation.dart';

const space = '11111111-1111-4111-8111-111111111111';
const a = '22222222-2222-4222-8222-222222222222';
const b = '33333333-3333-4333-8333-333333333333';
const user = '44444444-4444-4444-8444-444444444444';
const taskA = '55555555-5555-4555-8555-555555555555';
const taskB = '66666666-6666-4666-8666-666666666666';
const oldTask = '77777777-7777-4777-8777-777777777777';
final labs = <ActivationLab>[];

class CreationChain {
  final heads = <String, String>{};
  final sequences = <String, int>{};
  String emit(
    String writer,
    String entity,
    String type,
    Map<String, dynamic> data,
  ) {
    final seq = (sequences[writer] ?? 0) + 1;
    final raw = LogEvent(
      space,
      writer,
      seq,
      EventClock(BigInt.from(100 + seq)),
      entity,
      type,
      data,
    ).encode(previousHash: heads[writer] ?? eventGenesisHash(space, writer));
    sequences[writer] = seq;
    heads[writer] = (jsonDecode(raw) as Map)['hash'] as String;
    return raw;
  }

  String create(String writer, String entity, String title, String notes) {
    String seedHash(String text) {
      final seed =
          NativeBridge().call('seed', {'text': text})['update'] as String;
      return sha256.convert(base64Decode(seed)).toString();
    }

    return emit(writer, entity, 'task.createdWithText', {
      'title': title,
      'description': notes,
      'assignee': user,
      'text': {
        'codec': 'yrs-v1',
        'adapter': 1,
        'seeds': {'title': seedHash(title), 'description': seedHash(notes)},
      },
    });
  }

  String sharedUser() =>
      emit(a, user, 'user.created', {'name': 'Synthetic user'});
}

ActivationLab replica(String name, String writer, {Directory? directory}) {
  final lab = ActivationLab(
    name: name,
    writer: writer,
    config: null,
    directory: directory,
    nowNs: () => BigInt.from(1000),
  );
  labs.add(lab);
  return lab;
}

String edit(
  ActivationLab lab,
  String entity,
  String field,
  String value,
  String batch,
) {
  final draft = lab.begin(entity, field, batch: batch);
  draft.change(DraftValue(value));
  return lab.save(draft);
}

void main() {
  setUp(() => NativeBridge().call('reset'));
  tearDown(() {
    for (final lab in labs) {
      lab.close();
    }
    labs.clear();
  });

  test(
    'N01 new native title and notes edit offline without legacy baseline',
    () {
      final c = CreationChain();
      final r = replica('one', a)
        ..ingestAll([c.sharedUser(), c.create(a, taskA, 'Buy oats', 'Notes')]);
      expect(
        r.isActive,
        isFalse,
        reason: 'No legacy migration marker was received',
      );
      edit(r, taskA, 'title', 'Buy oats and fruit', 'a-title');
      edit(r, taskA, 'description', 'Notes\nsecond line 🧭', 'a-notes');
      expect(r.text(taskA, 'title'), 'Buy oats and fruit');
      expect(r.text(taskA, 'description'), 'Notes\nsecond line 🧭');
      expect(r.records.any((raw) => raw.contains('lab.activation')), isFalse);
    },
  );

  test(
    'N02 independent offline creations later exchange edits without a migration gate',
    () {
      final c = CreationChain();
      final shared = c.sharedUser();
      final ca = c.create(a, taskA, 'Task A', 'Note A');
      final cb = c.create(b, taskB, 'Task B', 'Note B');
      final x = replica('x', a)..ingestAll([shared, ca]);
      final y = replica('y', b)..ingestAll([shared, cb]);
      final ua = edit(x, taskA, 'title', 'Task A offline', 'a-offline');
      final ub = edit(y, taskB, 'description', 'Note B offline', 'b-offline');
      x.ingestAll([cb, ub]);
      y.ingestAll([ca, ua]);
      expect(x.context(taskA, 'title'), y.context(taskA, 'title'));
      expect(x.context(taskB, 'description'), y.context(taskB, 'description'));
      final pa = edit(y, taskA, 'title', 'Shared Task A offline', 'b-later');
      final pb = edit(
        x,
        taskB,
        'description',
        'Note B offline\nlater',
        'a-later',
      );
      x.ingest(pa);
      y.ingest(pb);
      for (final r in [x, y]) {
        expect(r.text(taskA, 'title'), 'Shared Task A offline');
        expect(r.text(taskB, 'description'), 'Note B offline\nlater');
        expect(r.records.length, 7);
      }
    },
  );

  test(
    'N03 creation identities remain distinct for identical values and fields',
    () {
      final c = CreationChain();
      final r = replica('identities', a)
        ..ingestAll([
          c.sharedUser(),
          c.create(a, taskA, 'Same', 'Same'),
          c.create(a, taskB, 'Same', 'Same'),
        ]);
      expect({
        r.context(taskA, 'title'),
        r.context(taskA, 'description'),
        r.context(taskB, 'title'),
        r.context(taskB, 'description'),
      }, hasLength(4));
      edit(r, taskA, 'title', 'Changed', 'one-field');
      expect(r.text(taskA, 'description'), 'Same');
      expect(r.text(taskB, 'title'), 'Same');
    },
  );

  test('N04 a pending legacy migration does not gate a newly created task', () {
    final c = CreationChain();
    final r = replica('mixed', a)
      ..ingestAll([
        c.sharedUser(),
        c.emit(a, oldTask, 'task.created', {
          'title': 'Legacy',
          'description': '',
          'assignee': user,
        }),
        c.create(a, taskA, 'Native', ''),
      ]);
    expect(() => r.begin(oldTask, 'title', batch: 'legacy'), throwsStateError);
    edit(r, taskA, 'title', 'Native offline', 'native');
    expect(r.text(taskA, 'title'), 'Native offline');
    expect(r.text(oldTask, 'title'), 'Legacy');
  });

  test(
    'N05 native creation context and edits survive cache loss and restart',
    () {
      final dir = Directory.systemTemp.createTempSync('native-creation-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = CreationChain();
      final r = replica('before', a, directory: dir)
        ..ingestAll([c.sharedUser(), c.create(a, taskA, 'Native', 'Notes')]);
      final context = r.context(taskA, 'title');
      edit(r, taskA, 'title', 'Native persisted', 'persisted');
      r.writeCache();
      r.close();
      final cache = File('${dir.path}/cache.json');
      cache.deleteSync();
      final raw = File('${dir.path}/records.jsonl').readAsBytesSync();
      final restored = replica('after', a, directory: dir);
      expect(restored.context(taskA, 'title'), context);
      expect(restored.text(taskA, 'title'), 'Native persisted');
      expect(File('${dir.path}/records.jsonl').readAsBytesSync(), raw);
    },
  );

  test(
    'N06 updates arriving before native creation remain pending and converge',
    () {
      final c = CreationChain();
      final shared = c.sharedUser();
      final created = c.create(a, taskA, 'Native', 'Notes');
      final x = replica('sender', a)..ingestAll([shared, created]);
      final update = edit(
        x,
        taskA,
        'description',
        'Notes from offline',
        'delayed',
      );
      final y = replica('receiver', b)..ingestAll([update, shared]);
      expect(
        () => y.begin(taskA, 'title', batch: 'too-soon'),
        throwsStateError,
      );
      y.ingest(created);
      expect(y.text(taskA, 'description'), 'Notes from offline');
      expect(y.records, contains(update));
    },
  );

  test(
    'N07 seed mismatch is preserved and blocks instead of creating another basis',
    () {
      final c = CreationChain();
      final shared = c.sharedUser();
      final valid =
          jsonDecode(c.create(a, taskA, 'Native', 'Notes'))
              as Map<String, dynamic>;
      final data =
          jsonDecode(jsonEncode(valid['data'])) as Map<String, dynamic>;
      ((data['text'] as Map)['seeds'] as Map)['title'] = '0' * 64;
      final invalid = LogEvent(
        space,
        a,
        2,
        EventClock(BigInt.from(102)),
        taskA,
        'task.createdWithText',
        data,
      ).encode(previousHash: valid['previousHash'] as String);
      final r = replica('invalid', b)..ingest(shared);
      expect(
        () => r.ingest(invalid),
        throwsA(
          predicate<Object>(
            (error) => error.toString().toLowerCase().contains('seed mismatch'),
            'native seed mismatch, rather than merely unknown event type',
          ),
        ),
      );
      expect(r.evidence, contains(invalid));
      expect(r.isBlocked, isTrue);
      expect(() => r.begin(taskA, 'title', batch: 'blocked'), throwsStateError);
    },
  );
}
