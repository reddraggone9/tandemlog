import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import '../domain/event.dart';
import 'legacy_profile_lease.dart';
import 'local_profile_database.dart';
import 'log_folder.dart';
import 'profile_text_intents.dart';

/// Immutable source observations, separate for every primary/backup cache.
/// Native projections are disposable; accepted raw records, trusted prefixes,
/// ranges, bindings, local preferences and outbox-only receipts are accounted.
class LegacyCacheSnapshot {
  LegacyCacheSnapshot._(this.data) {
    try {
      _validate();
    } on LocalDatabaseFailure {
      rethrow;
    } catch (_) {
      throw const LocalDatabaseFailure(
        'Invalid legacy cache snapshot; retained.',
      );
    }
  }
  factory LegacyCacheSnapshot.decode(List<int> raw) => LegacyCacheSnapshot._(
    jsonDecode(utf8.decode(raw)) as Map<String, dynamic>,
  );
  final Map<String, dynamic> data;
  String get path => data['path'] as String;
  String get location => data['location'] as String;
  String get space => data['space'] as String;
  int get version => data['version'] as int;
  bool get primary => path.endsWith('/cache.sqlite');
  Map<String, dynamic> get metadata => data['metadata'] as Map<String, dynamic>;
  List<Map<String, dynamic>> get streams => (data['streams'] as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
  List<Map<String, dynamic>> get ranges => (data['ranges'] as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
  List<String> get events => List<String>.from(data['events'] as List);
  List<String> get outbox => List<String>.from(data['outbox'] as List);
  bool get replayPending => metadata['replay_pending'] == '1';
  Uint8List get raw => Uint8List.fromList(utf8.encode(jsonEncode(data)));

  static final _hash = RegExp(r'^[a-f0-9]{64}$');
  static final _location = RegExp(r'^[a-f0-9]{64}$');
  static final cacheName = RegExp(
    r'^cache(?:-v([1-9][0-9]*)-([0-9a-f-]{36}))?\.sqlite$',
  );
  void _validate() {
    if (data.length != 10 ||
        data['v'] != 1 ||
        !_location.hasMatch(location) ||
        path.split('/').length != 3 ||
        path.split('/')[0] != 'spaces' ||
        path.split('/')[1] != location ||
        !cacheName.hasMatch(path.split('/').last) ||
        !isCanonicalId(space) ||
        version < 1 ||
        version > 16 ||
        metadata['space'] != space) {
      throw const LocalDatabaseFailure(
        'Invalid legacy cache identity/schema; retained.',
      );
    }
    final records = <String, LogEvent>{};
    final byWriter = <String, List<LogEvent>>{};
    for (final raw in events) {
      final event = LogEvent.decode(raw);
      if (event.space != space || records.containsKey(event.id)) {
        throw const LocalDatabaseFailure(
          'Legacy cache event binding conflicts; retained.',
        );
      }
      records[event.id] = event;
      (byWriter[event.writer] ??= []).add(event);
    }
    for (final entries in byWriter.values) {
      entries.sort((a, b) => a.sequence.compareTo(b.sequence));
      var seq = 0, previous = eventGenesisHash(space, entries.first.writer);
      for (final event in entries) {
        if (event.sequence != ++seq || event.previousHash != previous) {
          throw const LocalDatabaseFailure(
            'Legacy cache record chain is incomplete or conflicting; retained.',
          );
        }
        previous = event.hash!;
      }
    }
    final names = <String>{};
    for (final row in streams) {
      final name = row['name'];
      if (name is! String ||
          !name.endsWith('.jsonl') ||
          !isCanonicalId(name.substring(0, name.length - 6)) ||
          !names.add(name) ||
          row['offset'] is! int ||
          (row['offset'] as int) < 0 ||
          row['hash'] is! String ||
          !_hash.hasMatch(row['hash'] as String) ||
          row['stamp'] is! String) {
        throw const LocalDatabaseFailure(
          'Invalid trusted legacy stream observation; retained.',
        );
      }
      final baseline = row['hash_offset'] ?? row['offset'];
      if (baseline is! int ||
          baseline < 0 ||
          baseline > (row['offset'] as int) ||
          !{0, 1}.contains(row['range_capable'] ?? 0)) {
        throw const LocalDatabaseFailure(
          'Invalid trusted legacy prefix; retained.',
        );
      }
      var covered = baseline;
      final chunks = ranges.where((r) => r['name'] == name).toList()
        ..sort(
          (a, b) =>
              (a['start_offset'] as int).compareTo(b['start_offset'] as int),
        );
      for (final chunk in chunks) {
        if (chunk['start_offset'] != covered ||
            chunk['end_offset'] is! int ||
            (chunk['end_offset'] as int) <= covered ||
            (chunk['end_offset'] as int) > (row['offset'] as int) ||
            chunk['hash'] is! String ||
            !_hash.hasMatch(chunk['hash'] as String)) {
          throw const LocalDatabaseFailure(
            'Incomplete trusted legacy ranges; retained.',
          );
        }
        covered = chunk['end_offset'] as int;
      }
      if (covered != row['offset']) {
        throw const LocalDatabaseFailure(
          'Incomplete trusted legacy ranges; retained.',
        );
      }
      final writer = name.substring(0, name.length - 6),
          cached = byWriter[writer] ?? [];
      final seq = row['last_seq'] ?? cached.length;
      if (seq is! int ||
          seq < 0 ||
          (replayPending ? seq < cached.length : seq != cached.length) ||
          (row['chain_head'] != null &&
              (row['chain_head'] is! String ||
                  !_hash.hasMatch(row['chain_head'] as String))) ||
          (row['chain_head'] != null &&
              (!replayPending || seq == cached.length) &&
              row['chain_head'] !=
                  (cached.isEmpty
                      ? eventGenesisHash(space, writer)
                      : cached.last.hash)) ||
          (row['last_clock'] != null &&
              (!replayPending || seq == cached.length) &&
              row['last_clock'] !=
                  (cached.isEmpty ? null : cached.last.clock.value.toInt()))) {
        throw const LocalDatabaseFailure(
          'Legacy cache head differs from accepted records; retained.',
        );
      }
    }
    if (ranges.any((r) => !names.contains(r['name'])) ||
        byWriter.keys.any((w) => !names.contains('$w.jsonl'))) {
      throw const LocalDatabaseFailure(
        'Legacy cache records/ranges lack stream bindings; retained.',
      );
    }
    final pending = <String>{};
    for (final raw in outbox) {
      final event = LogEvent.decode(raw);
      if (event.space != space ||
          !nativeTextIntentTypes.contains(event.type) ||
          !pending.add(event.id) ||
          (records.containsKey(event.id) &&
              records[event.id]!.canonicalRaw != raw)) {
        throw const LocalDatabaseFailure(
          'Invalid legacy outbox-only receipt; retained.',
        );
      }
    }
  }

  List<Map<String, dynamic>> get normalizedStreams {
    final records = events.map(LogEvent.decode).toList();
    return [
      for (final row in streams)
        {
          ...row,
          'hash_offset': row['hash_offset'] ?? row['offset'],
          'range_capable': row['range_capable'] ?? 0,
          'last_seq':
              row['last_seq'] ??
              records.where((e) => '${e.writer}.jsonl' == row['name']).length,
          'chain_head':
              row['chain_head'] ??
              _lastRecord(records, row['name'] as String)?.hash ??
              (replayPending && row['offset'] != 0
                  ? null
                  : eventGenesisHash(
                      space,
                      (row['name'] as String).substring(
                        0,
                        (row['name'] as String).length - 6,
                      ),
                    )),
          'last_clock':
              row['last_clock'] ??
              _lastRecord(records, row['name'] as String)?.clock.value.toInt(),
        },
    ];
  }

  static LogEvent? _lastRecord(List<LogEvent> records, String name) {
    final found = records.where((e) => '${e.writer}.jsonl' == name).toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    return found.isEmpty ? null : found.last;
  }

  /// Verify every retained observation, including backups/aliases, before a
  /// location becomes writable. A later current checkpoint supersedes these
  /// lower bounds only after this exact-byte admission succeeds.
  Future<void> verifyCanonical(LogFolder folder) async {
    for (final row in normalizedStreams) {
      final bytes = await folder.read(row['name'] as String);
      final offset = row['offset'] as int, baseline = row['hash_offset'] as int;
      if (bytes.length < offset ||
          sha256
                  .convert(Uint8List.sublistView(bytes, 0, baseline))
                  .toString() !=
              row['hash']) {
        throw const LocalDatabaseFailure(
          'Canonical history differs from a retained legacy observation; retained.',
        );
      }
      for (final range in ranges.where((r) => r['name'] == row['name'])) {
        if (sha256
                .convert(
                  Uint8List.sublistView(
                    bytes,
                    range['start_offset'] as int,
                    range['end_offset'] as int,
                  ),
                )
                .toString() !=
            range['hash']) {
          throw const LocalDatabaseFailure(
            'Canonical history differs from a retained legacy range; retained.',
          );
        }
      }
      final saved =
          events
              .map(LogEvent.decode)
              .where((e) => '${e.writer}.jsonl' == row['name'])
              .toList()
            ..sort((a, b) => a.sequence.compareTo(b.sequence));
      var cursor = 0;
      for (final event in saved) {
        final raw = utf8.encode('${event.canonicalRaw}\n');
        if (cursor + raw.length > offset) {
          throw const LocalDatabaseFailure(
            'Legacy receipts exceed their trusted prefix; retained.',
          );
        }
        for (var i = 0; i < raw.length; i++) {
          if (bytes[cursor + i] != raw[i]) {
            throw const LocalDatabaseFailure(
              'Canonical bytes differ from retained accepted receipts; retained.',
            );
          }
        }
        cursor += raw.length;
      }
      if (!replayPending && cursor != offset) {
        throw const LocalDatabaseFailure(
          'Legacy receipts do not cover their trusted prefix; retained.',
        );
      }
      var count = 0;
      EventClock? clock;
      var head = eventGenesisHash(
        space,
        (row['name'] as String).substring(
          0,
          (row['name'] as String).length - 6,
        ),
      );
      final prefix = utf8.decode(Uint8List.sublistView(bytes, 0, offset));
      if (offset > 0 && !prefix.endsWith('\n')) {
        throw const LocalDatabaseFailure(
          'Trusted prefix does not end at a complete record; retained.',
        );
      }
      for (final raw in prefix.split('\n').where((raw) => raw.isNotEmpty)) {
        final event = LogEvent.decode(raw);
        if (event.space != space ||
            '${event.writer}.jsonl' != row['name'] ||
            event.sequence != ++count ||
            event.previousHash != head ||
            (clock != null && event.clock <= clock)) {
          throw const LocalDatabaseFailure(
            'Canonical trusted-prefix chain differs; retained.',
          );
        }
        head = event.hash!;
        clock = event.clock;
      }
      if (row['chain_head'] != null &&
          (row['chain_head'] != head ||
              row['last_seq'] != count ||
              row['last_clock'] != clock?.value.toInt())) {
        throw const LocalDatabaseFailure(
          'Canonical history differs from a retained trusted head; retained.',
        );
      }
    }
  }
}

class LegacyCacheImport {
  LegacyCacheImport(this.profile);
  final LocalProfileDatabase profile;
  Future<int> run({
    LegacyProfileLease? lease,
    void Function()? beforeCommit,
  }) async {
    final owned = lease == null,
        held = lease ?? await LegacyProfileLease.acquire(profile.root);
    held.requireRoot(profile.root);
    try {
      final snapshots = <LegacyCacheSnapshot>[];
      for (final key in held.locations) {
        final entries = await Directory(
          '${profile.root}/spaces/$key',
        ).list(followLinks: false).toList();
        entries.sort((a, b) => a.path.compareTo(b.path));
        for (final entry in entries) {
          final leaf = entry.uri.pathSegments.last;
          if (leaf.startsWith('cache-v') &&
              leaf.endsWith('.sqlite') &&
              !LegacyCacheSnapshot.cacheName.hasMatch(leaf)) {
            throw const LocalDatabaseFailure(
              'Unrecognized legacy cache backup name; retained.',
            );
          }
          if (!LegacyCacheSnapshot.cacheName.hasMatch(leaf)) continue;
          snapshots.add(await capture('spaces/$key/$leaf', key));
        }
      }
      var imported = 0;
      profile.transaction(() {
        final paths = snapshots.map((s) => s.path).toSet();
        for (final prior in profile.database.select(
          'SELECT path FROM protected_cache_imports',
        )) {
          if (!paths.contains(prior['path'])) {
            throw const LocalDatabaseFailure(
              'A previously captured legacy cache disappeared; retained.',
            );
          }
        }
        for (final snapshot in snapshots) {
          final bytes = snapshot.raw, hash = sha256.convert(bytes).toString();
          final prior = profile.database.select(
            'SELECT location,space,raw,hash FROM protected_cache_imports WHERE path=?',
            [snapshot.path],
          );
          if (prior.isNotEmpty) {
            if (prior.single['location'] != snapshot.location ||
                prior.single['space'] != snapshot.space ||
                prior.single['hash'] != hash ||
                sha256.convert(prior.single['raw'] as List<int>).toString() !=
                    hash) {
              throw const LocalDatabaseFailure(
                'Legacy cache changed or target evidence differs; retained.',
              );
            }
          } else {
            if (profile.database.select(
              'SELECT 1 FROM protected_cache_imports WHERE location=? AND space!=?',
              [snapshot.location, snapshot.space],
            ).isNotEmpty) {
              throw const LocalDatabaseFailure(
                'Legacy location has conflicting space bindings; retained.',
              );
            }
            profile.database.execute(
              'INSERT INTO protected_cache_imports VALUES (?,?,?,?,?)',
              [snapshot.path, snapshot.location, snapshot.space, bytes, hash],
            );
            for (final raw in snapshot.outbox) {
              final event = LogEvent.decode(raw);
              ProfileTextIntents(profile).stageInTransaction(
                event.space,
                event.writer,
                Uint8List.fromList(utf8.encode(raw)),
              );
              ProfileTextIntents(
                profile,
              ).recordMigrationInTransaction(event, utf8.encode(raw));
            }
            imported++;
          }
        }
        beforeCommit?.call();
      });
      // Read back via SQL and a second committed source snapshot. SQLite's
      // read transaction includes WAL state; no raw-open of either live DB.
      for (final snapshot in snapshots) {
        final again = await capture(snapshot.path, snapshot.location);
        final saved = profile.database.select(
          'SELECT raw,hash FROM protected_cache_imports WHERE path=?',
          [snapshot.path],
        ).single;
        if (sha256.convert(again.raw).toString() != saved['hash'] ||
            sha256.convert(saved['raw'] as List<int>).toString() !=
                saved['hash']) {
          throw const LocalDatabaseFailure(
            'Legacy cache verification changed; retained.',
          );
        }
        LegacyCacheSnapshot.decode(saved['raw'] as List<int>);
        for (final raw in snapshot.outbox) {
          final event = LogEvent.decode(raw),
              target = ProfileTextIntents(
                profile,
              ).atSequence(event.space, event.writer, event.sequence);
          if ((target == null && !_confirmed(event)) ||
              (target != null && utf8.decode(target) != raw)) {
            throw const LocalDatabaseFailure(
              'Cache-only receipt readback differs; retained.',
            );
          }
        }
      }
      return imported;
    } finally {
      if (owned) await held.close();
    }
  }

  bool _confirmed(LogEvent event) {
    final rows = profile.database.select(
      'SELECT value FROM profile_metadata WHERE key=?',
      ['migration.retired.${event.space}.${event.writer}.${event.sequence}'],
    );
    return rows.length == 1 &&
        rows.single['value'] ==
            sha256.convert(utf8.encode(event.canonicalRaw!)).toString();
  }

  Future<LegacyCacheSnapshot> capture(String path, String key) async {
    final full = '${profile.root}/$path';
    if (await FileSystemEntity.type(full, followLinks: false) !=
            FileSystemEntityType.file ||
        await FileSystemEntity.identical(
          full,
          '${profile.root}/${LocalProfileDatabase.fileName}',
        )) {
      throw const LocalDatabaseFailure(
        'Legacy cache is linked or aliases the live DB; retained.',
      );
    }
    final source = sqlite3.open(full, mode: OpenMode.readOnly);
    try {
      source.execute('BEGIN');
      if (source.select('PRAGMA integrity_check').single.values.single !=
          'ok') {
        throw const LocalDatabaseFailure(
          'Legacy cache integrity failed; retained.',
        );
      }
      final version =
          source.select('PRAGMA user_version').single.values.single as int;
      if (version < 1 || version > 16) {
        throw const LocalDatabaseFailure(
          'Unsupported legacy cache version; retained.',
        );
      }
      final leaf = path.split('/').last,
          name = LegacyCacheSnapshot.cacheName.firstMatch(leaf)!;
      if (name.group(1) != null &&
          (int.parse(name.group(1)!) != version ||
              !isCanonicalId(name.group(2)))) {
        throw const LocalDatabaseFailure(
          'Legacy backup version/name differs; retained.',
        );
      }
      final metadata = {
        for (final row in source.select(
          'SELECT key,value FROM metadata ORDER BY key',
        ))
          row['key'] as String: row['value'],
      };
      final knownTables = {
        'events',
        'views',
        'streams',
        'stream_ranges',
        'metadata',
        'positions',
        'text_fields',
        'text_actors',
        'text_outbox',
      };
      for (final row in source.select(
        "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      )) {
        if (!knownTables.contains(row['name'])) {
          throw const LocalDatabaseFailure(
            'Legacy cache contains unaccounted tables; retained.',
          );
        }
      }
      final space = metadata['space'];
      final events = <String>[];
      final hasEvents = source
          .select(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='events'",
          )
          .isNotEmpty;
      if (!hasEvents && metadata['replay_pending'] != '1') {
        throw const LocalDatabaseFailure(
          'Legacy accepted receipt table is missing; retained.',
        );
      }
      for (final row
          in (hasEvents
              ? source.select(
                  'SELECT id,entity,writer,seq,clock,raw FROM events ORDER BY writer,seq',
                )
              : <Row>[])) {
        final raw = row['raw'] as String, event = LogEvent.decode(raw);
        if (event.id != row['id'] ||
            event.entity != row['entity'] ||
            event.writer != row['writer'] ||
            event.sequence != row['seq'] ||
            event.clock.value.toInt() != row['clock'] ||
            event.space != space) {
          throw const LocalDatabaseFailure(
            'Legacy indexed receipt binding differs; retained.',
          );
        }
        events.add(raw);
      }
      bool table(String name) => source.select(
        "SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?",
        [name],
      ).isNotEmpty;
      if (version >= 13 && !table('text_outbox')) {
        throw const LocalDatabaseFailure(
          'Legacy native outbox table is missing; retained.',
        );
      }
      final outbox = <String>[];
      if (table('text_outbox')) {
        for (final row in source.select(
          'SELECT id,entity,raw FROM text_outbox ORDER BY id',
        )) {
          final raw = row['raw'] as String, event = LogEvent.decode(raw);
          if (event.id != row['id'] || event.entity != row['entity']) {
            throw const LocalDatabaseFailure(
              'Legacy outbox indexed identity differs; retained.',
            );
          }
          outbox.add(raw);
        }
      }
      final result = LegacyCacheSnapshot._({
        'v': 1,
        'path': path,
        'location': key,
        'space': space,
        'version': version,
        'metadata': metadata,
        'streams': source
            .select('SELECT * FROM streams ORDER BY name')
            .map((r) => Map<String, dynamic>.from(r))
            .toList(),
        'ranges': table('stream_ranges')
            ? source
                  .select(
                    'SELECT * FROM stream_ranges ORDER BY name,start_offset',
                  )
                  .map((r) => Map<String, dynamic>.from(r))
                  .toList()
            : [],
        'events': events,
        'outbox': outbox,
      });
      source.execute('COMMIT');
      return result;
    } finally {
      source.close();
    }
  }
}
