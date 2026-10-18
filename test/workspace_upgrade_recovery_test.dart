import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/profile_food_intents.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/workspace_upgrade.dart';
import 'package:tandemlog/storage/workspace_upgrade_recovery.dart';
import 'package:tandemlog/text/native_text_engine.dart';

const owner = '11111111-1111-4111-8111-111111111111';
const peer = '22222222-2222-4222-8222-222222222222';
const user = '33333333-3333-4333-8333-333333333333';
const task = '44444444-4444-4444-8444-444444444444';

class _RecoveryFolder extends LocalLogFolder {
  _RecoveryFolder(super.location);
  int? prefix;
  bool unknownAfterFullWrite = false;
  bool failFoodReadAfterWrite = false;
  bool foodReadsBlocked = false;
  bool failStagingMarker = false;
  int canonicalWrites = 0;

  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) {
    if (foodReadsBlocked && name.endsWith('.foodlog')) {
      throw FolderAccessFailure('Synthetic readback unavailable');
    }
    return super.readBounded(name, maximumBytes);
  }

  Future<void> _write(String name, Uint8List bytes, bool create) async {
    if (failStagingMarker && name.endsWith('-staging.json')) {
      failStagingMarker = false;
      throw FolderAccessFailure(
        'Synthetic staging marker publication interrupted',
      );
    }
    final canonical = name.endsWith('.jsonl') || name.endsWith('.foodlog');
    final cut = canonical ? prefix : null;
    if (canonical) prefix = null;
    final saved = cut == null
        ? bytes
        : Uint8List.sublistView(bytes, 0, cut.clamp(0, bytes.length));
    if (create) {
      await super.create(name, saved);
    } else {
      await super.append(name, saved);
    }
    if (!canonical) return;
    canonicalWrites++;
    if (name.endsWith('.foodlog') && failFoodReadAfterWrite) {
      failFoodReadAfterWrite = false;
      foodReadsBlocked = true;
    }
    if (cut != null || unknownAfterFullWrite) {
      unknownAfterFullWrite = false;
      throw FolderAccessFailure('Synthetic unknown append outcome');
    }
  }

  @override
  Future<void> create(String name, Uint8List bytes) =>
      _write(name, bytes, true);
  @override
  Future<void> append(String name, Uint8List bytes) =>
      _write(name, bytes, false);
}

void main() {
  late Directory root;
  late _RecoveryFolder folder;
  late LocalProfileDatabase profile, coordinator;
  TaskStore? tasks;
  FoodStore? food;

  Future<LocalProfileDatabase> openProfile(String id) async {
    final p = await LocalProfileDatabase.open('${root.path}/profile-$id');
    p.transaction(
      () =>
          p.database.execute('INSERT INTO protected_settings VALUES (1,?,?)', [
            id,
            utf8.encode(jsonEncode({'writer': id, 'appearance': 'system'})),
          ]),
    );
    return p;
  }

  Future<void> openStores({NativeTextEngine? engine}) async {
    tasks = await TaskStore.open(
      folder,
      profile.root,
      profileDatabase: profile,
      writerIdentity: owner,
      textEngine: engine,
      initializeNewWorkspaceText: false,
    );
    food = await FoodStore.open(
      folder,
      profile: profile,
      installationWriter: owner,
      space: tasks!.space,
    );
  }

  Future<WorkspaceUpgrade> freeze({NativeTextEngine? engine}) async {
    final upgrade = await WorkspaceUpgrade.start(
      folder: folder,
      profile: coordinator,
      writer: peer,
      participants: {owner, peer},
      textEngine: engine,
    );
    await WorkspaceUpgrade.open(
      folder: folder,
      profile: profile,
      writer: owner,
      textEngine: engine,
    );
    return upgrade;
  }

  Future<void> recover({NativeTextEngine? engine, bool warm = true}) =>
      finishWorkspaceUpgradeSaves(
        folder: folder,
        profile: profile,
        writer: owner,
        textEngine: engine,
        tasks: warm ? tasks : null,
        food: warm ? food : null,
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'upgrade-exact-save-recovery-',
    );
    folder = _RecoveryFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    profile = await openProfile(owner);
    coordinator = await openProfile(peer);
    await openStores();
    await tasks!.command(user, 'user.created', {'name': 'Synthetic'});
  });
  tearDown(() async {
    await food?.close();
    await tasks?.close();
    await profile.close();
    await coordinator.close();
    await root.delete(recursive: true);
  });

  test(
    'partial Food save recovers exact bytes once and invalidates frozen input',
    () async {
      folder.prefix = 0;
      await expectLater(
        food!.add(const FoodDetails(name: 'Synthetic rice'), 1),
        throwsA(isA<FolderAccessFailure>()),
      );
      final space = tasks!.space;
      final saved = ProfileFoodIntents(
        profile,
      ).pending(space, foodWriter(owner)).single;
      final manifest = await folder.read('tandemlog-space.json');
      final upgrade = await freeze();
      expect(WorkspaceUpgrade.isFrozen(profile, space), true);
      await recover();
      expect(await folder.read(foodLogName(foodWriter(owner))), [...saved, 10]);
      expect(food!.state.active.single.details.name, 'Synthetic rice');
      expect(
        ProfileFoodIntents(profile).pending(space, foodWriter(owner)),
        isEmpty,
      );
      final writes = folder.canonicalWrites;
      await recover();
      expect(folder.canonicalWrites, writes);
      expect(await folder.read('tandemlog-space.json'), manifest);
      await upgrade.refresh();
      expect(upgrade.phase, 'invalidated');
      expect(upgrade.canAbort, true);
      // Caller-owned handles were not closed.
      await tasks!.refresh();
      await food!.refresh();
    },
  );

  test(
    'full Food append with failed readback is admitted without reappend',
    () async {
      folder.failFoodReadAfterWrite = true;
      await expectLater(
        food!.add(const FoodDetails(name: 'Synthetic beans'), 1),
        throwsA(isA<FoodHistoryFailure>()),
      );
      final saved = ProfileFoodIntents(
        profile,
      ).pending(tasks!.space, foodWriter(owner)).single;
      folder.foodReadsBlocked = false;
      final upgrade = await freeze();
      final writes = folder.canonicalWrites;
      await recover();
      expect(folder.canonicalWrites, writes);
      expect(await folder.read(foodLogName(foodWriter(owner))), [...saved, 10]);
      expect(food!.state.active, hasLength(1));
      await upgrade.refresh();
      expect(
        upgrade.phase,
        'input',
      ); // Original bytes already included the save.
    },
  );

  test(
    'cold recovery closes only its opened handles and retains profile',
    () async {
      folder.prefix = 0;
      await expectLater(
        food!.add(const FoodDetails(name: 'Synthetic oats'), 1),
        throwsA(isA<FolderAccessFailure>()),
      );
      final space = tasks!.space;
      await food!.close();
      food = null;
      await tasks!.close();
      tasks = null;
      await freeze();
      await recover(warm: false);
      await openStores();
      expect(tasks!.space, space);
      expect(food!.state.active.single.details.name, 'Synthetic oats');
      expect(LocalSettings.protectedValues(profile)['writer'], owner);
    },
  );

  test(
    'unappended nontext Task save stays reserved without invented bytes',
    () async {
      folder.prefix = 0;
      await expectLater(
        tasks!.command(task, 'task.created', {
          'title': 'Reserved ordinary save',
          'description': '',
          'assignee': user,
        }),
        throwsA(isA<FolderAccessFailure>()),
      );
      final before = await folder.read('$owner.jsonl');
      final guard = await SqliteWriterGuard(profile).load(tasks!.space, owner);
      expect(guard!.pending, hasLength(1));
      await freeze();
      await expectLater(recover(), throwsA(isA<WriterGuardFailure>()));
      expect(await folder.read('$owner.jsonl'), before);
      final after = await SqliteWriterGuard(profile).load(tasks!.space, owner);
      expect(after!.pending.single.hash, guard.pending.single.hash);
      expect(tasks!.pendingTextOperations, isEmpty);
    },
  );

  test(
    'already present nontext Task save is acknowledged without reappend',
    () async {
      folder.unknownAfterFullWrite = true;
      await expectLater(
        tasks!.command(task, 'task.created', {
          'title': 'Already saved',
          'description': '',
          'assignee': user,
        }),
        throwsA(isA<FolderAccessFailure>()),
      );
      final before = await folder.read('$owner.jsonl');
      final writes = folder.canonicalWrites;
      await freeze();
      await recover();
      expect(await folder.read('$owner.jsonl'), before);
      expect(folder.canonicalWrites, writes);
      expect(
        tasks!.rows.singleWhere((row) => row['id'] == task)['title'],
        'Already saved',
      );
      expect(
        (await SqliteWriterGuard(profile).load(tasks!.space, owner))!.pending,
        isEmpty,
      );
    },
  );

  test(
    'staging marker blocks pending recovery without changing receipts',
    () async {
      folder.prefix = 0;
      await expectLater(
        food!.add(const FoodDetails(name: 'Held save'), 1),
        throwsA(isA<FolderAccessFailure>()),
      );
      final saved = ProfileFoodIntents(
        profile,
      ).pending(tasks!.space, foodWriter(owner)).single;
      await folder.create(
        'upgrade-$peer-staging.json',
        Uint8List.fromList([123, 125]),
      );
      final writes = folder.canonicalWrites;
      await expectLater(recover(), throwsA(isA<FormatFailure>()));
      expect(folder.canonicalWrites, writes);
      expect(
        ProfileFoodIntents(
          profile,
        ).pending(tasks!.space, foodWriter(owner)).single,
        saved,
      );
    },
  );

  test(
    'local staging journal blocks recovery before shared marker exists',
    () async {
      final upgrade = await freeze();
      final participant = (await WorkspaceUpgrade.open(
        folder: folder,
        profile: profile,
        writer: owner,
      ))!;
      await upgrade.acknowledgeInput();
      await participant.consentToUpgrade();
      await participant.acknowledgeInput();
      folder.failStagingMarker = true;
      await expectLater(upgrade.stage(), throwsA(isA<FolderAccessFailure>()));
      expect(
        (await folder.list()).any(
          (entry) => entry.name.endsWith('-staging.json'),
        ),
        false,
      );
      final writes = folder.canonicalWrites;
      await expectLater(
        finishWorkspaceUpgradeSaves(
          folder: folder,
          profile: coordinator,
          writer: peer,
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(folder.canonicalWrites, writes);
    },
  );

  test(
    'no pending save does not initialize cold modules or write history',
    () async {
      await food!.close();
      food = null;
      await tasks!.close();
      tasks = null;
      final before = folder.canonicalWrites;
      await recover(warm: false);
      expect(folder.canonicalWrites, before);
      await openStores();
    },
  );

  test(
    'different protected writer is rejected before any canonical write',
    () async {
      final writes = folder.canonicalWrites;
      await expectLater(
        finishWorkspaceUpgradeSaves(
          folder: folder,
          profile: profile,
          writer: peer,
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(folder.canonicalWrites, writes);
    },
  );

  test(
    'actual native exact Task receipt recovers once while frozen',
    () async {
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      try {
        await food!.close();
        food = null;
        await tasks!.close();
        tasks = null;
        await openStores(engine: engine);
        folder.prefix = 0;
        OperationReceipt? receipt;
        await expectLater(
          tasks!.command(task, 'task.createdWithText', {
            'title': 'Exact native save',
            'description': '',
            'assignee': user,
            'text': {
              'codec': 'yrs-v1',
              'adapter': 1,
              'seeds': {
                'title': sha256
                    .convert(engine.seedText('Exact native save').bytes)
                    .toString(),
                'description': sha256
                    .convert(engine.seedText('').bytes)
                    .toString(),
              },
            },
          }, onPrepared: (value) => receipt = value),
          throwsA(isA<FolderAccessFailure>()),
        );
        expect(tasks!.pendingTextOperations.single.raw, receipt!.raw);
        final upgrade = await freeze(engine: engine);
        await recover(engine: engine);
        expect(tasks!.pendingTextOperations, isEmpty);
        expect(
          tasks!.rows.singleWhere((row) => row['id'] == task)['title'],
          'Exact native save',
        );
        final raw = utf8.decode(await folder.read('$owner.jsonl'));
        expect(
          raw.split('\n').where((line) => line == receipt!.raw),
          hasLength(1),
        );
        final writes = folder.canonicalWrites;
        await recover(engine: engine);
        expect(folder.canonicalWrites, writes);
        await upgrade.refresh();
        expect(upgrade.phase, 'invalidated');
      } finally {
        await food?.close();
        food = null;
        await tasks?.close();
        tasks = null;
        engine.dispose();
      }
    },
    skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null
        ? 'Actual reviewed native library required'
        : false,
  );
}
