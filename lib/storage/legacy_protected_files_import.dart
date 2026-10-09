import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/event.dart';
import 'local_profile_database.dart';
import 'legacy_profile_lease.dart';
import 'profile_text_intents.dart';
import 'writer_guard.dart';

class ProtectedFilesImportResult {
  const ProtectedFilesImportResult(this.importedFiles, this.unmigratedCaches);
  final int importedFiles;

  /// These contain workspace bindings, trusted observations and potentially
  /// outbox-only receipts. This slice neither imports nor deletes them.
  final List<String> unmigratedCaches;
}

/// First opt-in migration slice: settings and protected JSON files only.
/// NOT full profile migration, NOT application activation, and NO cleanup API.
/// Run before using the profile's adapters. The existing profile/session leases
/// span capture, import, readback and verification of the legacy source files.
class LegacyProtectedFilesImport {
  LegacyProtectedFilesImport(this.profile);
  final LocalProfileDatabase profile;

  /// Final inactive-migration gate. No adapters may advance authorities yet,
  /// so every source-backed protected value must still match exact bytes.
  Future<void> verifyCaptured(LegacyProfileLease lease) async {
    lease.requireRoot(profile.root);
    for (final row in profile.database.select(
      'SELECT path,kind,hash FROM migration_file_imports ORDER BY path',
    )) {
      final source = await _read(row['path'] as String, row['kind'] as String);
      if (source.hash != row['hash']) {
        throw const LocalDatabaseFailure(
          'Imported source changed before activation; retained.',
        );
      }
      _verifyBindings(source);
      _verifyImported(source);
    }
  }

  Future<ProtectedFilesImportResult> run({
    void Function()? beforeCommit,
    LegacyProfileLease? lease,
  }) async {
    final ownedLease = lease == null;
    final legacy = lease ?? await LegacyProfileLease.acquire(profile.root);
    legacy.requireRoot(profile.root);
    try {
      final sources = <_Source>[];
      final caches = <String>[];
      sources.add(await _read('settings.json', 'settings'));
      if (await _exists('writer-migration.json')) {
        sources.add(await _read('writer-migration.json', 'marker'));
      }
      final guards = await _directory('writer-guards');
      if (guards != null) {
        await for (final entry in guards.list(followLinks: false)) {
          final leaf = entry.uri.pathSegments.last;
          if (leaf.endsWith('.json')) {
            sources.add(await _read('writer-guards/$leaf', 'guard'));
          }
        }
      }
      final spaces = await _directory('spaces');
      if (spaces != null) {
        await for (final entry in spaces.list(followLinks: false)) {
          final key = entry.uri.pathSegments.lastWhere((p) => p.isNotEmpty);
          if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) continue;
          if (entry is! Directory) {
            throw const LocalDatabaseFailure(
              'A legacy cache path is not a plain directory; retained.',
            );
          }
          if (await _exists('spaces/$key/cache.sqlite')) {
            caches.add('spaces/$key/cache.sqlite');
          }
          if (await _exists('spaces/$key/writer-id')) {
            sources.add(await _read('spaces/$key/writer-id', 'legacy-writer'));
          }
          final intents = await _directory('spaces/$key/text-intents');
          if (intents == null) continue;
          await for (final file in intents.list(followLinks: false)) {
            final leaf = file.uri.pathSegments.last;
            if (leaf.endsWith('.json')) {
              sources.add(
                await _read('spaces/$key/text-intents/$leaf', 'intent'),
              );
            }
          }
        }
      }
      sources.sort((a, b) => a.path.compareTo(b.path));
      final imported = <_Source>[];
      profile.transaction(() {
        final captured = sources.map((s) => s.path).toSet();
        for (final prior in profile.database.select(
          "SELECT path FROM migration_file_imports WHERE kind!='cache'",
        )) {
          if (!captured.contains(prior['path'])) {
            throw const LocalDatabaseFailure(
              'A previously imported legacy source disappeared; retain the database and originals before recovery.',
            );
          }
        }
        for (final source in sources) {
          final old = profile.database.select(
            'SELECT kind,hash FROM migration_file_imports WHERE path=?',
            [source.path],
          );
          if (old.isNotEmpty) {
            if (old.single['kind'] != source.kind ||
                old.single['hash'] != source.hash) {
              throw const LocalDatabaseFailure(
                'A previously imported legacy source changed; both authorities were retained.',
              );
            }
            continue; // Never restore old reservations over subsequent DB state.
          }
          _insert(source);
          profile.database.execute(
            'INSERT INTO migration_file_imports VALUES (?,?,?)',
            [source.path, source.kind, source.hash],
          );
          imported.add(source);
        }
        for (final source in sources) {
          _verifyBindings(source);
          // Complete the known unpublished files-only proof's missing import
          // fences from unchanged retained source evidence, never absent rows.
          if (source.kind == 'settings') {
            profile.database.execute(
              "INSERT OR IGNORE INTO profile_metadata VALUES ('migration.writer',?)",
              [source.writer],
            );
          } else if (source.kind == 'guard') {
            profile.database.execute(
              'INSERT OR IGNORE INTO profile_metadata VALUES (?,?)',
              [
                'migration.guard.${source.space}.${source.writer}',
                utf8.decode(source.bytes),
              ],
            );
          } else if (source.kind == 'intent') {
            final key = ProfileTextIntents.migrationKey(source.event!);
            final prior = profile.database.select(
              'SELECT value FROM profile_metadata WHERE key=?',
              ['migration.intent-source.${source.path}'],
            );
            if (prior.isEmpty) {
              ProfileTextIntents(profile).recordMigrationInTransaction(
                source.event!,
                source.bytes,
                source: source.path,
              );
            }
            if (prior.isNotEmpty && prior.single['value'] != key) {
              throw const LocalDatabaseFailure(
                'Imported source intent binding differs; retained.',
              );
            }
          }
        }
        profile.database.execute(
          "INSERT INTO profile_metadata VALUES ('migration.protected-files','pending-verification') ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        );
        beforeCommit?.call();
      });
      // Verify through SQLite, never raw-open/read/hash the live profile DB.
      if (profile.database
              .select('PRAGMA integrity_check')
              .single
              .values
              .single !=
          'ok') {
        throw const LocalDatabaseFailure(
          'Local import integrity verification failed; originals were retained.',
        );
      }
      for (final source in sources) {
        final current = await _read(source.path, source.kind);
        if (current.hash != source.hash) {
          throw const LocalDatabaseFailure(
            'A legacy source changed during verification; originals were retained.',
          );
        }
      }
      for (final source in sources) {
        _verifyBindings(source);
        if (imported.contains(source)) _verifyImported(source);
      }
      profile.transaction(() {
        profile.database.execute(
          "UPDATE profile_metadata SET value='verified-files-only' WHERE key='migration.protected-files'",
        );
      });
      caches.sort();
      return ProtectedFilesImportResult(
        imported.length,
        List.unmodifiable(caches),
      );
    } finally {
      if (ownedLease) await legacy.close();
    }
  }

  Future<bool> _exists(String path) async =>
      await FileSystemEntity.type(
        '${profile.root}/$path',
        followLinks: false,
      ) !=
      FileSystemEntityType.notFound;

  Future<Directory?> _directory(String path) async {
    final full = '${profile.root}/$path';
    final type = await FileSystemEntity.type(full, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.directory) {
      throw const LocalDatabaseFailure(
        'A legacy directory is linked or invalid; retained.',
      );
    }
    return Directory(full);
  }

  Future<_Source> _read(String path, String kind) async {
    final full = '${profile.root}/$path';
    if (await FileSystemEntity.type(full, followLinks: false) !=
            FileSystemEntityType.file ||
        await FileSystemEntity.identical(
          full,
          '${profile.root}/${LocalProfileDatabase.fileName}',
        )) {
      throw const LocalDatabaseFailure(
        'A legacy source is missing, linked or aliases the live database; retained.',
      );
    }
    final file = File(full);
    if (await file.length() > 16 * 1024 * 1024) {
      throw const LocalDatabaseFailure('Oversized legacy source; retained.');
    }
    final source = _Source(path, kind, await file.readAsBytes());
    final raw = utf8.decode(source.bytes);
    switch (kind) {
      case 'settings':
        final data = jsonDecode(raw);
        if (data is! Map<String, dynamic> ||
            !isCanonicalId(data['writer']) ||
            (data['folder'] != null && data['folder'] is! String) ||
            (data['user'] != null && data['user'] is! String) ||
            (data['appearance'] != null &&
                !{'system', 'light', 'dark'}.contains(data['appearance']))) {
          throw const LocalDatabaseFailure(
            'Legacy settings authority is invalid or requires an earlier identity migration; retained.',
          );
        }
        source.writer = data['writer'] as String;
      case 'marker':
        if (raw != '{"v":1}') {
          throw const LocalDatabaseFailure(
            'Invalid legacy writer marker; retained.',
          );
        }
      case 'legacy-writer':
        if (!isCanonicalId(raw.trim())) {
          throw const LocalDatabaseFailure(
            'Invalid legacy writer identity; retained.',
          );
        }
      case 'guard':
        final parts = path.split('/').last.split('.');
        if (parts.length != 3 || parts[2] != 'json') {
          throw const LocalDatabaseFailure(
            'Invalid legacy guard filename; retained.',
          );
        }
        decodeWriterGuardState(source.bytes, parts[0], parts[1]);
        source.space = parts[0];
        source.writer = parts[1];
      case 'intent':
        final event = LogEvent.decode(raw);
        if (!nativeTextIntentTypes.contains(event.type) ||
            path.split('/').last != '${event.writer}-${event.sequence}.json') {
          throw const LocalDatabaseFailure(
            'Invalid legacy text intent binding; retained.',
          );
        }
        source.event = event;
      default:
        throw StateError('Unknown protected-file import kind');
    }
    return source;
  }

  void _insert(_Source source) {
    final db = profile.database;
    switch (source.kind) {
      case 'settings':
        _insertExact(
          'SELECT raw FROM protected_settings WHERE singleton=1',
          [],
          source,
          () => db.execute('INSERT INTO protected_settings VALUES (1,?,?)', [
            source.writer,
            source.bytes,
          ]),
        );
        db.execute(
          "INSERT INTO profile_metadata VALUES ('migration.writer',?)",
          [source.writer],
        );
      case 'guard':
        _insertExact(
          'SELECT raw FROM protected_writer_guards WHERE space=? AND writer=?',
          [source.space, source.writer],
          source,
          () => db.execute(
            'INSERT INTO protected_writer_guards VALUES (?,?,?)',
            [source.space, source.writer, source.bytes],
          ),
        );
        db.execute('INSERT INTO profile_metadata VALUES (?,?)', [
          'migration.guard.${source.space}.${source.writer}',
          utf8.decode(source.bytes),
        ]);
      case 'intent':
        final event = source.event!;
        _insertExact(
          'SELECT raw FROM protected_text_intents WHERE space=? AND writer=? AND sequence=?',
          [event.space, event.writer, event.sequence],
          source,
          () => db.execute(
            'INSERT INTO protected_text_intents VALUES (?,?,?,?,?,?)',
            [
              event.space,
              event.writer,
              event.sequence,
              event.id,
              event.entity,
              source.bytes,
            ],
          ),
        );
        ProfileTextIntents(profile).recordMigrationInTransaction(
          event,
          source.bytes,
          source: source.path,
        );
    }
  }

  void _insertExact(
    String query,
    List<Object?> arguments,
    _Source source,
    void Function() insert,
  ) {
    final existing = profile.database.select(query, arguments);
    if (existing.isEmpty) {
      insert();
    } else if (sha256.convert(existing.single['raw'] as List<int>).toString() !=
        source.hash) {
      throw const LocalDatabaseFailure(
        'Protected import conflicts with existing database authority; originals were retained.',
      );
    }
  }

  void _verifyImported(_Source source) {
    List<int>? bytes;
    switch (source.kind) {
      case 'settings':
        bytes =
            profile.database
                    .select(
                      'SELECT raw FROM protected_settings WHERE singleton=1',
                    )
                    .single['raw']
                as List<int>;
      case 'guard':
        bytes =
            profile.database.select(
                  'SELECT raw FROM protected_writer_guards WHERE space=? AND writer=?',
                  [source.space, source.writer],
                ).single['raw']
                as List<int>;
      case 'intent':
        final event = source.event!;
        bytes =
            profile.database.select(
                  'SELECT raw FROM protected_text_intents WHERE space=? AND writer=? AND sequence=?',
                  [event.space, event.writer, event.sequence],
                ).single['raw']
                as List<int>;
    }
    if (bytes != null && sha256.convert(bytes).toString() != source.hash) {
      throw const LocalDatabaseFailure(
        'Protected import readback differs; originals were retained.',
      );
    }
  }

  void _verifyBindings(_Source source) {
    final db = profile.database;
    switch (source.kind) {
      case 'settings':
        final rows = db.select(
          'SELECT writer,raw FROM protected_settings WHERE singleton=1',
        );
        if (rows.length != 1) {
          throw const LocalDatabaseFailure(
            'Imported settings authority is missing; retained.',
          );
        }
        final raw = jsonDecode(utf8.decode(rows.single['raw'] as List<int>));
        if (raw is! Map ||
            !isCanonicalId(raw['writer']) ||
            raw['writer'] != rows.single['writer'] ||
            raw['writer'] != source.writer) {
          throw const LocalDatabaseFailure(
            'Imported settings writer binding differs; retained.',
          );
        }
      case 'guard':
        final rows = db.select(
          'SELECT raw FROM protected_writer_guards WHERE space=? AND writer=?',
          [source.space, source.writer],
        );
        if (rows.length != 1) {
          throw const LocalDatabaseFailure(
            'Imported writer guard is missing; retained.',
          );
        }
        // Validate current authority without rolling later acknowledgements
        // backwards to a previously imported legacy reservation snapshot.
        final current = decodeWriterGuardState(
          rows.single['raw'] as List<int>,
          source.space!,
          source.writer!,
        );
        final previous = decodeWriterGuardState(
          source.bytes,
          source.space!,
          source.writer!,
        );
        verifyImportedGuardProgress(current, previous);
      case 'intent':
        final event = source.event!;
        final raw = ProfileTextIntents(
          profile,
        ).atSequence(event.space, event.writer, event.sequence);
        if (raw == null || sha256.convert(raw).toString() != source.hash) {
          throw const LocalDatabaseFailure(
            'Imported exact text intent is missing or differs; retained.',
          );
        }
    }
  }
}

void verifyImportedGuardProgress(
  WriterGuardState current,
  WriterGuardState previous,
) {
  if (current.sequence < previous.sequence ||
      (current.sequence == previous.sequence &&
          current.hash != previous.hash)) {
    throw const LocalDatabaseFailure(
      'Imported writer guard regressed from retained authority; retained.',
    );
  }
  final pending = {
    for (final record in current.pending) record.sequence: record.hash,
  };
  for (final record in previous.pending) {
    if ((record.sequence == current.sequence && current.hash != record.hash) ||
        (record.sequence > current.sequence &&
            pending[record.sequence] != record.hash)) {
      throw const LocalDatabaseFailure(
        'Imported writer guard lost or changed a retained reservation; retained.',
      );
    }
  }
}

class _Source {
  _Source(this.path, this.kind, this.bytes)
    : hash = sha256.convert(bytes).toString();
  final String path, kind, hash;
  final Uint8List bytes;
  String? writer, space;
  LogEvent? event;
}
