import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/task_store.dart';

void main() {
  test(
    'offline observation includes tombstones and complete completion projection',
    () {
      const space = '11111111-1111-4111-8111-111111111111';
      const writer = '22222222-2222-4222-8222-222222222222';
      const task = '33333333-3333-4333-8333-333333333333';
      const person = '44444444-4444-4444-8444-444444444444';
      var head = eventGenesisHash(space, writer);
      var sequence = 0;
      LogEvent make(String entity, String type, Map<String, dynamic> data) {
        final e = LogEvent.decode(
          LogEvent(
            space,
            writer,
            ++sequence,
            EventClock(BigInt.from(sequence)),
            entity,
            type,
            data,
            previousHash: head,
          ).encode(),
        );
        head = e.hash!;
        return e;
      }

      final events = [
        make(person, 'user.created', {'name': 'Synthetic'}),
        make(task, 'task.created', {
          'title': 'Synthetic task',
          'description': '',
          'assignee': person,
        }),
        make(task, 'task.completed', {
          'completedInstant': '2026-10-26T10:00:00.000000Z',
        }),
        make(task, 'task.deleted', {}),
      ];
      List<Map<String, dynamic>>? observed;
      final visible = TaskStore.validateSemanticHistory(
        events,
        space: space,
        writer: writer,
        onAllRows: (rows) => observed = rows,
      );
      expect(visible.where((r) => r['id'] == task), isEmpty);
      final row = observed!.singleWhere((r) => r['id'] == task);
      expect(row['deleted'], isTrue);
      expect(row['completed'], isTrue);
      expect(row['completedInstant'], '2026-10-26T10:00:00.000000Z');
      expect(
        row['completedMicros'],
        DateTime.utc(2026, 10, 26, 10).microsecondsSinceEpoch,
      );
      expect(() => row['title'] = 'changed', throwsUnsupportedError);
    },
  );
}
