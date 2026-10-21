import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';

void main() {
  test(
    'last section survives cold reopen in the same protected settings row',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'synthetic-section-prefs-',
      );
      LocalProfileDatabase? profile;
      try {
        profile = await LocalProfileDatabase.open(root.path);
        await LocalSettings.initialize(profile);
        final settings = LocalSettings(root.path, profileDatabase: profile);
        await settings.load();
        final before = LocalSettings.protectedValues(profile),
            writer = settings.writer;
        expect(settings.lastSection, AppSection.tasks);
        expect(before.containsKey('lastSection'), isFalse);
        await settings.saveSection(AppSection.food);
        final after = LocalSettings.protectedValues(profile);
        expect(after, {...before, 'lastSection': 'food'});
        await profile.close();
        profile = await LocalProfileDatabase.open(root.path);
        final loaded = LocalSettings(root.path, profileDatabase: profile);
        await loaded.load();
        expect(loaded.writer, writer);
        expect(loaded.lastSection, AppSection.food);
        await loaded.saveSection(AppSection.tasks);
        expect(LocalSettings.protectedValues(profile)['lastSection'], 'tasks');
        expect(
          await root
              .list()
              .where(
                (e) => !{
                  'local.sqlite',
                  'local.sqlite-wal',
                  'local.sqlite-shm',
                }.contains(e.uri.pathSegments.last),
              )
              .toList(),
          isEmpty,
          reason:
              'No sidecar preferences, workspace or synced records are created',
        );
      } finally {
        await profile?.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'unknown or malformed optional section defaults Tasks and unrelated saves preserve it',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'synthetic-unknown-section-',
      );
      final profile = await LocalProfileDatabase.open(root.path);
      try {
        await LocalSettings.initialize(profile);
        for (final unknown in [
          'future-section',
          42,
          {'unexpected': true},
          null,
        ]) {
          final values = LocalSettings.protectedValues(profile)
            ..['lastSection'] = unknown;
          profile.transaction(
            () => profile.database.execute(
              'UPDATE protected_settings SET raw=? WHERE singleton=1',
              [utf8.encode(jsonEncode(values))],
            ),
          );
          final settings = LocalSettings(root.path, profileDatabase: profile);
          await settings.load();
          expect(settings.lastSection, AppSection.tasks);
          settings.appearance = Appearance.dark;
          await settings.save();
          expect(
            LocalSettings.protectedValues(profile)['lastSection'],
            unknown,
          );
          await settings.saveSection(AppSection.food);
          expect(LocalSettings.protectedValues(profile)['lastSection'], 'food');
        }
      } finally {
        await profile.close();
        await root.delete(recursive: true);
      }
    },
  );
}
