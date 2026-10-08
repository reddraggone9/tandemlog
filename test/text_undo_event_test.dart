import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';

const s = '00000000-0000-4000-8000-000000000001';
const w = '00000000-0000-4000-8000-000000000002';
const e = '00000000-0000-4000-8000-000000000003';
const a = '00000000-0000-4000-8000-000000000004';
Map<String, dynamic> packet() => {
  'context': 'a' * 64,
  'actor': 42,
  'allocation': a,
  'update': base64Encode([0, 0]),
};
LogEvent wire(Map<String, dynamic> data) => LogEvent.decode(
  LogEvent(
    s,
    w,
    1,
    EventClock(BigInt.one),
    e,
    'task.textEditUndone',
    data,
  ).encode(),
);

void main() {
  test(
    'native Undo preserves compensation bytes and names original command',
    () {
      final event = wire({
        'operation': '$w:2',
        'changes': {'title': packet()},
      });
      expect(event.data['operation'], '$w:2');
      expect(event.data['changes']['title']['update'], base64Encode([0, 0]));
      expect(retractedOperationIds([event]), {'$w:2'});
    },
  );
  test(
    'Undo nontext effects remains possible when native compensation is empty',
    () {
      expect(
        wire({
          'operation': '$w:2',
          'changes': <String, dynamic>{},
        }).data['changes'],
        isEmpty,
      );
      for (final invalid in [
        {'operation': 'bad', 'changes': <String, dynamic>{}},
        {'operation': '$w:0', 'changes': <String, dynamic>{}},
        {
          'operation': '$w:2',
          'changes': {'other': packet()},
        },
        {'operation': '$w:2', 'changes': <String, dynamic>{}, 'title': 'Old'},
      ]) {
        expect(() => wire(invalid), throwsA(isA<FormatFailure>()));
      }
    },
  );
  test(
    'Undo retracts only the original nontext effects in pure projection',
    () {
      final created = LogEvent(
        s,
        w,
        1,
        EventClock(BigInt.one),
        e,
        'task.created',
        {
          'title': 'Seed',
          'description': '',
          'assignee': w,
          'tags': ['home'],
        },
      );
      final edited = LogEvent(
        s,
        w,
        2,
        EventClock(BigInt.two),
        e,
        'task.textEdited',
        {
          'changes': {'title': packet()},
          'assignee': s,
          'tagChanges': {
            'add': ['work'],
            'remove': <String>[],
          },
        },
      );
      final remote = LogEvent(
        s,
        w,
        3,
        EventClock(BigInt.from(3)),
        e,
        'task.edited',
        {'assignee': a},
      );
      final undo = LogEvent(
        s,
        w,
        4,
        EventClock(BigInt.from(4)),
        e,
        'task.textEditUndone',
        {
          'operation': edited.id,
          'changes': {'title': packet()},
        },
      );
      final view = project([undo, edited, created, remote])!;
      expect(view['assignee'], a);
      expect(view['tags'], ['home']);
      expect(view['title'], 'Seed');
      expect(view.containsKey('changes'), false);
      expect(retractedOperationIds([undo, undo]), {edited.id});
    },
  );
}
