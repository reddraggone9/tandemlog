import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/platform/view_time_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('time-source-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });
  Future<void> nativeChange() async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      'time-source-test',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('changed')),
      (ByteData? _) {
        done.complete();
      },
    );
    await done.future;
  }

  testWidgets(
    'same-offset zone changes notify; unchanged fallback stays quiet',
    (tester) async {
      var zone = 'America/Chicago', notifications = 0;
      final source = ViewTimeSource(
        channel: channel,
        onChanged: () => notifications++,
        loadZone: () async => zone,
        now: () => DateTime.utc(2026, 1, 15),
      );
      source.start();
      await tester.pump();
      expect(source.ready, true);
      expect(notifications, 1);
      final old = source.readTime();
      await tester.pump(const Duration(minutes: 1));
      expect(notifications, 1);
      zone = 'America/Mexico_City';
      await tester.pump(const Duration(minutes: 1));
      expect(notifications, 2);
      expect(source.readTime().localOffset, old.localOffset);
      expect(source.readTime().sameZone(old), false);
      await nativeChange();
      await tester.pump();
      expect(
        notifications,
        3,
        reason:
            'Explicit native clock change invalidates even with unchanged zone.',
      );
      source.stop();
      await nativeChange();
      await tester.pump(const Duration(minutes: 2));
      expect(notifications, 3);
      source.dispose();
    },
  );

  testWidgets(
    'late requests and disposed callbacks cannot replace current zone',
    (tester) async {
      final reads = <Completer<String>>[];
      var notifications = 0;
      final source = ViewTimeSource(
        channel: channel,
        onChanged: () => notifications++,
        loadZone: () {
          final c = Completer<String>();
          reads.add(c);
          return c.future;
        },
      );
      source.start();
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      reads[1].complete('Europe/Paris');
      await tester.pump();
      reads[0].complete('Europe/London');
      await tester.pump();
      expect(source.readTime().localZoneId, 'Europe/Paris');
      expect(notifications, 1);
      source.stop();
      source.start();
      await tester.pump();
      expect(source.ready, false);
      source.dispose();
      reads.last.complete('America/Chicago');
      await tester.pump();
      expect(notifications, 1);
    },
  );

  testWidgets(
    'unknown local zone is explicit, and recovers without UTC guessing',
    (tester) async {
      var zone = 'Not/AZone';
      final source = ViewTimeSource(
        channel: channel,
        onChanged: () {},
        loadZone: () async => zone,
      );
      source.start();
      await tester.pump();
      expect(source.ready, false);
      expect(source.error, isNotNull);
      expect(source.readTime, throwsStateError);
      zone = 'Etc/UTC';
      await tester.pump(const Duration(minutes: 1));
      expect(source.ready, true);
      expect(source.error, isNull);
      source.dispose();
    },
  );

  test('local mapping refuses disabled-DST or inconsistent OS offsets', () {
    expect(
      () => validateLocalOffset(
        'America/Chicago',
        DateTime.utc(2026, 7, 1),
        const Duration(hours: -5),
      ),
      returnsNormally,
    );
    expect(
      () => validateLocalOffset(
        'America/Chicago',
        DateTime.utc(2026, 7, 1),
        const Duration(hours: -6),
      ),
      throwsStateError,
    );
  });

  test('explicit Linux TZ identity does not need filesystem access', () async {
    expect(
      await readLinuxZone(environment: {'TZ': 'America/Chicago'}),
      'America/Chicago',
    );
  });

  test(
    'Linux zone files honor localtime symlink and copied-file identity',
    () async {
      final root = await Directory.systemTemp.createTemp('zone-identity');
      try {
        final zone = File('${root.path}/zoneinfo/Europe/Paris');
        await zone.parent.create(recursive: true);
        await zone.writeAsString('fixture');
        await Link('${root.path}/localtime').create(zone.path);
        expect(
          await readLinuxZone(environment: {}, etcPath: root.path),
          'Europe/Paris',
        );
        expect(
          await readLinuxZone(environment: {'TZ': ':${zone.path}'}),
          'Europe/Paris',
        );
        await Link('${root.path}/localtime').delete();
        await File('${root.path}/localtime').writeAsString('fixture');
        await File('${root.path}/timezone').writeAsString('Europe/Paris');
        expect(
          await readLinuxZone(
            environment: {},
            etcPath: root.path,
            zoneInfoPath: '${root.path}/zoneinfo',
          ),
          'Europe/Paris',
        );
        await File('${root.path}/localtime').writeAsString('other');
        await expectLater(
          readLinuxZone(
            environment: {},
            etcPath: root.path,
            zoneInfoPath: '${root.path}/zoneinfo',
          ),
          throwsStateError,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isLinux, // Exercises Linux path and symlink semantics.
  );
}
