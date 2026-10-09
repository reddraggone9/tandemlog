import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../domain/event.dart';
import 'legacy_cache_import.dart';
import 'legacy_profile_lease.dart';
import 'legacy_protected_files_import.dart';
import 'local_durability.dart';
import 'local_profile_database.dart';
import 'local_settings.dart';
import 'profile_text_intents.dart';
import 'writer_guard.dart';

typedef MigrationCheckpoint =
    FutureOr<void> Function(String boundary, String? path);

/// Bootstrap before adapters exist. The active marker commits only after all
/// known local authorities have been imported and read back. Cleanup records
/// make unlink and directory barriers resumable without reopening old stores.
class LocalProfileMigration {
  LocalProfileMigration(this.profile);
  final LocalProfileDatabase profile;

  Future<void> run({
    MigrationCheckpoint? checkpoint,
  }) => profile.serialize(() async {
    Future<void> point(String name, [String? path]) async {
      await checkpoint?.call(name, path);
    }

    var phase = _phase;
    if (phase != null && !{'importing', 'active', 'complete'}.contains(phase)) {
      throw const LocalDatabaseFailure(
        'Unrecognized profile migration state; retained.',
      );
    }
    if (phase != 'active' && phase != 'complete') {
      _setPhase('importing');
      await point('import.started');
      final settingsType = await _type('settings.json');
      final legacyPresent =
          settingsType != FileSystemEntityType.notFound ||
          await _type('spaces') != FileSystemEntityType.notFound ||
          await _type('writer-guards') != FileSystemEntityType.notFound ||
          await _type('profile.lock') != FileSystemEntityType.notFound ||
          await _type('writer-migration.json') != FileSystemEntityType.notFound;
      LegacyProfileLease? lease;
      try {
        if (legacyPresent) {
          lease = await LegacyProfileLease.acquire(profile.root);
          await _prepareLegacySettings(lease);
          await LegacyProtectedFilesImport(profile).run(lease: lease);
          await point('files.imported');
          await LegacyCacheImport(profile).run(lease: lease);
          await point('caches.imported');
          await _plan(lease);
        } else {
          if (profile.database
              .select(
                'SELECT 1 FROM migration_file_imports UNION ALL SELECT 1 FROM protected_cache_imports LIMIT 1',
              )
              .isNotEmpty) {
            throw const LocalDatabaseFailure(
              'Previously imported legacy sources disappeared before activation; retained.',
            );
          }
          if (profile.database
              .select('SELECT 1 FROM protected_settings')
              .isEmpty) {
            final writer = const Uuid().v4();
            profile.transaction(() {
              profile.database.execute(
                'INSERT INTO protected_settings VALUES (1,?,?)',
                [
                  writer,
                  utf8.encode(
                    jsonEncode({
                      'writer': writer,
                      'folder': null,
                      'user': null,
                      'appearance': 'system',
                    }),
                  ),
                ],
              );
              profile.database.execute(
                "INSERT INTO profile_metadata VALUES ('migration.writer',?)",
                [writer],
              );
            });
          }
          await point('files.imported');
          await point('caches.imported');
        }
        await point('cleanup.planned');
        if (lease != null) {
          await LegacyProtectedFilesImport(profile).verifyCaptured(lease);
        }
        _verifyTarget(beforeActivation: true);
        for (final row in profile.database.select(
          'SELECT path,kind,hash FROM migration_cleanup ORDER BY path',
        )) {
          await _verifySource(
            row['path'] as String,
            row['kind'] as String,
            row['hash'] as String,
            heldLocks: lease != null,
          );
        }
        await point('sources.verified');
        await point('activation.before');
        // Recheck immediately before committing activation, including any
        // external disturbance during the test/diagnostic boundary.
        _verifyTarget(beforeActivation: true);
        if (lease != null) {
          await LegacyProtectedFilesImport(profile).verifyCaptured(lease);
          await LegacyCacheImport(profile).run(lease: lease);
        }
        _verifyTarget(beforeActivation: true);
        for (final row in profile.database.select(
          'SELECT path,kind,hash FROM migration_cleanup ORDER BY path',
        )) {
          await _verifySource(
            row['path'] as String,
            row['kind'] as String,
            row['hash'] as String,
            heldLocks: lease != null,
          );
        }
        _setPhase('active');
        phase = 'active';
        await point('activation.committed');
      } finally {
        await lease?.close();
      }
    }
    _verifyTarget();
    for (final row in profile.database.select(
      'SELECT path,kind,hash,state FROM migration_cleanup ORDER BY path',
    )) {
      final path = row['path'] as String,
          kind = row['kind'] as String,
          hash = row['hash'] as String;
      _allow(path, kind);
      final exists = await _type(path) != FileSystemEntityType.notFound;
      if (!exists && row['state'] == 'ready') {
        throw const LocalDatabaseFailure(
          'A legacy source disappeared before its cleanup record; retained.',
        );
      }
      if (exists) await _verifySource(path, kind, hash);
      if (row['state'] == 'deleted' && !exists) continue;
      profile.transaction(
        () => profile.database.execute(
          "UPDATE migration_cleanup SET state='deleting' WHERE path=?",
          [path],
        ),
      );
      await point('cleanup.marked', path);
      _verifyTarget(integrity: false);
      if (exists) {
        await _verifySource(path, kind, hash);
        await File('${profile.root}/$path').delete();
      }
      await point('cleanup.deleted', path);
      await syncParentAfterCreate(File('${profile.root}/$path'));
      profile.transaction(
        () => profile.database.execute(
          "UPDATE migration_cleanup SET state='deleted' WHERE path=?",
          [path],
        ),
      );
      await point('cleanup.committed', path);
    }
    _verifyTarget();
    _setPhase('complete');
    await point('cleanup.finished');
  });

  String? get _phase {
    final rows = profile.database.select(
      "SELECT value FROM profile_metadata WHERE key='migration.profile'",
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  void _setPhase(String value) => profile.transaction(
    () => profile.database.execute(
      "INSERT INTO profile_metadata VALUES ('migration.profile',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
      [value],
    ),
  );
  Future<FileSystemEntityType> _type(String path) =>
      FileSystemEntity.type('${profile.root}/$path', followLinks: false);

  Future<void> _prepareLegacySettings(LegacyProfileLease lease) async {
    final file = File('${profile.root}/settings.json');
    Map<String, dynamic> values;
    if (await _type('settings.json') == FileSystemEntityType.notFound) {
      // A missing installation authority cannot safely be inferred from a
      // pending outbox or old cache writer. Preserve all evidence for recovery.
      if (lease.locations.isNotEmpty ||
          await _type('writer-guards') != FileSystemEntityType.notFound) {
        throw const LocalDatabaseFailure(
          'Legacy settings are missing alongside workspace evidence; retained.',
        );
      }
      values = {};
    } else {
      await _plain('settings.json');
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const LocalDatabaseFailure('Invalid legacy settings; retained.');
      }
      values = decoded;
    }
    if (values.containsKey('writer')) {
      return; // Import performs full validation.
    }
    if (await _type('settings.json.tmp') != FileSystemEntityType.notFound) {
      throw const LocalDatabaseFailure(
        'Unresolved legacy settings replacement; retained.',
      );
    }
    final marker = await _type('writer-migration.json');
    String? writer;
    if (marker == FileSystemEntityType.notFound) {
      final identities = <String, String>{};
      for (final key in lease.locations) {
        final path = 'spaces/$key/writer-id';
        if (await _type(path) == FileSystemEntityType.notFound) continue;
        await _plain(path);
        final id = (await File('${profile.root}/$path').readAsString()).trim();
        if (!isCanonicalId(id)) {
          throw const LocalDatabaseFailure(
            'Invalid legacy writer identity; retained.',
          );
        }
        identities[key] = id;
      }
      final folder = values['folder'];
      if (folder is String) {
        writer = identities[sha256.convert(utf8.encode(folder)).toString()];
      }
      if (writer == null && identities.isNotEmpty) {
        writer = identities[identities.keys.first];
      }
    } else {
      await _plain('writer-migration.json');
      if (await File('${profile.root}/writer-migration.json').readAsString() !=
          '{"v":1}') {
        throw const LocalDatabaseFailure(
          'Invalid legacy writer marker; retained.',
        );
      }
    }
    values['writer'] = writer ?? const Uuid().v4();
    await writeAtomicDurable(file, utf8.encode(jsonEncode(values)));
    if (marker == FileSystemEntityType.notFound) {
      await writeAtomicDurable(
        File('${profile.root}/writer-migration.json'),
        utf8.encode('{"v":1}'),
      );
    }
  }

  Future<void> _plan(LegacyProfileLease lease) async {
    final planned = <String, ({String kind, String hash})>{};
    Future<void> add(String path, String kind, {String? expected}) async {
      _allow(path, kind);
      final hash = await _fingerprint(path, kind, heldLocks: true);
      if (expected != null && hash != expected) {
        throw const LocalDatabaseFailure(
          'Imported source changed before cleanup planning; retained.',
        );
      }
      planned[path] = (kind: kind, hash: hash);
    }

    for (final row in profile.database.select(
      'SELECT path,kind,hash FROM migration_file_imports',
    )) {
      final path = row['path'] as String;
      await add(path, row['kind'] as String, expected: row['hash'] as String);
      if (await _type('$path.tmp') != FileSystemEntityType.notFound) {
        await add('$path.tmp', 'temporary', expected: row['hash'] as String);
      }
    }
    final caches = profile.database
        .select('SELECT path FROM protected_cache_imports')
        .map((r) => r['path'] as String)
        .toSet();
    for (final path in caches) {
      await add(path, 'cache');
      for (final suffix in ['-wal', '-shm', '-journal']) {
        if (await _type('$path$suffix') != FileSystemEntityType.notFound) {
          await add('$path$suffix', 'cache-sidecar');
        }
      }
    }
    await add('profile.lock', 'lock');
    for (final key in lease.locations) {
      await add('spaces/$key/session.lock', 'lock');
      await for (final entry in Directory(
        '${profile.root}/spaces/$key',
      ).list(followLinks: false)) {
        final leaf = entry.uri.pathSegments.last;
        if (RegExp(r'^cache.*\.sqlite-(wal|shm|journal)$').hasMatch(leaf)) {
          final main =
              'spaces/$key/${leaf.replaceFirst(RegExp(r'-(wal|shm|journal)$'), '')}';
          if (!caches.contains(main)) {
            throw const LocalDatabaseFailure(
              'Orphan legacy cache recovery sidecar; retained.',
            );
          }
        }
      }
    }
    // Temporary authorities with no accounted original must never be ignored.
    final dirs = [
      '',
      'writer-guards',
      for (final key in lease.locations) 'spaces/$key/text-intents',
    ];
    for (final dir in dirs) {
      if (dir.isNotEmpty && await _type(dir) == FileSystemEntityType.notFound) {
        continue;
      }
      if (dir.isNotEmpty &&
          await _type(dir) != FileSystemEntityType.directory) {
        throw const LocalDatabaseFailure(
          'Linked legacy authority directory; retained.',
        );
      }
      await for (final entry in Directory(
        '${profile.root}${dir.isEmpty ? '' : '/$dir'}',
      ).list(followLinks: false)) {
        final leaf = entry.uri.pathSegments.last;
        final path = dir.isEmpty ? leaf : '$dir/$leaf';
        if (leaf.endsWith('.tmp') &&
            (dir.isNotEmpty ||
                {
                  'settings.json.tmp',
                  'writer-migration.json.tmp',
                }.contains(leaf)) &&
            !planned.containsKey(path)) {
          throw const LocalDatabaseFailure(
            'Unaccounted legacy authority replacement; retained.',
          );
        }
      }
    }
    profile.transaction(() {
      for (final row in profile.database.select(
        'SELECT path FROM migration_cleanup',
      )) {
        if (!planned.containsKey(row['path'])) {
          throw const LocalDatabaseFailure(
            'A planned cleanup source disappeared; retained.',
          );
        }
      }
      for (final entry in planned.entries) {
        final prior = profile.database.select(
          'SELECT kind,hash FROM migration_cleanup WHERE path=?',
          [entry.key],
        );
        if (prior.isNotEmpty &&
            (prior.single['kind'] != entry.value.kind ||
                prior.single['hash'] != entry.value.hash)) {
          throw const LocalDatabaseFailure(
            'Cleanup source changed after planning; retained.',
          );
        }
        profile.database.execute(
          "INSERT OR IGNORE INTO migration_cleanup VALUES (?,?,?,'ready')",
          [entry.key, entry.value.kind, entry.value.hash],
        );
      }
    });
  }

  void _verifyTarget({bool beforeActivation = false, bool integrity = true}) {
    if (integrity &&
        profile.database
                .select('PRAGMA integrity_check')
                .single
                .values
                .single !=
            'ok') {
      throw const LocalDatabaseFailure(
        'Profile integrity verification failed; retained.',
      );
    }
    final writer = LocalSettings.protectedValues(profile)['writer'];
    final identity = profile.database.select(
      "SELECT value FROM profile_metadata WHERE key='migration.writer'",
    );
    if (identity.length != 1 || identity.single['value'] != writer) {
      throw const LocalDatabaseFailure(
        'Installation writer differs from its migration authority; retained.',
      );
    }
    ProfileTextIntents(profile).verifyMigration();
    for (final row in profile.database.select(
      "SELECT path,hash FROM migration_file_imports WHERE kind='intent'",
    )) {
      final source = profile.database.select(
        'SELECT value FROM profile_metadata WHERE key=?',
        ['migration.intent-source.${row['path']}'],
      );
      if (source.length != 1 ||
          !(source.single['value'] as String).startsWith('migration.intent.') ||
          profile.database.select(
                'SELECT 1 FROM profile_metadata WHERE key=? AND value=?',
                [source.single['value'], row['hash']],
              ).length !=
              1) {
        throw const LocalDatabaseFailure(
          'Imported private intent obligation is missing; retained.',
        );
      }
    }
    for (final row in profile.database.select(
      "SELECT path FROM migration_cleanup WHERE kind='cache'",
    )) {
      if (profile.database.select(
            'SELECT 1 FROM protected_cache_imports WHERE path=?',
            [row['path']],
          ).length !=
          1) {
        throw const LocalDatabaseFailure(
          'Imported cache evidence is missing; retained.',
        );
      }
    }
    for (final row in profile.database.select(
      'SELECT * FROM protected_writer_guards',
    )) {
      decodeWriterGuardState(
        row['raw'] as List<int>,
        row['space'] as String,
        row['writer'] as String,
      );
    }
    for (final row in profile.database.select(
      "SELECT path,hash FROM migration_file_imports WHERE kind='guard'",
    )) {
      final parts = (row['path'] as String).split('/').last.split('.');
      if (parts.length != 3 ||
          profile.database.select(
                'SELECT 1 FROM protected_writer_guards WHERE space=? AND writer=?',
                [parts[0], parts[1]],
              ).length !=
              1) {
        throw const LocalDatabaseFailure(
          'Imported writer authority is missing; retained.',
        );
      }
      final baseline = profile.database.select(
        'SELECT value FROM profile_metadata WHERE key=?',
        ['migration.guard.${parts[0]}.${parts[1]}'],
      );
      if (baseline.length != 1 ||
          sha256
                  .convert(utf8.encode(baseline.single['value'] as String))
                  .toString() !=
              row['hash']) {
        throw const LocalDatabaseFailure(
          'Imported guard baseline is missing or differs; retained.',
        );
      }
      final current =
          profile.database.select(
                'SELECT raw FROM protected_writer_guards WHERE space=? AND writer=?',
                [parts[0], parts[1]],
              ).single['raw']
              as List<int>;
      verifyImportedGuardProgress(
        decodeWriterGuardState(current, parts[0], parts[1]),
        decodeWriterGuardState(
          utf8.encode(baseline.single['value'] as String),
          parts[0],
          parts[1],
        ),
      );
    }
    for (final row in profile.database.select(
      'SELECT DISTINCT space,writer FROM protected_text_intents',
    )) {
      ProfileTextIntents(
        profile,
      ).pending(row['space'] as String, row['writer'] as String);
      if (beforeActivation && row['writer'] != writer) {
        throw const LocalDatabaseFailure(
          'Pending legacy receipts use another installation writer; retained for recovery.',
        );
      }
    }
    for (final row in profile.database.select(
      'SELECT * FROM protected_cache_imports',
    )) {
      final raw = row['raw'] as List<int>,
          snapshot = LegacyCacheSnapshot.decode(raw);
      if (sha256.convert(raw).toString() != row['hash'] ||
          snapshot.path != row['path'] ||
          snapshot.location != row['location'] ||
          snapshot.space != row['space']) {
        throw const LocalDatabaseFailure(
          'Imported cache evidence binding differs; retained.',
        );
      }
      for (final pending in snapshot.outbox) {
        final event = LogEvent.decode(pending),
            expected = profile.database.select(
              'SELECT value FROM profile_metadata WHERE key=?',
              [ProfileTextIntents.migrationKey(event)],
            );
        if (expected.length != 1 ||
            expected.single['value'] !=
                sha256.convert(utf8.encode(pending)).toString()) {
          throw const LocalDatabaseFailure(
            'Imported cache-only intent obligation is missing; retained.',
          );
        }
      }
    }
  }

  void _allow(String path, String kind) {
    final key = r'[a-f0-9]{64}',
        id = r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}';
    final cache = 'spaces/$key/(cache\\.sqlite|cache-v[0-9]+-$id\\.sqlite)';
    final authority =
        '(settings\\.json|writer-migration\\.json|writer-guards/$id\\.$id\\.json|spaces/$key/writer-id|spaces/$key/text-intents/$id-[0-9]+\\.json)';
    final valid = switch (kind) {
      'settings' => path == 'settings.json',
      'marker' => path == 'writer-migration.json',
      'guard' => RegExp('^writer-guards/$id\\.$id\\.json\$').hasMatch(path),
      'legacy-writer' => RegExp('^spaces/$key/writer-id\$').hasMatch(path),
      'intent' => RegExp(
        '^spaces/$key/text-intents/$id-[0-9]+\\.json\$',
      ).hasMatch(path),
      'temporary' => RegExp('^$authority\\.tmp\$').hasMatch(path),
      'cache' => RegExp('^$cache\$').hasMatch(path),
      'cache-sidecar' => RegExp('^$cache-(wal|shm|journal)\$').hasMatch(path),
      'lock' =>
        path == 'profile.lock' ||
            RegExp('^spaces/$key/session\\.lock\$').hasMatch(path),
      _ => false,
    };
    if (!valid) {
      throw const LocalDatabaseFailure(
        'Cleanup path is outside the exact legacy allowlist; retained.',
      );
    }
  }

  Future<void> _plain(String path) async {
    var parent = '';
    final pieces = path.split('/');
    for (final piece in pieces.take(pieces.length - 1)) {
      parent = parent.isEmpty ? piece : '$parent/$piece';
      if (await _type(parent) != FileSystemEntityType.directory) {
        throw const LocalDatabaseFailure(
          'Legacy source parent is linked or missing; retained.',
        );
      }
    }
    final full = '${profile.root}/$path';
    if (await _type(path) != FileSystemEntityType.file ||
        await FileSystemEntity.identical(
          full,
          '${profile.root}/${LocalProfileDatabase.fileName}',
        )) {
      throw const LocalDatabaseFailure(
        'Legacy source is linked, missing or aliases the live database; retained.',
      );
    }
  }

  Future<String> _fingerprint(
    String path,
    String kind, {
    bool heldLocks = false,
  }) async {
    await _plain(path);
    if (kind == 'lock' && heldLocks) {
      if (await File('${profile.root}/$path').length() != 0) {
        throw const LocalDatabaseFailure('Legacy lock changed; retained.');
      }
      return sha256.convert([]).toString();
    }
    return (await sha256.bind(File('${profile.root}/$path').openRead()).first)
        .toString();
  }

  Future<void> _verifySource(
    String path,
    String kind,
    String hash, {
    bool heldLocks = false,
  }) async {
    _allow(path, kind);
    if (await _fingerprint(path, kind, heldLocks: heldLocks) != hash) {
      throw const LocalDatabaseFailure(
        'Legacy cleanup source changed; retained.',
      );
    }
  }
}
