import 'dart:math';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:uuid/uuid.dart';

void main() {
  test(
    'all arrival permutations yield identical field conflict and undo state',
    () {
      final space = const Uuid().v4(),
          a = const Uuid().v4(),
          b = const Uuid().v4(),
          id = const Uuid().v4();
      final events = [
        LogEvent(space, a, 1, HlcClock(1, 0), id, 'task.created', {
          'title': 'First',
          'description': '',
          'assignee': a,
        }),
        LogEvent(space, a, 2, HlcClock(2, 0), id, 'task.edited', {
          'title': 'A',
        }),
        LogEvent(space, b, 1, HlcClock(2, 0), id, 'task.edited', {
          'title': 'B',
        }),
        LogEvent(space, a, 3, HlcClock(3, 0), id, 'task.completed', {}),
        LogEvent(space, a, 4, HlcClock(4, 0), id, 'task.completionUndone', {
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
      LogEvent(id, id, 1, HlcClock(1, 0), id, 'future.event', {}),
      LogEvent(id, id, 1, HlcClock(1, 0), id, 'user.created', {
        'name': 'Lee',
        'future': true,
      }),
      LogEvent(id, id, 1, HlcClock(9007199254740992, 0), id, 'user.created', {
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
      final old = LogEvent(id, id, 1, HlcClock(1, 0), id, 'user.created', {
        'name': 'Fixture',
      }).toJson()..['v'] = 1;
      expect(
        () => LogEvent.decode(jsonEncode(old)),
        throwsA(isA<FormatFailure>()),
      );
      for (final e in [
        LogEvent(id, id, 1, HlcClock(1, 0), id, 'task.edited', {
          'schedule': {'startDate': '2026-11-02', 'dueDate': '2026-11-01'},
        }),
        LogEvent(id, id, 1, HlcClock(1, 0), id, 'task.edited', {
          'schedule': {'timeZone': 'Unrecognised/Place'},
        }),
        LogEvent(id, id, 1, HlcClock(1, 0), id, 'task.edited', {
          'schedule': {'futureField': 'value'},
        }),
        LogEvent(id, id, 1, HlcClock(1, 0), id, 'task.completed', {
          'completedAt': '2026-02-30',
        }),
        LogEvent(id, id, 1, HlcClock(1, 0), id, 'task.moved', {'before': id}),
        LogEvent(id, id, 1, HlcClock(1, 0), id, 'task.tagsChanged', {
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
