import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/diagnostics/startup_trace.dart';

void _block(int ms) {
  final held = Stopwatch()..start();
  while (held.elapsedMilliseconds < ms) {}
}

({int longest, List<List<int>> stalls}) _stalls(String line) {
  final match = RegExp(r' stall_ms=(\d+) stalls=(\[.*\])$').firstMatch(line)!;
  return (
    longest: int.parse(match.group(1)!),
    stalls: [
      for (final stall in jsonDecode(match.group(2)!) as List)
        (stall as List).cast<int>(),
    ],
  );
}

void main() {
  test('an unwatched trace keeps the original line', () {
    final line = StartupTrace(Stopwatch()..start()).line('MARK');
    expect(line, isNot(contains('stall_ms')));
    expect(line, matches(RegExp(r'^MARK at=\S+ ms=\d+ ')));
  });

  test('a blocked isolate is reported as one stall', () async {
    final trace = StartupTrace(Stopwatch()..start())..watchStalls();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    _block(120);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final seen = _stalls(trace.line('MARK'));
    expect(seen.longest, inInclusiveRange(120, 400));
    expect(seen.stalls.where((stall) => stall[1] >= 120), hasLength(1));
  });

  test('work that returns to the event loop is not a stall', () async {
    final trace = StartupTrace(Stopwatch()..start())..watchStalls();
    for (var slice = 0; slice < 12; slice++) {
      _block(10);
      await Future<void>.delayed(Duration.zero);
    }
    expect(_stalls(trace.line('MARK')).longest, lessThan(120));
  });

  test('the stretch that ends at the report counts', () async {
    final trace = StartupTrace(Stopwatch()..start())..watchStalls();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _block(80);
    expect(_stalls(trace.line('MARK')).longest, greaterThanOrEqualTo(80));
  });
}
