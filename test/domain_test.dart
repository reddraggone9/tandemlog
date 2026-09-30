import 'dart:math';
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
        LogEvent(space, a, 1, 1, id, 'task.created', {
          'title': 'First',
          'description': '',
          'assignee': a,
        }),
        LogEvent(space, a, 2, 2, id, 'task.edited', {'title': 'A'}),
        LogEvent(space, b, 1, 2, id, 'task.edited', {'title': 'B'}),
        LogEvent(space, a, 3, 3, id, 'task.completed', {}),
        LogEvent(space, a, 4, 4, id, 'task.completionUndone', {
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
      LogEvent(id, id, 1, 1, id, 'future.event', {}),
      LogEvent(id, id, 1, 1, id, 'user.created', {
        'name': 'Lee',
        'future': true,
      }),
      LogEvent(id, id, 1, 9007199254740992, id, 'user.created', {
        'name': 'Lee',
      }),
    ]) {
      expect(() => LogEvent.decode(e.encode()), throwsA(isA<FormatFailure>()));
    }
  });
}
