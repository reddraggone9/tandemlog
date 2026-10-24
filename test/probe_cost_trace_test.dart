import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/log_folder.dart';
import '../tool/windows_widget_qa/probe_cost_trace.dart';

void main() {
  test('span cap preserves successful result and original failure', () async {
    final trace = ProbeCostTrace(() => 0);
    for (var i = 0; i < ProbeCostTrace.maximumSpans; i++) {
      trace.spans.add({'operation': 'fixture'});
    }
    expect(await trace.measure('success', () async => 7), 7);
    final error = StateError('original append failure');
    await expectLater(
      trace.measure<void>('failure', () async {
        throw error;
      }),
      throwsA(same(error)),
    );
    expect(trace.spans, hasLength(ProbeCostTrace.maximumSpans));
    expect(trace.droppedSpans, 2);
    expect(trace.report()['complete'], isFalse);
  });

  test(
    'trace preserves result/failure and does not turn overlapping spans into costs',
    () async {
      var now = 10;
      final trace = ProbeCostTrace(() => now);
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = await trace.measure('outer', () async {
        now = 12;
        await trace.measure('inner', () async {
          now = 17;
        });
        now = 20;
        return bytes;
      });
      expect(identical(result, bytes), isTrue);
      expect(trace.spans.map((s) => s['operation']), ['inner', 'outer']);
      expect(trace.spans.last['returnedBytes'], 3);
      expect(trace.spans.last['startUs'], 10);
      expect(trace.spans.last['endUs'], 20);
      final failure = StateError('preserved');
      await expectLater(
        trace.measure<void>('failure', () async {
          throw failure;
        }),
        throwsA(same(failure)),
      );
      expect(trace.spans.last['succeeded'], isFalse);
      trace.action('save', 10, 20);
      expect(trace.report()['inclusiveOverlappingIntervalsDoNotSum'], isTrue);
      expect(trace.report()['causalParentAttributionClaimed'], isFalse);
    },
  );

  test(
    'diagnostic folder retains capabilities, exact bytes and range offsets',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'probe-provider-cost-',
      );
      addTearDown(() => root.delete(recursive: true));
      final watch = Stopwatch()..start();
      final trace = ProbeCostTrace(() => watch.elapsedMicroseconds);
      final folder = ProbeLocalLogFolder(root.path, trace);
      expect(folder, isA<BoundedRangeLogFolder>());
      expect(folder, isA<AtomicReplaceLogFolder>());
      expect(folder, isA<RecoverableReplaceLogFolder>());
      expect(folder, isA<TailTruncateLogFolder>());
      await folder.create('sample.applog', Uint8List.fromList([1, 2]));
      await folder.append('sample.applog', Uint8List.fromList([3, 4]));
      expect(await folder.readFrom('sample.applog', 2), [3, 4]);
      expect(await folder.readBounded('sample.applog', 4), [1, 2, 3, 4]);
      expect((await folder.list()).single.name, 'sample.applog');
      final ranges = trace.spans.where(
        (s) => s['operation'] == 'provider.readFromBounded',
      );
      expect(ranges, hasLength(1));
      expect(ranges.single['offset'], 2);
      expect(ranges.single['returnedBytes'], 2);
      expect(
        trace.spans.where((s) => s['operation'] == 'durability.append+barrier'),
        hasLength(1),
      );
      await expectLater(
        folder.readBounded('sample.applog', 1),
        throwsFormatException,
      );
      expect(trace.spans.last['succeeded'], isFalse);
    },
  );
}
