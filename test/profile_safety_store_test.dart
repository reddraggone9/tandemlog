import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/profile_text_intents.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';

const space = '00000000-0000-4000-8000-000000000001';
const writer = '00000000-0000-4000-8000-000000000002';
const entity = '00000000-0000-4000-8000-000000000003';
const otherSpace = '00000000-0000-4000-8000-000000000004';

Uint8List intentBytes([String workspace = space]) => Uint8List.fromList(
  utf8.encode(
    LogEvent(
      workspace,
      writer,
      1,
      EventClock(BigInt.one),
      entity,
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

void main() {
  late Directory root;
  late LocalProfileDatabase profile;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-profile-safety-');
    profile = await LocalProfileDatabase.open(root.path);
  });
  tearDown(() async {
    await profile.close();
    await root.delete(recursive: true);
  });

  test(
    'writer reservation and partial acknowledgement survive reopening',
    () async {
      final guard = SqliteWriterGuard(profile);
      await guard.prepare(space, writer, 0, eventGenesisHash(space, writer), [
        PreparedWriterRecord(1, 'a' * 64),
        PreparedWriterRecord(2, 'b' * 64),
      ]);
      await guard.acknowledge(space, writer, 1, 'a' * 64);
      await profile.close();
      profile = await LocalProfileDatabase.open(root.path);
      final restored = await SqliteWriterGuard(profile).load(space, writer);
      expect(restored!.sequence, 1);
      expect(restored.hash, 'a' * 64);
      expect(restored.pending.single.sequence, 2);
      expect(restored.pending.single.hash, 'b' * 64);
      await expectLater(
        SqliteWriterGuard(profile).prepare(space, writer, 1, 'a' * 64, [
          PreparedWriterRecord(2, 'c' * 64),
        ]),
        throwsA(isA<WriterGuardFailure>()),
      );
      await expectLater(
        SqliteWriterGuard(profile).acknowledge(space, writer, 2, 'c' * 64),
        throwsA(isA<WriterGuardFailure>()),
      );
      await SqliteWriterGuard(profile).acknowledge(space, writer, 2, 'b' * 64);
    },
  );

  test(
    'same writer and event sequence are scoped to separate workspaces',
    () async {
      final guard = SqliteWriterGuard(profile);
      for (final workspace in [space, otherSpace]) {
        await guard.prepare(
          workspace,
          writer,
          0,
          eventGenesisHash(workspace, writer),
          [PreparedWriterRecord(1, workspace == space ? 'a' * 64 : 'b' * 64)],
        );
        ProfileTextIntents(
          profile,
        ).stage(workspace, writer, intentBytes(workspace));
      }
      expect((await guard.load(space, writer))!.pending.single.hash, 'a' * 64);
      expect(
        (await guard.load(otherSpace, writer))!.pending.single.hash,
        'b' * 64,
      );
      expect(
        ProfileTextIntents(profile).pending(space, writer).single,
        intentBytes(),
      );
      expect(
        ProfileTextIntents(profile).pending(otherSpace, writer).single,
        intentBytes(otherSpace),
      );
    },
  );

  test('pending canonical bytes are immutable and survive reopen', () async {
    final raw = intentBytes();
    final intents = ProfileTextIntents(profile);
    intents.stage(space, writer, raw);
    intents.stage(space, writer, raw);
    // Same event meaning/hash with different whitespace is different intent
    // evidence. Never silently normalize a previously staged receipt.
    expect(
      () => intents.stage(space, writer, Uint8List.fromList([...raw, 10])),
      throwsA(isA<FormatFailure>()),
    );
    expect(
      () => intents.stage(otherSpace, writer, raw),
      throwsA(isA<FormatFailure>()),
    );
    await profile.close();
    profile = await LocalProfileDatabase.open(root.path);
    expect(ProfileTextIntents(profile).pending(space, writer).single, raw);
  });

  test(
    'rollback and projection deletion do not clear protected evidence',
    () async {
      final guard = SqliteWriterGuard(profile);
      await guard.prepare(space, writer, 0, eventGenesisHash(space, writer), [
        PreparedWriterRecord(1, 'a' * 64),
      ]);
      ProfileTextIntents(profile).stage(space, writer, intentBytes());
      final db = profile.database;
      db.execute('CREATE TABLE proof_projection (raw TEXT)');
      db.execute("INSERT INTO proof_projection VALUES ('derived')");
      expect(
        () => profile.transaction(() {
          db.execute('DELETE FROM protected_writer_guards');
          throw StateError('injected before commit');
        }),
        throwsStateError,
      );
      db.execute('DROP TABLE proof_projection');
      expect((await guard.load(space, writer))!.pending.single.sequence, 1);
      expect(
        ProfileTextIntents(profile).pending(space, writer).single,
        intentBytes(),
      );
    },
  );

  test(
    'a SQL disk-capacity failure preserves original error and pending rows',
    () async {
      ProfileTextIntents(profile).stage(space, writer, intentBytes());
      final db = profile.database;
      final pages = db.select('PRAGMA page_count').single.values.single;
      db.execute('PRAGMA max_page_count=$pages');
      expect(
        () => profile.transaction(() {
          db.execute('CREATE TABLE large_proof (raw BLOB)');
          db.execute('INSERT INTO large_proof VALUES (zeroblob(1000000))');
        }),
        throwsA(
          isA<SqliteException>().having((e) => e.resultCode, 'SQLITE_FULL', 13),
        ),
      );
      expect(db.autocommit, isTrue);
      expect(
        ProfileTextIntents(profile).pending(space, writer).single,
        intentBytes(),
      );
    },
  );

  test(
    'copied writer IDs across profiles are outside profile exclusion',
    () async {
      final second = await LocalProfileDatabase.open('${root.path}/second');
      try {
        // This exposes the pre-existing installation-identity contract: neither
        // the old private lock nor a new DB lease is a shared writer append lock.
        for (final local in [profile, second]) {
          await SqliteWriterGuard(local).prepare(
            space,
            writer,
            0,
            eventGenesisHash(space, writer),
            [PreparedWriterRecord(1, local == profile ? 'a' * 64 : 'b' * 64)],
          );
        }
        expect(
          (await SqliteWriterGuard(
            profile,
          ).load(space, writer))!.pending.single.hash,
          isNot(
            (await SqliteWriterGuard(
              second,
            ).load(space, writer))!.pending.single.hash,
          ),
        );
      } finally {
        await second.close();
      }
    },
  );
  test(
    'distinct profile writers converge in one canonical workspace',
    () async {
      final secondProfile = await LocalProfileDatabase.open(
        '${root.path}/second',
      );
      await Directory('${root.path}/shared').create();
      final shared = LocalLogFolder('${root.path}/shared');
      TaskStore? first, second;
      try {
        first = await TaskStore.open(
          shared,
          '${root.path}/cache-first',
          writerIdentity: writer,
          writerGuard: SqliteWriterGuard(profile),
        );
        second = await TaskStore.open(
          shared,
          '${root.path}/cache-second',
          writerIdentity: otherSpace,
          writerGuard: SqliteWriterGuard(secondProfile),
        );
        await first.command(writer, 'user.created', {'name': 'Synthetic user'});
        await second.refresh();
        await first.command(entity, 'task.created', {
          'title': 'First',
          'description': '',
          'assignee': writer,
        });
        await second.command(
          '00000000-0000-4000-8000-000000000006',
          'task.created',
          {'title': 'Second', 'description': '', 'assignee': writer},
        );
        await first.refresh();
        await second.refresh();
        expect(
          first.rows
              .where((row) => row['kind'] == 'task')
              .map((row) => row['title'])
              .toSet(),
          {'First', 'Second'},
        );
        expect(
          second.rows
              .where((row) => row['kind'] == 'task')
              .map((row) => row['title'])
              .toSet(),
          {'First', 'Second'},
        );
        expect(
          (await SqliteWriterGuard(
            profile,
          ).load(first.space, writer))!.sequence,
          2,
        );
        expect(
          (await SqliteWriterGuard(
            secondProfile,
          ).load(second.space, otherSpace))!.sequence,
          1,
        );
      } finally {
        await first?.close();
        await second?.close();
        await secondProfile.close();
      }
    },
  );

  test('async and nested transactions cannot commit unrelated outer work', () {
    var started = false;
    expect(
      () => profile.transaction(() async {
        started = true;
      }),
      throwsArgumentError,
    );
    expect(started, isFalse);
    profile.transaction(() {
      expect(() => profile.transaction(() {}), throwsA(isA<SqliteException>()));
      expect(profile.database.autocommit, isFalse);
    });
    expect(profile.database.autocommit, isTrue);
  });
  test(
    'pending reads reject corrupt bytes and mismatched indexed identity',
    () {
      final intents = ProfileTextIntents(profile);
      intents.stage(space, writer, intentBytes());
      profile.database.execute('UPDATE protected_text_intents SET entity=?', [
        otherSpace,
      ]);
      expect(
        () => intents.pending(space, writer),
        throwsA(isA<FormatFailure>()),
      );
      profile.database.execute(
        'UPDATE protected_text_intents SET entity=?,raw=?',
        [
          entity,
          Uint8List.fromList([255]),
        ],
      );
      expect(
        () => intents.pending(space, writer),
        throwsA(isA<FormatException>()),
      );
      expect(
        profile.database
            .select('SELECT raw FROM protected_text_intents')
            .single['raw'],
        [255],
      );
    },
  );
}
