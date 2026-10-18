import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/task_tables.dart';
import 'unified_conversion_test.dart' as fixture;

void main() {
  test(
    'conversion proves current prefixes/ranges and retained backup receipts',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'unified-observation-proof-',
      );
      final profile = await LocalProfileDatabase.open('${root.path}/profile');
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      TaskStore? store;
      try {
        await folder.create(
          'tandemlog-space.json',
          Uint8List.fromList(
            utf8.encode(jsonEncode({'v': 3, 'id': fixture.space})),
          ),
        );
        final original = {
          for (final e in fixture.sources().entries.where(
            (e) => e.key.endsWith('.jsonl'),
          ))
            e.key: Uint8List.fromList(e.value),
        };
        final peerEvent = LogEvent(
          fixture.space,
          fixture.peer,
          1,
          EventClock(BigInt.from(3000000000)),
          '55555555-5555-4555-8555-555555555555',
          'user.created',
          {'name': 'Original peer'},
        );
        original['${fixture.peer}.jsonl'] = Uint8List.fromList(
          utf8.encode('${peerEvent.encode()}\n'),
        );
        for (final e in original.entries) {
          await folder.create(e.key, e.value);
        }
        store = await TaskStore.open(
          folder,
          profile.root,
          profileDatabase: profile,
          writerIdentity: fixture.owner,
        );
        await store.close();
        store = null;
        await TaskStore.verifyConvertedHistoryObservations(
          profile,
          fixture.space,
          original,
        );
        final location = sha256
            .convert(utf8.encode(folder.location))
            .toString();
        final tables = TaskTables.forLocation(location);
        final db = profile.database;
        final snapshot = {
          'v': 1,
          'path':
              'spaces/$location/cache-v16-77777777-7777-4777-8777-777777777777.sqlite',
          'location': location,
          'space': fixture.space,
          'version': 16,
          'metadata': {
            for (final r in db.select('SELECT * FROM ${tables.metadata}'))
              r['key'] as String: r['value'] as String,
          },
          'streams': db
              .select('SELECT * FROM ${tables.streams}')
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
          'ranges': db
              .select('SELECT * FROM ${tables.streamRanges}')
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
          'events': db
              .select('SELECT raw FROM ${tables.events}')
              .map((r) => r['raw'])
              .toList(),
          'outbox': <String>[],
        };
        final raw = utf8.encode(jsonEncode(snapshot));
        profile.transaction(
          () => db.execute(
            'INSERT INTO protected_cache_imports VALUES (?,?,?,?,?)',
            [
              snapshot['path'],
              location,
              fixture.space,
              raw,
              sha256.convert(raw).toString(),
            ],
          ),
        );
        await TaskStore.verifyConvertedHistoryObservations(
          profile,
          fixture.space,
          original,
        );
        final observations = db
            .select('SELECT * FROM ${tables.streams}')
            .map((r) => r.toString())
            .toList();
        final fork = LogEvent(
          fixture.space,
          fixture.peer,
          1,
          peerEvent.clock,
          peerEvent.entity,
          'user.created',
          {'name': 'Different peer'},
        );
        await expectLater(
          TaskStore.verifyConvertedHistoryObservations(profile, fixture.space, {
            ...original,
            '${fixture.peer}.jsonl': Uint8List.fromList(
              utf8.encode('${fork.encode()}\n'),
            ),
          }),
          throwsA(anyOf(isA<LocalDatabaseFailure>(), isA<FormatFailure>())),
        );
        await expectLater(
          TaskStore.verifyConvertedHistoryObservations(profile, fixture.space, {
            '${fixture.owner}.jsonl': original['${fixture.owner}.jsonl']!,
          }),
          throwsA(anyOf(isA<LocalDatabaseFailure>(), isA<FormatFailure>())),
        );
        // Even after disposable projections are emptied for replay, immutable
        // backup observations must prevent accepting a divergent old source.
        profile.transaction(() {
          db.execute('DELETE FROM ${tables.events}');
          db.execute('DELETE FROM ${tables.streamRanges}');
          db.execute('DELETE FROM ${tables.streams}');
        });
        await expectLater(
          TaskStore.verifyConvertedHistoryObservations(profile, fixture.space, {
            ...original,
            '${fixture.peer}.jsonl': Uint8List.fromList(
              utf8.encode('${fork.encode()}\n'),
            ),
          }),
          throwsA(anyOf(isA<LocalDatabaseFailure>(), isA<FormatFailure>())),
        );
        expect(observations, isNotEmpty);
        expect(
          db.select('SELECT raw FROM protected_cache_imports').single['raw'],
          raw,
        );
      } finally {
        await store?.close();
        await profile.close();
        await root.delete(recursive: true);
      }
    },
  );
}
