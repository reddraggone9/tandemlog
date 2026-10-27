import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/current_operation.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';

const space = '00000000-0000-4000-8000-000000000001';
const writer = '00000000-0000-4000-8000-000000000002';
const entity = '00000000-0000-4000-8000-000000000003';
const author = '00000000-0000-4000-8000-000000000004';
LogEvent event(String type, Map<String, dynamic> data, {String? anchor}) =>
    LogEvent(
      space,
      writer,
      1,
      EventClock(BigInt.one),
      entity,
      type,
      data,
      previousHash: eventGenesisHash(space, writer),
      hash: anchor,
      attributedWriter: author,
    );

void main() {
  test(
    'current operation owns nested JSON before hashing and cached wire cannot be mutated through aliases',
    () {
      final input = <String, dynamic>{
        'values': {'title': 'Original'},
        'tags': {
          'add': ['one'],
          'remove': <String>[],
        },
      };
      CurrentOperation make(Map<String, dynamic> value) => CurrentOperation(
        module: 'tasks',
        space: space,
        author: author,
        writer: writer,
        sequence: 1,
        clock: '1',
        subject: entity,
        family: 'task.update',
        revision: 1,
        value: value,
        predecessor: eventGenesisHash(space, writer),
      );
      final expectedInput =
          jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
      final op = make(input);
      (input['values'] as Map)['title'] = 'Changed before first hash';
      ((input['tags'] as Map)['add'] as List).add('two');
      final expected = make(expectedInput);
      expect(op.encode(), expected.encode());
      expect(op.contentHash, expected.contentHash);
      expect(
        () => (op.value['values'] as Map)['title'] = 'Mutated',
        throwsUnsupportedError,
      );
      expect(
        () => ((op.value['tags'] as Map)['add'] as List).clear(),
        throwsUnsupportedError,
      );
      final json = op.toJson();
      json['contentHash'] = 'forged';
      (json['identity'] as Map)['writer'] = author;
      expect(op.encode(), expected.encode());
      expect(
        CurrentOperation.decode(op.encode(), module: 'tasks').encode(),
        expected.encode(),
      );
    },
  );

  test(
    'a known required revision survives decode and re-encode even without an alias',
    () {
      final base = CurrentOperation.decode(
        event('task.edited', {'title': 'Valid'}).encode(),
        module: 'tasks',
      );
      final required = CurrentOperation(
        module: base.module,
        space: base.space,
        author: base.author,
        writer: base.writer,
        sequence: base.sequence,
        clock: base.clock,
        subject: base.subject,
        family: base.family,
        revision: 2,
        value: base.value,
        predecessor: base.predecessor,
      );
      final raw = required.encode();
      expect(LogEvent.decode(raw).encode(), raw);
      expect(LogEvent.decode(raw).operationRevision, 2);
    },
  );
  test(
    'unknown producer fields cannot disappear or change action semantics during normalization',
    () {
      for (final action in [
        event('user.created', {'name': 'Synthetic', 'future': true}),
        event('task.operationUndone', {
          'operation': '$writer:1',
          'future': true,
        }),
        event('task.created', {
          'title': 'Valid',
          'description': '',
          'assignee': writer,
          'text': {
            'codec': 'yrs-v1',
            'adapter': 1,
            'seeds': {'title': 'a' * 64, 'description': 'b' * 64},
          },
        }),
        event('task.createdWithText', {
          'title': 'Valid',
          'description': '',
          'assignee': writer,
        }),
        event('task.textEdited', {
          'schedule': {'dueDate': '2026-11-02'},
        }),
      ]) {
        expect(
          () => LogEvent.decode(action.encode()),
          throwsA(isA<FormatFailure>()),
        );
      }
    },
  );
  test(
    'reserved values cannot shadow otherwise valid native contributions',
    () {
      final base = CurrentOperation.decode(
        event('task.edited', {'title': 'Valid'}).encode(),
        module: 'tasks',
      );
      final seed = {
        'codec': 'yrs-v1',
        'adapter': 1,
        'seeds': {'title': 'a' * 64, 'description': 'b' * 64},
      };
      final packet = {
        'context': 'a' * 64,
        'allocation': '88888888-8888-4888-8888-888888888888',
        'actor': 42,
        'update': base64Encode([0, 0]),
      };
      for (final value in [
        (
          'task.create',
          <String, dynamic>{
            'values': {
              'title': 'Valid',
              'description': '',
              'assignee': writer,
              'text': {'ignored': true},
            },
            'textSeed': seed,
          },
        ),
        (
          'task.update',
          <String, dynamic>{
            'values': {
              'changes': {'ignored': true},
            },
            'text': {'title': packet},
          },
        ),
      ]) {
        final op = CurrentOperation(
          module: base.module,
          space: base.space,
          author: base.author,
          writer: base.writer,
          sequence: base.sequence,
          clock: base.clock,
          subject: base.subject,
          family: value.$1,
          revision: 1,
          value: value.$2,
          predecessor: base.predecessor,
        );
        expect(
          () => LogEvent.decode(op.encode()),
          throwsA(isA<FormatFailure>()),
        );
      }
    },
  );

  test(
    'current Task family round trip keeps semantic identity and explicit author',
    () {
      final original = event('task.created', {
        'title': 'Synthetic task',
        'description': '',
        'assignee': entity,
      });
      final raw = original.encode();
      final wire = jsonDecode(raw) as Map<String, dynamic>;
      expect(wire['format'], 'tandemlog.operation');
      expect(wire.containsKey('v'), isFalse);
      expect(wire.containsKey('type'), isFalse);
      expect(wire['operation'], {'family': 'task.create', 'revision': 1});
      final decoded = LogEvent.decode(raw);
      expect(decoded.id, original.id);
      expect(decoded.author, author);
      expect(decoded.type, original.type);
      expect(decoded.data, original.data);
      expect(decoded.encode(), raw);
      expect(decoded.hash, decoded.integrityHash);
    },
  );

  test(
    'old Task and Food envelopes are not accepted by current app decoders',
    () {
      expect(
        () => LogEvent.decode('{"v":3,"type":"task.created"}'),
        throwsA(isA<FormatFailure>()),
      );
      for (final v in [1, 2, 3]) {
        expect(
          () => FoodRecord.decode('{"v":$v,"module":"food"}'),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );

  test(
    'reference anchors survive wire normalization without pretending to be current hashes',
    () {
      final anchor = List.filled(64, 'a').join();
      final original = event('task.edited', {
        'description': 'Preserved',
      }, anchor: anchor);
      final decoded = LogEvent.decode(original.encode());
      expect(decoded.hash, anchor);
      expect(decoded.integrityHash, isNot(anchor));
      expect(decoded.writer, writer);
      expect(decoded.author, author);
      expect(decoded.data, original.data);
    },
  );

  test(
    'additional timezone revision is part of the saved operation itself',
    () {
      final legacy = event('task.edited', {
        'schedule': TaskSchedule(
          dueDate: '2026-11-02',
          dueTime: '09:00',
          timeZone: 'America/Chicago',
        ).toJson(),
      });
      final additional = event('task.edited', {
        'schedule': TaskSchedule(
          dueDate: '2026-11-02',
          dueTime: '09:00',
          timeZone: 'CST6CDT',
        ).toJson(),
      });
      final a = CurrentOperation.decode(legacy.encode(), module: 'tasks');
      final b = CurrentOperation.decode(additional.encode(), module: 'tasks');
      expect(a.revision, 1);
      expect(b.revision, 2);
      expect(LogEvent.decode(additional.encode()).data, additional.data);
      final invalid = CurrentOperation(
        module: b.module,
        space: b.space,
        author: b.author,
        writer: b.writer,
        sequence: b.sequence,
        clock: b.clock,
        subject: b.subject,
        family: b.family,
        revision: 1,
        value: b.value,
        predecessor: b.predecessor,
      );
      expect(
        () => LogEvent.decode(invalid.encode()),
        throwsA(isA<FormatFailure>()),
      );
    },
  );

  test('unknown family and revision fail closed rather than skipping', () {
    final known = CurrentOperation.decode(
      event('task.deleted', {}).encode(),
      module: 'tasks',
    );
    for (final (family, revision) in [
      ('future.action', 1),
      (known.family, 99),
    ]) {
      final value = CurrentOperation(
        module: known.module,
        space: known.space,
        author: known.author,
        writer: known.writer,
        sequence: known.sequence,
        clock: known.clock,
        subject: known.subject,
        family: family,
        revision: revision,
        value: known.value,
        predecessor: known.predecessor,
      );
      expect(
        () => LogEvent.decode(value.encode()),
        throwsA(isA<FormatFailure>()),
      );
    }
  });

  test('tampering cannot retain a valid current content hash', () {
    final raw = event('task.created', {
      'title': 'Synthetic task',
      'description': '',
      'assignee': entity,
    }).encode();
    final wire = jsonDecode(raw) as Map<String, dynamic>;
    ((wire['value'] as Map)['values'] as Map)['title'] = 'Tampered';
    expect(
      () => LogEvent.decode(canonicalDataJson(wire)),
      throwsA(isA<FormatFailure>()),
    );
  });

  test(
    'normalized completion/retraction variants preserve their domain meaning',
    () {
      for (final (type, data) in <(String, Map<String, dynamic>)>[
        ('task.completed', {'completedInstant': '2026-10-20T12:00:00.000000Z'}),
        ('task.completionUndone', {'completion': '$writer:1'}),
        ('task.recurringCompletionUndone', {'completion': '$writer:1'}),
        ('task.operationUndone', {'operation': '$writer:1'}),
      ]) {
        final decoded = LogEvent.decode(event(type, data).encode());
        expect(decoded.type, type);
        expect(decoded.data, data);
      }
    },
  );

  test(
    'Food uses the same current envelope for original operations and inverses',
    () {
      final record = FoodRecord(
        space: space,
        writer: writer,
        sequence: 1,
        clock: EventClock(BigInt.one),
        previousHash: eventGenesisHash(space, writer),
        attributedWriter: author,
        operation: FoodOperation(
          id: '$writer:1',
          order: 1,
          action: FoodAction.add,
          targets: [entity],
          details: const FoodDetails(
            name: 'Synthetic rice',
            expiry: '2026-11-02',
          ),
          contents: const Contents.fraction(1, 1),
          createdAt: '2026-10-20T12:00:00Z',
        ),
      );
      final raw = record.encode();
      final decoded = FoodRecord.decode(raw);
      expect(decoded.author, author);
      expect(decoded.writer, writer);
      expect(decoded.operation.toJson(), record.operation.toJson());
      expect(decoded.hash, decoded.integrityHash);
      expect(decoded.encode(), raw);
    },
  );
}
