import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/current_operation.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'support/frozen_recurrence_r3/current_operation.dart' as frozen;

const space = '00000000-0000-4000-8000-000000000001';
const writer = '00000000-0000-4000-8000-000000000002';
const entity = '00000000-0000-4000-8000-000000000003';
void main() {
  CurrentOperation withRevision(
    CurrentOperation op,
    int revision, [
    Map<String, dynamic>? value,
  ]) => CurrentOperation(
    module: op.module,
    space: op.space,
    author: op.author,
    writer: op.writer,
    sequence: op.sequence,
    clock: op.clock,
    subject: op.subject,
    family: op.family,
    revision: revision,
    value: value ?? op.value,
    predecessor: op.predecessor,
  );
  for (final rule in [
    'every 2 months on the 2nd Tuesday',
    'every May and November on the 15th when done',
  ]) {
    for (final type in ['task.created', 'task.edited', 'task.completed']) {
      test(
        '$type expanded recurrence chooses r4 and frozen RC109 explicitly refuses',
        () {
          final schedule = TaskSchedule(
            dueDate: '2026-11-01',
            recurrence: rule,
          ).toJson();
          final task = <String, dynamic>{
            'title': 'Synthetic',
            'description': '',
            'assignee': entity,
            'schedule': schedule,
            'tags': <String>[],
          };
          final data = type == 'task.completed'
              ? <String, dynamic>{
                  'completedInstant': '2026-11-01T12:00:00.000000Z',
                  'successor': {
                    'id': const Uuid().v5(entity, 'successor'),
                    ...task,
                  },
                }
              : type == 'task.created'
              ? task
              : <String, dynamic>{'schedule': schedule};
          final event = LogEvent(
            space,
            writer,
            1,
            EventClock(BigInt.one),
            entity,
            type,
            data,
          );
          final raw = event.encode();
          final op = CurrentOperation.decode(raw, module: 'tasks');
          expect(op.revision, 4);
          expect(LogEvent.decode(raw).encode(), raw);
          expect(
            () => frozen.CurrentOperation.decode(raw, module: 'tasks'),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'update diagnosis',
                contains('Update the app; history was preserved'),
              ),
            ),
          );
          for (final old in type == 'task.completed' ? [3] : [1, 2]) {
            expect(
              () => LogEvent.decode(withRevision(op, old).encode()),
              throwsA(isA<FormatFailure>()),
            );
          }
        },
      );
    }
  }
  test(
    'r4 completion has cumulative strict instant fields, not legacy dates',
    () {
      final op = CurrentOperation(
        module: 'tasks',
        space: space,
        author: writer,
        writer: writer,
        sequence: 1,
        clock: '1',
        subject: entity,
        family: 'task.complete',
        revision: 4,
        value: {
          'mode': 'snapshot',
          'values': {'completedInstant': '2026-11-01T12:00:00.000000Z'},
        },
        predecessor: eventGenesisHash(space, writer),
      );
      expect(LogEvent.decode(op.encode()).operationRevision, 4);
      for (final values in <Map<String, dynamic>>[
        {},
        {'completedAt': '2026-11-01'},
        {'completedInstant': '2026-11-01T12:00:00Z'},
        {
          'completedInstant': '2026-11-01T12:00:00.000000Z',
          'completedAt': '2026-11-01',
        },
        {
          'completedInstant': '2026-11-01T12:00:00.000000Z',
          'completionTimeZone': 'UTC',
        },
      ]) {
        expect(
          () => LogEvent.decode(
            withRevision(op, 4, {
              'mode': 'snapshot',
              'values': values,
            }).encode(),
          ),
          throwsA(isA<FormatFailure>()),
        );
      }
      expect(
        () => CurrentOperation.decode(
          withRevision(op, 5).encode(),
          module: 'tasks',
        ),
        throwsFormatException,
      );
    },
  );
}
