import 'dart:math';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:uuid/uuid.dart';

void main() {
  test(
    'canonical UUID admission matches namespace validation and rejects aliases',
    () {
      final good = const Uuid().v4();
      for (final id in [
        good,
        const Uuid().v5(good, 'fixture'),
        '00000000-0000-0000-0000-000000000000',
        'ffffffff-ffff-ffff-ffff-ffffffffffff',
      ]) {
        expect(isCanonicalId(id), isTrue);
        expect(() => const Uuid().v5(id, 'successor'), returnsNormally);
      }
      for (final bad in [
        '------------------------------------',
        '11111111-1111-1111-1111-111111111111',
        good.toUpperCase(),
        good.replaceAll('-', ''),
      ]) {
        expect(isCanonicalId(bad), isFalse);
        for (final entry in [
          LogEvent(good, good, 1, testClock(1, 0), bad, 'user.created', {
            'name': 'Fixture',
          }),
          LogEvent(
            good,
            good,
            1,
            testClock(1, 0),
            good,
            'task.completionUndone',
            {'completion': '$bad:1'},
          ),
          LogEvent(good, good, 1, testClock(1, 0), good, 'task.tagsChanged', {
            'add': <String>[],
            'remove': ['$bad:1:0'],
          }),
        ]) {
          expect(
            () => LogEvent.decode(entry.encode()),
            throwsA(isA<FormatFailure>()),
          );
        }
      }
    },
  );
  test(
    'all arrival permutations yield identical field conflict and undo state',
    () {
      final space = const Uuid().v4(),
          a = const Uuid().v4(),
          b = const Uuid().v4(),
          id = const Uuid().v4();
      final events = [
        LogEvent(space, a, 1, testClock(1, 0), id, 'task.created', {
          'title': 'First',
          'description': '',
          'assignee': a,
        }),
        LogEvent(space, a, 2, testClock(2, 0), id, 'task.edited', {
          'title': 'A',
        }),
        LogEvent(space, b, 1, testClock(2, 0), id, 'task.edited', {
          'title': 'B',
        }),
        LogEvent(space, a, 3, testClock(3, 0), id, 'task.completed', {}),
        LogEvent(space, a, 4, testClock(4, 0), id, 'task.completionUndone', {
          'completion': '$a:3',
        }),
      ];
      final expected = project([...events]);
      for (var i = 0; i < 100; i++) {
        expect(project([...events]..shuffle(Random(i))), expected);
      }
      expect(expected!['completed'], false);
      expect(expected['title'], a.compareTo(b) > 0 ? 'A' : 'B');
    },
  );
  test('unknown event/fields and counter overflow are rejected', () {
    final id = const Uuid().v4();
    for (final e in [
      LogEvent(id, id, 1, testClock(1, 0), id, 'future.event', {}),
      LogEvent(id, id, 1, testClock(1, 0), id, 'import.document', {
        'lines': [],
      }),
      LogEvent(id, id, 1, testClock(1, 0), id, 'task.created', {
        'title': 'Fixture',
        'description': '',
        'assignee': id,
        'import': {'documentId': id, 'line': 1},
      }),
      LogEvent(id, id, 1, testClock(1, 0), id, 'user.created', {
        'name': 'Lee',
        'future': true,
      }),
      LogEvent(id, id, 1, testClock(9007199254740992, 0), id, 'user.created', {
        'name': 'Lee',
      }),
    ]) {
      expect(() => LogEvent.decode(e.encode()), throwsA(isA<FormatFailure>()));
    }
  });
  test(
    'historical v1 events and invalid new active fields fail explicitly',
    () {
      final id = const Uuid().v4();
      final old = LogEvent(id, id, 1, testClock(1, 0), id, 'user.created', {
        'name': 'Fixture',
      }).toJson()..['v'] = 1;
      expect(
        () => LogEvent.decode(jsonEncode(old)),
        throwsA(isA<FormatFailure>()),
      );
      for (final e in [
        LogEvent(id, id, 1, testClock(1, 0), id, 'task.edited', {
          'schedule': {'startDate': '2026-11-02', 'dueDate': '2026-11-01'},
        }),
        LogEvent(id, id, 1, testClock(1, 0), id, 'task.edited', {
          'schedule': {'timeZone': 'Unrecognised/Place'},
        }),
        LogEvent(id, id, 1, testClock(1, 0), id, 'task.edited', {
          'schedule': {'futureField': 'value'},
        }),
        LogEvent(id, id, 1, testClock(1, 0), id, 'task.completed', {
          'completedAt': '2026-02-30',
        }),
        LogEvent(id, id, 1, testClock(1, 0), id, 'task.moved', {'before': id}),
        LogEvent(id, id, 1, testClock(1, 0), id, 'task.tagsChanged', {
          'add': ['tag'],
          'remove': ['not-observed-token'],
        }),
      ]) {
        expect(
          () => LogEvent.decode(e.encode()),
          throwsA(isA<FormatFailure>()),
        );
      }
    },
  );
}

EventClock testClock(int wallMs, int increment) => EventClock(
  BigInt.from(wallMs) * BigInt.from(1000000) + BigInt.from(increment),
);
