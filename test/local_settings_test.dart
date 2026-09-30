import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/local_settings.dart';

void main() {
  test(
    'legacy folder/user settings remain selected and default to System',
    () async {
      final root = await Directory.systemTemp.createTemp('tandemlog-settings');
      try {
        await File(
          '${root.path}/settings.json',
        ).writeAsString('{"folder":"chosen","user":"lee"}');
        final settings = LocalSettings(root.path);
        await settings.load();
        expect(settings.folder, 'chosen');
        expect(settings.user, 'lee');
        expect(settings.appearance, Appearance.system);
        settings.appearance = Appearance.dark;
        await settings.save();
        final loaded = LocalSettings(root.path);
        await loaded.load();
        expect(loaded.folder, 'chosen');
        expect(loaded.user, 'lee');
        expect(loaded.appearance, Appearance.dark);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('theme-only preferences never create a canonical workspace', () async {
    final root = await Directory.systemTemp.createTemp('tandemlog-settings');
    try {
      final settings = LocalSettings(root.path)..appearance = Appearance.light;
      await settings.save();
      final loaded = LocalSettings(root.path);
      await loaded.load();
      expect(loaded.folder, isNull);
      expect(loaded.appearance, Appearance.light);
      expect(await Directory('${root.path}/data').exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
