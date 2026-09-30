import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/platform/foreground_importer.dart';

void main() {
  test('coalesces repeated notifications and retains bounded fallback', () {
    fakeAsync((clock) {
      final events = StreamController<Object?>.broadcast(sync: true);
      var calls = 0;
      final importer = ForegroundImporter(
        events: () => events.stream,
        reconcile: () async {
          calls++;
        },
      );
      importer.start();
      clock.flushMicrotasks();
      expect(calls, 1);
      for (var i = 0; i < 100; i++) {
        events.add(null);
      }
      clock.elapse(const Duration(milliseconds: 249));
      expect(calls, 1);
      clock.elapse(const Duration(milliseconds: 1));
      clock.flushMicrotasks();
      expect(calls, 2);
      clock.elapse(const Duration(seconds: 15));
      clock.flushMicrotasks();
      expect(calls, 3);
      importer.dispose();
      unawaited(events.close());
      clock.flushMicrotasks();
      expect(clock.periodicTimerCount, 0);
    });
  });
  test(
    'pause and workspace disposal cancel debounce and fallback; resume reconciles',
    () {
      fakeAsync((clock) {
        final events = StreamController<Object?>.broadcast(sync: true);
        var calls = 0;
        final importer = ForegroundImporter(
          events: () => events.stream,
          reconcile: () async {
            calls++;
          },
        );
        importer.start();
        clock.flushMicrotasks();
        events.add(null);
        importer.stop();
        clock.elapse(const Duration(minutes: 2));
        clock.flushMicrotasks();
        expect(calls, 1);
        importer.start();
        clock.flushMicrotasks();
        expect(calls, 2);
        events.add(null);
        importer.dispose();
        importer.start();
        clock.elapse(const Duration(minutes: 2));
        clock.flushMicrotasks();
        expect(calls, 2);
        unawaited(events.close());
        clock.flushMicrotasks();
        expect(clock.periodicTimerCount, 0);
      });
    },
  );
  test(
    'watcher failure recovers on fallback and overlapping work is serialized',
    () {
      fakeAsync((clock) {
        var attempts = 0, calls = 0;
        final events = StreamController<Object?>.broadcast(sync: true);
        final pending = Completer<void>();
        final importer = ForegroundImporter(
          events: () {
            attempts++;
            if (attempts == 1) throw StateError('directory temporarily absent');
            return events.stream;
          },
          reconcile: () {
            calls++;
            return calls == 1 ? pending.future : Future.value();
          },
        );
        importer.start();
        clock.elapse(const Duration(seconds: 15));
        expect(attempts, 2);
        expect(calls, 1);
        pending.complete();
        clock.flushMicrotasks();
        expect(calls, 2);
        events.addError(StateError('watcher unavailable'));
        clock.flushMicrotasks();
        expect(calls, 3);
        clock.elapse(const Duration(seconds: 15));
        clock.flushMicrotasks();
        expect(attempts, 3);
        expect(calls, 4);
        importer.dispose();
        unawaited(events.close());
        clock.flushMicrotasks();
      });
    },
  );
}
