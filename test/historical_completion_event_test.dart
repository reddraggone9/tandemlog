import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/historical_completion.dart';

const _space = '00000000-0000-4000-8000-000000000001';
const _parent = '00000000-0000-4000-8000-000000000002';
const _a = '00000000-0000-4000-8000-000000000003';
const _b = '00000000-0000-4000-8000-000000000004';
final _child = const Uuid().v5(_parent, 'successor');
LogEvent _event(
  String writer,
  int sequence,
  int clock,
  String type,
  Map<String, dynamic> data,
) => LogEvent.decode(
  LogEvent(
    _space,
    writer,
    sequence,
    EventClock(BigInt.from(clock)),
    _parent,
    type,
    data,
  ).encode(previousHash: eventGenesisHash(_space, writer)),
);

void main() {
  final source = _event(_a, 1, 1, 'task.completed', {
    'completedAt': '2030-05-10',
    'successor': {
      'id': _child,
      'title': 'Original child',
      'description': '',
      'assignee': _a,
      'tags': <String>[],
      'schedule': <String, dynamic>{},
    },
  });
  Map<String, dynamic> payload() => {
    'completedAt': '2030-06-10',
    'retainedSuccessor': {
      'id': _child,
      'completion': source.id,
      'hash': source.hash,
    },
  };
  test(
    'historical completion is required, separate and hash-bound to earlier scalar initialization',
    () {
      final marker = _event(
        _b,
        1,
        2,
        'task.completedKeepingSuccessor',
        payload(),
      );
      expect(verifyHistoricalCompletion(marker, source), true);
      expect(verifyHistoricalCompletion(marker, null), false);
      expect(isTaskCompletion(marker.type), true);
      expect(
        () => _event(_b, 1, 2, marker.type, {
          ...payload(),
          'successor': source.data['successor'],
        }),
        throwsA(isA<FormatFailure>()),
      );
      final altered = _event(_a, 1, 1, source.type, {
        ...source.data,
        'completedAt': '2030-05-11',
      });
      expect(
        () => verifyHistoricalCompletion(marker, altered),
        throwsA(isA<FormatFailure>()),
      );
    },
  );
  test(
    'forward/self reference, extra retained metadata and wrong child identities fail wire admission',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (data) => data['retainedSuccessor']['completion'] = '$_b:1',
        (data) => data['retainedSuccessor']['completion'] = '$_b:2',
        (data) => data['retainedSuccessor']['context'] = 'f' * 64,
        (data) => data['retainedSuccessor']['id'] = _parent,
        (data) => data.remove('completedAt'),
      ]) {
        final data = payload();
        mutate(data);
        expect(
          () => _event(_b, 1, 2, 'task.completedKeepingSuccessor', data),
          throwsA(isA<FormatFailure>()),
        );
      }
    },
  );
  test(
    'known equal or later source clocks remain invalid after delayed arrival',
    () {
      final marker = _event(
        _b,
        1,
        2,
        'task.completedKeepingSuccessor',
        payload(),
      );
      for (final clock in [2, 3]) {
        final future = _event(_a, 1, clock, source.type, source.data);
        final data = payload()..['retainedSuccessor']['hash'] = future.hash;
        final declared = _event(_b, 1, 2, marker.type, data);
        expect(verifyHistoricalCompletion(declared, null), false);
        expect(
          () => verifyHistoricalCompletion(declared, future),
          throwsA(isA<FormatFailure>()),
        );
      }
    },
  );
}
