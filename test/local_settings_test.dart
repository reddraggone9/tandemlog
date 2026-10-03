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
      expect(await Directory('${root.path}/shared-data').exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('new desktop default is shared-data without creating files', () async {
    final root = await Directory.systemTemp.createTemp('tandemlog-settings');
    try {
      final settings = LocalSettings(root.path);
      expect(await settings.desktopDefaultFolder(), '${root.path}/shared-data');
      expect(await root.list().isEmpty, isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('settings reset retains a populated legacy default', () async {
    final root = await Directory.systemTemp.createTemp('tandemlog-settings');
    try {
      final legacy = await Directory('${root.path}/data').create();
      await File(
        '${legacy.path}/tandemlog-space.json',
      ).writeAsString('fixture');
      final settings = LocalSettings(root.path);
      expect(await settings.desktopDefaultFolder(), legacy.path);
      expect(await Directory('${root.path}/shared-data').exists(), isFalse);
      await Directory('${root.path}/shared-data').create();
      expect(await settings.desktopDefaultFolder(), legacy.path);
      expect(
        await File('${legacy.path}/tandemlog-space.json').readAsString(),
        'fixture',
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('empty legacy folder does not override the clearer default', () async {
    final root = await Directory.systemTemp.createTemp('tandemlog-settings');
    try {
      await Directory('${root.path}/data').create();
      expect(
        await LocalSettings(root.path).desktopDefaultFolder(),
        '${root.path}/shared-data',
      );
      expect(await Directory('${root.path}/shared-data').exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'populated shared-data remains preferred without altering either folder',
    () async {
      final root = await Directory.systemTemp.createTemp('tandemlog-settings');
      try {
        for (final name in ['data', 'shared-data']) {
          await Directory('${root.path}/$name').create();
          await File(
            '${root.path}/$name/tandemlog-space.json',
          ).writeAsString(name);
        }
        expect(
          await LocalSettings(root.path).desktopDefaultFolder(),
          '${root.path}/shared-data',
        );
        for (final name in ['data', 'shared-data']) {
          expect(
            await File(
              '${root.path}/$name/tandemlog-space.json',
            ).readAsString(),
            name,
          );
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
