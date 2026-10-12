import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/platform/android_section_navigation.dart';
import 'package:tandemlog/storage/local_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tandemlog/sections-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<void> native(Object? args) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('openSection', args),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'newer warm intent beats delayed initial; duplicates and unknown targets ignored',
    () async {
      final initial = Completer<Object?>();
      final accepted = <AppSection>[];
      messenger.setMockMethodCallHandler(channel, (_) => initial.future);
      final adapter = AndroidSectionNavigation(channel: channel);
      final started = adapter.start(accepted.add);
      await native({'id': 2, 'section': 'food'});
      initial.complete({'id': 1, 'section': 'tasks'});
      await started;
      await native({'id': 2, 'section': 'food'});
      await native({'id': 3, 'section': 'arbitrary-route'});
      await native({'id': '4', 'section': 'tasks'});
      await native({'id': 4, 'section': 'tasks'});
      expect(accepted, [AppSection.food, AppSection.tasks]);
      adapter.dispose();
    },
  );
  test(
    'manual navigation beats delayed cold request; later warm navigation still works',
    () async {
      final initial = Completer<Object?>();
      final accepted = <AppSection>[];
      messenger.setMockMethodCallHandler(channel, (_) => initial.future);
      final adapter = AndroidSectionNavigation(channel: channel);
      final started = adapter.start(accepted.add);
      adapter.manualNavigation();
      initial.complete({'id': 1, 'section': 'food'});
      await started;
      expect(accepted, isEmpty);
      await native({'id': 2, 'section': 'tasks'});
      expect(accepted, [AppSection.tasks]);
      adapter.dispose();
      await native({'id': 3, 'section': 'food'});
      expect(accepted, [AppSection.tasks]);
    },
  );
  test('missing native adapter does not block setup', () async {
    final accepted = <AppSection>[];
    final adapter = AndroidSectionNavigation(channel: channel);
    await adapter.start(accepted.add);
    expect(accepted, isEmpty);
    adapter.dispose();
  });
}
