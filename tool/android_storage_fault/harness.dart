import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_profile_migration.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/profile_text_intents.dart';

const faultSource = String.fromEnvironment('STORAGE_FAULT_SOURCE');
const cuts = <String>{
  'import.started',
  'files.imported',
  'caches.imported',
  'cleanup.planned',
  'sources.verified',
  'activation.before',
  'activation.committed',
  'cleanup.marked',
  'cleanup.deleted',
  'cleanup.committed',
  'cleanup.finished',
};
const writer = '00000000-0000-4000-8000-000000000001';
const user = '00000000-0000-4000-8000-000000000002';
const task = '00000000-0000-4000-8000-000000000003';
const intentSpace = '00000000-0000-4000-8000-000000000007';

String bytesHash(List<int> bytes) => sha256.convert(bytes).toString();
Future<void> durableJson(File file, Object value) =>
    file.writeAsString(jsonEncode(value), flush: true).then((_) {});

Map<String, dynamic> validateControl(Object? value) {
  if (value is! Map<String, dynamic> ||
      value.keys.any((key) => !{'case', 'mode', 'cut'}.contains(key)) ||
      value['case'] is! String ||
      !RegExp(r'^[a-z0-9][a-z0-9-]{0,39}$').hasMatch(value['case'] as String) ||
      !{'cut', 'seed-held', 'resume', 'sql-full'}.contains(value['mode']) ||
      (value['mode'] == 'cut' && !cuts.contains(value['cut']))) {
    throw ArgumentError('Expected safe case, mode and an exact supported cut.');
  }
  return value;
}

Future<Map<String, String>> canonicalHashes(Directory root) async {
  final result = <String, String>{};
  await for (final file in root.list(followLinks: false)) {
    if (file is! File) throw StateError('Unexpected canonical source type.');
    result[file.uri.pathSegments.last] = bytesHash(await file.readAsBytes());
  }
  return result;
}

Future<Map<String, dynamic>> seedFixture(
  Directory root, {
  bool hold = false,
}) async {
  if (root.existsSync()) {
    throw StateError('Refusing to replace retained fixture.');
  }
  await root.create(recursive: true);
  final canonical = await Directory('${root.path}/canonical').create();
  final private = await Directory('${root.path}/profile').create();
  final settings = utf8.encode(
    jsonEncode({
      'writer': writer,
      'folder': canonical.path,
      'user': user,
      'appearance': 'dark',
    }),
  );
  await File(
    '${private.path}/settings.json',
  ).writeAsBytes(settings, flush: true);
  await File(
    '${private.path}/writer-migration.json',
  ).writeAsString('{"v":1}', flush: true);
  final location = bytesHash(utf8.encode(canonical.path));
  final guard = FileWriterGuard(private.path);
  final store = await TaskStore.open(
    LocalLogFolder(canonical.path),
    '${private.path}/spaces/$location',
    writerIdentity: writer,
    writerGuard: guard,
  );
  await store.command(user, 'user.created', {'name': 'Synthetic fault user'});
  await store.command(task, 'task.created', {
    'title': 'Retained fault task',
    'description': '',
    'assignee': user,
  });
  final head = (await guard.load(store.space, writer))!;
  await guard.prepare(store.space, writer, head.sequence, head.hash, [
    PreparedWriterRecord(head.sequence + 1, 'a' * 64),
  ]);
  final intent = Uint8List.fromList(
    utf8.encode(
      LogEvent(
        intentSpace,
        writer,
        1,
        EventClock(BigInt.one),
        task,
        'task.textEdited',
        {
          'changes': {
            'title': {
              'context': 'a' * 64,
              'allocation': '00000000-0000-4000-8000-000000000005',
              'actor': 42,
              'update': base64Encode([0, 0]),
            },
          },
        },
      ).encode(),
    ),
  );
  final intents = await Directory(
    '${private.path}/spaces/${'e' * 64}/text-intents',
  ).create(recursive: true);
  await File(
    '${intents.path}/$writer-1.json',
  ).writeAsBytes(intent, flush: true);
  await File(
    '${private.path}/unknown.txt',
  ).writeAsString('retain synthetic unknown', flush: true);
  final guardFile = File(
    '${private.path}/writer-guards/${store.space}.$writer.json',
  );
  final expected = <String, dynamic>{
    'source': faultSource,
    'writer': writer,
    'space': store.space,
    'location': location,
    'canonical': await canonicalHashes(canonical),
    'settingsSha256': bytesHash(settings),
    'guardSha256': bytesHash(await guardFile.readAsBytes()),
    'guardSequence': head.sequence,
    'guardHash': head.hash,
    'pendingGuardSequence': head.sequence + 1,
    'pendingGuardHash': 'a' * 64,
    'intentBase64': base64Encode(intent),
    'intentSha256': bytesHash(intent),
    'trustedStreams': store.db
        .select('SELECT * FROM streams ORDER BY name')
        .map((row) => Map<String, dynamic>.from(row))
        .toList(),
    'trustedRanges': store.db
        .select('SELECT * FROM stream_ranges ORDER BY name,start_offset')
        .map((row) => Map<String, dynamic>.from(row))
        .toList(),
    'acceptedEvents': store.db
        .select('SELECT raw FROM events ORDER BY writer,seq')
        .map((row) => row['raw'])
        .toList(),
    'outboxEvents': store.db
        .select('SELECT raw FROM text_outbox ORDER BY id')
        .map((row) => row['raw'])
        .toList(),
  };
  await durableJson(File('${root.path}/expected.json'), expected);
  if (hold) {
    Timer.periodic(
      const Duration(seconds: 1),
      (_) => store.db.select('SELECT 1'),
    );
    await durableJson(File('${root.path}/ready.json'), {
      'source': faultSource,
      'pid': pid,
      'boundary': 'legacy-wal',
      'root': root.path,
      'sqliteVersion': store.db
          .select('SELECT sqlite_version() AS v')
          .single['v'],
      'walExists': File(
        '${private.path}/spaces/$location/cache.sqlite-wal',
      ).existsSync(),
    });
    await Completer<void>().future;
  }
  await store.close();
  return expected;
}

Object jsonSqlValue(Object? value) => value is List<int>
    ? {'base64': base64Encode(value), 'sha256': bytesHash(value)}
    : value ?? 'NULL';
List<Map<String, Object>> query(LocalProfileDatabase profile, String sql) =>
    profile.database
        .select(sql)
        .map((row) => {for (final key in row.keys) key: jsonSqlValue(row[key])})
        .toList();

Map<String, dynamic> sqlSnapshot(LocalProfileDatabase profile) => {
  'sqliteVersion': query(profile, 'SELECT sqlite_version() AS version'),
  'metadata': query(
    profile,
    'SELECT key,value FROM profile_metadata ORDER BY key',
  ),
  'settings': query(profile, 'SELECT writer,raw FROM protected_settings'),
  'guards': query(
    profile,
    'SELECT space,writer,raw FROM protected_writer_guards ORDER BY space,writer',
  ),
  'intents': query(
    profile,
    'SELECT space,writer,sequence,id,entity,raw FROM protected_text_intents ORDER BY space,writer,sequence',
  ),
  'cacheImports': query(
    profile,
    'SELECT path,location,space,raw,hash FROM protected_cache_imports ORDER BY path',
  ),
  'cleanup': query(
    profile,
    'SELECT path,kind,hash,state FROM migration_cleanup ORDER BY path',
  ),
};

Future<Map<String, dynamic>> runFaultCase(
  Directory documents,
  Object? rawControl, {
  void Function(String)? progress,
}) async {
  final control = validateControl(rawControl);
  final root = Directory(
    '${documents.path}/storage-fault-cases/${control['case']}',
  );
  final mode = control['mode'];
  if (mode == 'seed-held') {
    progress?.call(
      'Preparing committed legacy WAL; wait for ready.json before force-stop.',
    );
    await seedFixture(root, hold: true);
    throw StateError('Held fixture unexpectedly returned.');
  }
  if (!root.existsSync()) {
    if (mode != 'cut') {
      throw StateError('Resume requires the retained fixture.');
    }
    await seedFixture(root);
  }
  final priorMarker = File('${root.path}/ready.json');
  if (mode == 'cut' && priorMarker.existsSync()) {
    final prior = jsonDecode(await priorMarker.readAsString());
    if (prior['boundary'] != 'legacy-wal') {
      throw StateError(
        'A migration cut requires a fresh case; retained markers are not replaced.',
      );
    }
  }
  final expected =
      jsonDecode(await File('${root.path}/expected.json').readAsString())
          as Map<String, dynamic>;
  if (expected['source'] != faultSource) {
    throw StateError('Fixture source differs.');
  }
  if (mode != 'cut') {
    final ready = jsonDecode(
      await File('${root.path}/ready.json').readAsString(),
    );
    if (ready['source'] != faultSource ||
        ready['root'] != root.path ||
        !(cuts.contains(ready['boundary']) ||
            ready['boundary'] == 'legacy-wal') ||
        ready['pid'] == pid) {
      throw StateError('Missing exact migration cut marker.');
    }
  }
  final profile = await LocalProfileDatabase.open('${root.path}/profile');
  late Map<String, dynamic> report;
  try {
    await LocalProfileMigration(profile).run(
      checkpoint: (boundary, path) async {
        if (mode == 'cut' && boundary == control['cut']) {
          await durableJson(File('${root.path}/ready.json'), {
            'source': faultSource,
            'pid': pid,
            'boundary': boundary,
            'path': path,
            'root': root.path,
            'sql': sqlSnapshot(profile),
          });
          progress?.call('READY $boundary pid=$pid root=${root.path}');
          Timer.periodic(
            const Duration(seconds: 1),
            (_) => profile.database.select('SELECT 1'),
          );
          await Completer<void>().future;
        }
      },
    );
    if (mode == 'cut') {
      throw StateError(
        'Requested cut was not reached; no passing death proof.',
      );
    }
    final settings = profile.database
        .select('SELECT writer,raw FROM protected_settings')
        .single;
    if (settings['writer'] != writer ||
        bytesHash(settings['raw'] as List<int>) != expected['settingsSha256']) {
      throw StateError('Protected settings/writer changed.');
    }
    final guard = (await SqliteWriterGuard(
      profile,
    ).load(expected['space'] as String, writer))!;
    final guardRaw =
        profile.database.select(
              'SELECT raw FROM protected_writer_guards WHERE space=? AND writer=?',
              [expected['space'], writer],
            ).single['raw']
            as List<int>;
    if (bytesHash(guardRaw) != expected['guardSha256'] ||
        guard.sequence != expected['guardSequence'] ||
        guard.hash != expected['guardHash'] ||
        guard.pending.length != 1 ||
        guard.pending.single.sequence != expected['pendingGuardSequence'] ||
        guard.pending.single.hash != expected['pendingGuardHash']) {
      throw StateError('Guard evidence changed.');
    }
    ProfileTextIntents(profile).verifyMigration();
    final cacheRows = profile.database.select(
      'SELECT raw FROM protected_cache_imports WHERE location=? AND space=?',
      [expected['location'], expected['space']],
    );
    if (cacheRows.length != 1) {
      throw StateError('Expected exact primary cache import.');
    }
    final importedCache = jsonDecode(
      utf8.decode(cacheRows.single['raw'] as List<int>),
    );
    for (final entry in {
      'streams': 'trustedStreams',
      'ranges': 'trustedRanges',
      'events': 'acceptedEvents',
      'outbox': 'outboxEvents',
    }.entries) {
      if (jsonEncode(importedCache[entry.key]) !=
          jsonEncode(expected[entry.value])) {
        throw StateError(
          'Imported cache ${entry.key} differs from owned legacy observations.',
        );
      }
    }
    final pending = ProfileTextIntents(profile).pending(intentSpace, writer);
    if (pending.length != 1 ||
        base64Encode(pending.single) != expected['intentBase64']) {
      throw StateError('Exact pending bytes changed or disappeared.');
    }
    final currentCanonical = await canonicalHashes(
      Directory('${root.path}/canonical'),
    );
    final expectedCanonical = expected['canonical'] as Map<String, dynamic>;
    if (currentCanonical.length != expectedCanonical.length ||
        currentCanonical.entries.any(
          (entry) => expectedCanonical[entry.key] != entry.value,
        )) {
      throw StateError('Canonical bytes changed.');
    }
    if (await File('${profile.root}/unknown.txt').readAsString() !=
            'retain synthetic unknown' ||
        profile.database
            .select("SELECT 1 FROM migration_cleanup WHERE state!='deleted'")
            .isNotEmpty ||
        profile.database
            .select('SELECT 1 FROM protected_cache_imports')
            .isEmpty) {
      throw StateError('Cleanup/import/unknown-file obligations failed.');
    }
    int? injectedSqlCode;
    if (mode == 'sql-full') {
      final pages = profile.database
          .select('PRAGMA page_count')
          .single
          .values
          .single;
      profile.database.execute('PRAGMA max_page_count=$pages');
      try {
        profile.transaction(() {
          profile.database.execute('CREATE TABLE synthetic_full (raw BLOB)');
          profile.database.execute(
            'INSERT INTO synthetic_full VALUES (zeroblob(1000000))',
          );
        });
        throw StateError('Expected SQL capacity failure.');
      } on SqliteException catch (error) {
        injectedSqlCode = error.resultCode;
        if (injectedSqlCode != 13 ||
            !profile.database.autocommit ||
            base64Encode(
                  ProfileTextIntents(
                    profile,
                  ).pending(intentSpace, writer).single,
                ) !=
                expected['intentBase64'] ||
            profile.database
                .select(
                  "SELECT name FROM sqlite_master WHERE name='synthetic_full'",
                )
                .isNotEmpty) {
          throw StateError(
            'SQL capacity rollback did not preserve pending evidence.',
          );
        }
      }
    }
    report = <String, dynamic>{
      'passed': true,
      'source': faultSource,
      'pid': pid,
      'root': root.path,
      'mode': mode,
      'cutMarker': jsonDecode(
        await File('${root.path}/ready.json').readAsString(),
      ),
      'sql': sqlSnapshot(profile),
      'canonical': await canonicalHashes(Directory('${root.path}/canonical')),
      'pendingExact': true,
      'guardExact': true,
      'writerExact': true,
      'trustedObservationsAndAcceptedEventsExact': true,
      'injectedSqlResultCode': injectedSqlCode,
      'limits':
          'External worker must prove prior PID exit. File-flushed marker is not a power-loss/directory-barrier proof. No SAF or installed production app evidence.',
    };
  } finally {
    await profile.close();
  }
  report['profileClosed'] = true;
  await durableJson(File('${root.path}/report.json'), report);
  return report;
}
