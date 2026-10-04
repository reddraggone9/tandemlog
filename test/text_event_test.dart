import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';

const s = '00000000-0000-4000-8000-000000000001';
const w = '00000000-0000-4000-8000-000000000002';
const e = '00000000-0000-4000-8000-000000000003';
const allocation = '00000000-0000-4000-8000-000000000004';
final digest = 'a' * 64;

Map<String, dynamic> change() => {
  'context': digest,
  'allocation': allocation,
  'actor': 42,
  'update': base64Encode([0, 0]),
};
LogEvent roundTrip(
  String type,
  Map<String, dynamic> data, {
  String entity = e,
}) => LogEvent.decode(
  LogEvent(s, w, 1, EventClock(BigInt.one), entity, type, data).encode(),
);

void main() {
  test('new text packets retain exact bytes and closed metadata', () {
    final value = roundTrip('task.textEdited', {
      'changes': {'title': change()},
      'intent': 'undo',
    });
    expect(value.data['changes']['title']['update'], base64Encode([0, 0]));
    expect(value.data['intent'], 'undo');
    expect(
      () => value.data['changes']['title']['actor'] = 43,
      throwsUnsupportedError,
    );
  });
  test('text packet fields, ownership and canonical base64 fail closed', () {
    for (final invalid in [
      {...change(), 'actor': 1},
      {...change(), 'actor': 9007199254740992},
      {...change(), 'actor': '42'},
      {...change(), 'allocation': 'bad'},
      {...change(), 'context': 'A' * 64},
      {...change(), 'update': 'AAA'},
      {...change(), 'update': 'AA A='},
      {...change(), 'update': ''},
      {...change(), 'future': true},
    ]) {
      expect(
        () => roundTrip('task.textEdited', {
          'changes': {'title': invalid},
        }),
        throwsA(isA<FormatFailure>()),
      );
    }
    for (final invalid in [
      {'changes': {}},
      {
        'changes': {'name': change()},
      },
      {
        'changes': {'title': change()},
        'title': 'Replacement',
      },
      {
        'changes': {'title': change()},
        'intent': 'redo',
      },
      {
        'changes': {'title': change()},
        'batch': allocation,
      },
    ]) {
      expect(
        () => roundTrip('task.textEdited', Map<String, dynamic>.from(invalid)),
        throwsA(isA<FormatFailure>()),
      );
    }
  });
  test('one text command can carry atomic existing nontext edits', () {
    final value = roundTrip('task.textEdited', {
      'changes': {'description': change()},
      'assignee': s,
      'schedule': {'dueDate': '2026-10-04'},
      'tagChanges': {
        'add': ['work'],
        'remove': <String>[],
      },
    });
    expect(value.data['schedule']['dueDate'], '2026-10-04');
    expect(
      () => roundTrip('task.textEdited', {
        'changes': {'title': change()},
        'schedule': {'startDate': '2026-10-05', 'dueDate': '2026-10-04'},
      }),
      throwsA(isA<FormatFailure>()),
    );
    expect(
      () => roundTrip('task.textEdited', {
        'changes': {'title': change()},
        'assignee': 'bad',
      }),
      throwsA(isA<FormatFailure>()),
    );
  });
  test(
    'pure projection applies nontext without leaking native packet metadata',
    () {
      final created = LogEvent(
        s,
        w,
        1,
        EventClock(BigInt.one),
        e,
        'task.created',
        {'title': 'Seed', 'description': 'Notes', 'assignee': w},
      );
      final edited = LogEvent(
        s,
        w,
        2,
        EventClock(BigInt.two),
        e,
        'task.textEdited',
        {
          'changes': {'title': change()},
          'assignee': s,
          'schedule': {'dueDate': '2026-10-04'},
          'tagChanges': {
            'add': ['work'],
            'remove': <String>[],
          },
        },
      );
      final view = project([edited, created])!;
      expect(view['title'], 'Seed');
      expect(view['assignee'], s);
      expect(view['schedule']['dueDate'], '2026-10-04');
      expect(view['tags'], ['work']);
      expect(view['inbox'], false);
      expect(view.containsKey('changes'), false);
      expect(view.containsKey('intent'), false);
    },
  );
  test('baseline root declares closed exact prefix and genesis frontiers', () {
    final value = roundTrip('text.baselineInitialized', {
      'codec': 'yrs-v1',
      'adapter': 1,
      'frontiers': {
        w: {'seq': 0, 'hash': eventGenesisHash(s, w)},
      },
      'seedDigest': digest,
    }, entity: s);
    expect(value.data['frontiers'][w]['seq'], 0);
    expect(project([value]), isNull);
  });
  test(
    'baseline unknown versions and invalid scope or frontiers fail closed',
    () {
      final data = <String, dynamic>{
        'codec': 'yrs-v1',
        'adapter': 1,
        'frontiers': {
          w: {'seq': 0, 'hash': eventGenesisHash(s, w)},
        },
        'seedDigest': digest,
      };
      for (final invalid in [
        {...data, 'codec': 'yrs-v2'},
        {...data, 'adapter': 2},
        {...data, 'seedDigest': 'bad'},
        {...data, 'rawSource': 'text'},
        {
          ...data,
          'frontiers': {
            w: {'seq': -1, 'hash': digest},
          },
        },
        {
          ...data,
          'frontiers': {
            w: {'seq': 9007199254740992, 'hash': digest},
          },
        },
        {
          ...data,
          'frontiers': {
            'bad': {'seq': 1, 'hash': digest},
          },
        },
        {
          ...data,
          'frontiers': {
            w: {'seq': 1, 'hash': digest, 'clock': '1'},
          },
        },
      ]) {
        expect(
          () => roundTrip('text.baselineInitialized', invalid, entity: s),
          throwsA(isA<FormatFailure>()),
        );
      }
      expect(
        () => roundTrip('text.baselineInitialized', data),
        throwsA(isA<FormatFailure>()),
      );
    },
  );
}
