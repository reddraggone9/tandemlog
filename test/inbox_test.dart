import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/projection.dart';
import 'package:tandemlog/domain/task_view.dart';
import 'package:tandemlog/domain/timed_view.dart';
import 'package:uuid/uuid.dart';

void main() {
  final space = const Uuid().v4(), writer = const Uuid().v4();
  final task = const Uuid().v4(), user = const Uuid().v4();
  LogEvent event(int seq, String type, Map<String, dynamic> data) => LogEvent(
    space,
    writer,
    seq,
    EventClock(BigInt.from(seq)),
    task,
    type,
    data,
  );
  LogEvent created([Map<String, dynamic> fields = const {}]) =>
      event(1, 'task.created', {
        'title': 'Synthetic capture',
        'description': '',
        'assignee': user,
        ...fields,
      });

  test('Inbox means raw capture until first surviving saved edit', () {
    final creation = created();
    expect(project([creation])!['inbox'], isTrue);
    for (final fields in [
      {'description': 'A useful note'},
      {
        'tags': ['home'],
      },
      {
        'schedule': {'dueDate': '2026-10-03'},
      },
      {
        'schedule': {'dueMinDays': 0},
      },
    ]) {
      expect(project([created(fields)])!['inbox'], isFalse);
    }
    final edit = event(2, 'task.edited', {'title': 'Saved title'});
    expect(project([creation, edit])!['inbox'], isFalse);
    final undo = event(3, 'task.operationUndone', {'operation': edit.id});
    expect(project([creation, edit, undo])!['inbox'], isTrue);
    final tagEdit = event(2, 'task.tagsChanged', {
      'add': ['home'],
      'remove': <String>[],
    });
    final removeTag = event(3, 'task.tagsChanged', {
      'add': <String>[],
      'remove': ['${tagEdit.id}:0'],
    });
    expect(project([creation, tagEdit, removeTag])!['inbox'], isFalse);
    expect(
      project([
        creation,
        event(2, 'task.moved', {'before': null}),
      ])!['inbox'],
      isTrue,
    );
  });

  test('derived successors are organized even if their snapshot is empty', () {
    final completion = event(2, 'task.completed', {
      'successor': {
        'id': const Uuid().v4(),
        'title': 'Synthetic next',
        'description': '',
        'assignee': user,
      },
    });
    expect(project([successorCreation(completion)])!['inbox'], isFalse);
    expect(
      project([
        LogEvent(
          space,
          writer,
          1,
          EventClock(BigInt.one),
          user,
          'user.created',
          {'name': 'Synthetic user'},
        ),
      ])!['inbox'],
      isFalse,
    );
  });

  test('Inbox is first in manual order and separate from Someday/history', () {
    Map<String, dynamic> row(
      String id, {
      bool inbox = false,
      bool done = false,
      Map<String, dynamic> schedule = const {},
    }) => {
      'kind': 'task',
      'id': id,
      'title': id,
      'assignee': user,
      'schedule': schedule,
      'completed': done,
      'inbox': inbox,
    };
    final rows = [
      row('dated', schedule: {'dueDate': '2026-10-02'}),
      row('organized'),
      row('raw-b', inbox: true),
      row('raw-a', inbox: true),
      row('done', inbox: true, done: true),
    ];
    final time = ViewTime(
      instant: DateTime.utc(2026, 10, 3),
      localZoneId: 'UTC',
      localOffset: Duration.zero,
    );
    final view = projectTaskView(rows, time).value;
    expect(view.open.map((e) => e.task['id']), [
      'raw-b',
      'raw-a',
      'dated',
      'organized',
    ]);
    expect(view.openGroups.map((e) => e.inbox), [true, false, false]);
    expect(view.completedGroups.single.inbox, isFalse);
    expect(view.open.first.sharesOrderBucket(view.open[1]), isTrue);
    expect(view.open.first.sharesOrderBucket(view.open.last), isFalse);
    final filtered = projectTaskView(
      rows,
      time,
      searchQuery: 'organized',
    ).value;
    expect(filtered.open.single.inbox, isFalse);
  });
}
