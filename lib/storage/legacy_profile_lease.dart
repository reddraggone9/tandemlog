import 'dart:io';

import 'local_profile_database.dart';
import 'profile_lock.dart';

/// One coordinated migration lease spans file/cache capture, verification and
/// activation. Existing session locks are held without raw-opening their files.
class LegacyProfileLease {
  LegacyProfileLease._(
    this.root,
    this._profile,
    this._sessions,
    this.locations,
  );
  final String root;
  final ProfileLock _profile;
  final List<ProfileLock> _sessions;
  final List<String> locations;
  bool _closed = false;

  static Future<LegacyProfileLease> acquire(String root) async {
    await _checkLock(root, '$root/profile.lock');
    final profile = await ProfileLock.acquire(root);
    final sessions = <ProfileLock>[];
    final locations = <String>[];
    try {
      final type = await FileSystemEntity.type(
        '$root/spaces',
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw const LocalDatabaseFailure(
          'Legacy spaces directory is linked or invalid; retained.',
        );
      }
      if (type == FileSystemEntityType.directory) {
        final entries = await Directory(
          '$root/spaces',
        ).list(followLinks: false).toList();
        entries.sort((a, b) => a.path.compareTo(b.path));
        for (final entry in entries) {
          final key = entry.uri.pathSegments.lastWhere((p) => p.isNotEmpty);
          if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) continue;
          if (entry is! Directory) {
            throw const LocalDatabaseFailure(
              'Legacy workspace directory is linked or invalid; retained.',
            );
          }
          await _checkLock(root, '${entry.path}/session.lock');
          sessions.add(
            await ProfileLock.acquire(entry.path, fileName: 'session.lock'),
          );
          locations.add(key);
        }
      }
      return LegacyProfileLease._(
        root,
        profile,
        sessions,
        List.unmodifiable(locations),
      );
    } catch (_) {
      for (final session in sessions.reversed) {
        await session.close();
      }
      await profile.close();
      rethrow;
    }
  }

  static Future<void> _checkLock(String root, String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.file ||
        await FileSystemEntity.identical(
          path,
          '$root/${LocalProfileDatabase.fileName}',
        ) ||
        await File(path).length() != 0) {
      throw const LocalDatabaseFailure(
        'Legacy lock is linked, nonempty or aliases the live database; retained.',
      );
    }
  }

  void requireRoot(String expected) {
    if (_closed || root != expected) {
      throw StateError('Migration requires its active legacy profile lease.');
    }
  }

  Future<void> close() async {
    if (_closed) return;
    for (final session in _sessions.reversed) {
      await session.close();
    }
    await _profile.close();
    _closed = true;
  }
}
