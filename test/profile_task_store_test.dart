import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/profile_lock.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/task_tables.dart';
import 'package:tandemlog/storage/checklist_expansion_store.dart';
import 'package:tandemlog/storage/profile_text_intents.dart';
import 'package:tandemlog/text/native_text_engine.dart';

const owner = '00000000-0000-4000-8000-000000000001';
const user = '00000000-0000-4000-8000-000000000002';
const entity = '00000000-0000-4000-8000-000000000003';

void main() {
  late Directory root;
  late LocalProfileDatabase profile;
  final handles = <TaskStore>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-shared-db-');
    profile = await LocalProfileDatabase.open('${root.path}/profile');
  });
  tearDown(() async {
    for (final store in handles) {
      await store.close();
    }
    handles.clear();
    await profile.close();
    await root.delete(recursive: true);
  });

  Future<TaskStore> open(String name) async {
    final location = '${root.path}/$name';
    await Directory(location).create(recursive: true);
    final store = await TaskStore.open(
      LocalLogFolder(location),
      profile.root,
      profileDatabase: profile,
      writerIdentity: owner,
    );
    handles.add(store);
    return store;
  }

  test('immutable names reject injected identifiers', () {
    expect(
      () => TaskTables.forLocation('x; DROP TABLE protected_settings'),
      throwsArgumentError,
    );
    expect(
      TaskTables.forLocation('a' * 64).events,
      isNot(TaskTables.forLocation('b' * 64).events),
    );
  });

  test(
    'shared checklist display state is scoped and uses owner rollback',
    () async {
      final first = await open('display-first');
      final second = await open('display-second');
      final display = ChecklistExpansionStore(
        first.db,
        tables: first.tables,
        profileDatabase: profile,
      );
      final other = ChecklistExpansionStore(
        second.db,
        tables: second.tables,
        profileDatabase: profile,
      );
      display.setExpanded([entity], true);
      expect(display.load(), {entity});
      expect(other.load(), isEmpty);
      profile.database.execute(
        "CREATE TRIGGER reject_display_change BEFORE INSERT ON ${first.tables.metadata} WHEN NEW.key='ui.checklist-expanded:$user' BEGIN SELECT RAISE(ABORT,'synthetic display failure'); END",
      );
      await expectLater(
        Future.sync(() => display.setExpanded([owner, user], true)),
        throwsA(isA<Exception>()),
      );
      expect(display.load(), {entity});
      expect(profile.database.autocommit, isTrue);
      await second.command(user, 'user.created', {'name': 'Still usable'});
    },
  );

  test(
    'two workspaces isolate identical entity and writer sequence IDs',
    () async {
      final first = await open('first');
      final second = await open('second');
      expect(identical(first.db, second.db), isTrue);
      for (final (index, store) in [first, second].indexed) {
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        await store.command(entity, 'task.created', {
          'title': 'Task $index',
          'description': '',
          'assignee': user,
        });
      }
      expect(
        first.rows.firstWhere((r) => r['id'] == entity)['title'],
        'Task 0',
      );
      expect(
        second.rows.firstWhere((r) => r['id'] == entity)['title'],
        'Task 1',
      );
      expect(
        await SqliteWriterGuard(profile).load(first.space, owner),
        isNotNull,
      );
      expect(
        await SqliteWriterGuard(profile).load(second.space, owner),
        isNotNull,
      );
      await first.close();
      await second.command(entity, 'task.edited', {'title': 'Still open'});
      expect(
        second.rows.firstWhere((r) => r['id'] == entity)['title'],
        'Still open',
      );
      expect(Directory('${profile.root}/spaces').existsSync(), isFalse);
      expect(File('${profile.root}/profile.lock').existsSync(), isFalse);
    },
  );

  test('same location rejects a duplicate handle until close', () async {
    final first = await open('same');
    await expectLater(
      TaskStore.open(
        first.folder,
        profile.root,
        profileDatabase: profile,
        writerIdentity: owner,
      ),
      throwsA(isA<ProfileInUse>()),
    );
    await first.close();
    final reopened = await open('same');
    expect(reopened.space, first.space);
  });

  test(
    'queued open prevents owner close before its handle is returned',
    () async {
      final location = await Directory('${root.path}/queued').create();
      final gate = Completer<void>();
      final blocked = profile.serialize(() => gate.future);
      final opening = TaskStore.open(
        LocalLogFolder(location.path),
        profile.root,
        profileDatabase: profile,
        writerIdentity: owner,
      );
      final closeCheck = expectLater(profile.close(), throwsStateError);
      gate.complete();
      await blocked;
      final store = await opening;
      handles.add(store);
      await closeCheck;
      await store.command(user, 'user.created', {'name': 'Still usable'});
    },
  );

  test('shared namespace never invokes legacy global schema replay', () async {
    final store = await open('legacy-version');
    await store.close();
    profile.database.execute(
      "UPDATE ${store.tables.metadata} SET value='12' WHERE key='projection_schema'",
    );
    await expectLater(open('legacy-version'), throwsA(isA<Exception>()));
    expect(
      profile.database.select('PRAGMA user_version').single.values.single,
      LocalProfileDatabase.schemaVersion,
    );
    expect(
      profile.database.select(
        "SELECT 1 FROM sqlite_schema WHERE name='protected_text_intents'",
      ),
      isNotEmpty,
    );
  });

  for (final appended in [false, true]) {
    test(
      'protected native receipt survives alias confirmation/rebuild appended=$appended',
      () async {
        final engine = NativeTextEngine(
          libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
        );
        try {
          final location = await Directory('${root.path}/native').create();
          final folder = _AliasFolder(LocalLogFolder(location.path), 'first');
          var store = await TaskStore.open(
            folder,
            profile.root,
            profileDatabase: profile,
            writerIdentity: owner,
            textEngine: engine,
          );
          handles.add(store);
          await store.command(user, 'user.created', {'name': 'Synthetic'});
          final alias = await TaskStore.open(
            _AliasFolder(folder.inner, 'second'),
            profile.root,
            profileDatabase: profile,
            writerIdentity: owner,
            textEngine: engine,
          );
          handles.add(alias);
          OperationReceipt? receipt;
          folder.failNext = true;
          folder.writeBeforeFailure = appended;
          await expectLater(
            store.command(entity, 'task.createdWithText', {
              'title': 'Exact receipt',
              'description': '',
              'assignee': user,
              'text': {
                'codec': 'yrs-v1',
                'adapter': 1,
                'seeds': {
                  'title': sha256
                      .convert(engine.seedText('Exact receipt').bytes)
                      .toString(),
                  'description': sha256
                      .convert(engine.seedText('').bytes)
                      .toString(),
                },
              },
            }, onPrepared: (value) => receipt = value),
            throwsA(isA<FolderAccessFailure>()),
          );
          expect(store.pendingTextOperations.single.raw, receipt!.raw);
          await alias.refresh();
          await store.close();
          store = await TaskStore.open(
            folder,
            profile.root,
            profileDatabase: profile,
            writerIdentity: owner,
            textEngine: engine,
          );
          handles.add(store);
          if (appended) {
            expect(store.pendingTextOperations, isEmpty);
          } else {
            expect(store.pendingTextOperations.single.raw, receipt!.raw);
          }
          await store.rebuildCache();
          final event = await store.retryTextOperation(receipt!);
          expect(event.canonicalRaw, receipt!.raw);
          expect(store.pendingTextOperations, isEmpty);
          expect(
            profile.database.select('SELECT * FROM protected_text_intents'),
            isEmpty,
          );
          expect(
            store.rows.firstWhere((row) => row['id'] == entity)['title'],
            'Exact receipt',
          );
          expect(File('${profile.root}/cache.sqlite').existsSync(), isFalse);
          expect(
            Directory('${profile.root}/text-intents').existsSync(),
            isFalse,
          );
        } finally {
          for (final store in handles) {
            await store.close();
          }
          engine.dispose();
        }
      },
    );
  }

  test(
    'failed shared acknowledgement retains exact intent and rolls back projections',
    () async {
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      try {
        final location = await Directory('${root.path}/ack-failure').create();
        final folder = _AliasFolder(LocalLogFolder(location.path), 'ack');
        final store = await TaskStore.open(
          folder,
          profile.root,
          profileDatabase: profile,
          writerIdentity: owner,
          textEngine: engine,
        );
        handles.add(store);
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        final before = jsonEncode(store.rows);
        final guard = await SqliteWriterGuard(profile).load(store.space, owner);
        profile.database.execute(
          "CREATE TRIGGER reject_ack BEFORE UPDATE ON protected_writer_guards WHEN NEW.space='${store.space}' AND json_extract(NEW.raw,'\$.sequence')>json_extract(OLD.raw,'\$.sequence') BEGIN SELECT RAISE(ABORT,'synthetic acknowledgement failure'); END",
        );
        OperationReceipt? receipt;
        await expectLater(
          store.command(entity, 'task.createdWithText', {
            'title': 'Exact intent',
            'description': '',
            'assignee': user,
            'text': {
              'codec': 'yrs-v1',
              'adapter': 1,
              'seeds': {
                'title': sha256
                    .convert(engine.seedText('Exact intent').bytes)
                    .toString(),
                'description': sha256
                    .convert(engine.seedText('').bytes)
                    .toString(),
              },
            },
          }, onPrepared: (value) => receipt = value),
          throwsA(isA<Exception>()),
        );
        expect(jsonEncode(store.rows), before);
        expect(
          store.db.select('SELECT id FROM ${store.tables.events} WHERE id=?', [
            receipt!.id,
          ]),
          isEmpty,
        );
        final retained = await SqliteWriterGuard(
          profile,
        ).load(store.space, owner);
        expect(retained!.sequence, guard!.sequence);
        expect(retained.hash, guard.hash);
        expect(retained.pending, hasLength(1));
        expect(
          utf8.decode(
            ProfileTextIntents(profile).pending(store.space, owner).single,
          ),
          receipt!.raw,
        );
        expect(profile.database.autocommit, isTrue);
        final canonical = await folder.read('$owner.jsonl');
        profile.database.execute('DROP TRIGGER reject_ack');
        await store.refresh();
        expect(store.pendingTextOperations, isEmpty);
        expect(await folder.read('$owner.jsonl'), canonical);
        expect(
          store.rows.firstWhere((row) => row['id'] == entity)['title'],
          'Exact intent',
        );
      } finally {
        for (final store in handles) {
          await store.close();
        }
        engine.dispose();
      }
    },
  );

  test(
    'overlapping workspace operations share one transaction owner',
    () async {
      final first = await open('first');
      final second = await open('second');
      await Future.wait([
        first.command(user, 'user.created', {'name': 'One'}),
        second.command(user, 'user.created', {'name': 'Two'}),
      ]);
      expect(profile.database.autocommit, isTrue);
      for (final store in [first, second]) {
        final key = sha256
            .convert(utf8.encode(store.folder.location))
            .toString();
        final tables = TaskTables.forLocation(key);
        expect(
          profile.database
              .select('SELECT COUNT(*) AS n FROM ${tables.events}')
              .single['n'],
          1,
        );
      }
    },
  );
}

class _AliasFolder implements LogFolder, RangeLogFolder {
  _AliasFolder(this.inner, this.alias);
  final LocalLogFolder inner;
  final String alias;
  bool failNext = false, writeBeforeFailure = false;
  @override
  String get location => '${inner.location}/$alias';
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<Uint8List?> readFrom(String name, int offset) =>
      inner.readFrom(name, offset);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    if (failNext) {
      failNext = false;
      if (writeBeforeFailure) await inner.append(name, bytes);
      throw FolderAccessFailure('Synthetic unknown append outcome');
    }
    await inner.append(name, bytes);
  }
}
