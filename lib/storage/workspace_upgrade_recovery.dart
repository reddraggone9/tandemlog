import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/event.dart';
import '../food/food_record.dart';
import '../food/food_store.dart';
import '../text/native_text_engine.dart';
import 'local_profile_database.dart';
import 'local_settings.dart';
import 'log_folder.dart';
import 'profile_food_intents.dart';
import 'profile_text_intents.dart';
import 'task_store.dart';
import 'workspace_upgrade_guard.dart';

/// Finishes only exact saves reserved before upgrade staging. Call outside
/// profile.serialize: store methods own that queue. The host must keep other
/// local upgrade actions disabled until this operation finishes. Folder sync
/// supplies no global lock; the coordinator must revalidate its frozen sources
/// and cancel/restart an invalidated pre-staging session after recovered writes.
Future<void> finishWorkspaceUpgradeSaves({
  required LogFolder folder,
  required LocalProfileDatabase profile,
  required String writer,
  NativeTextEngine? textEngine,
  TaskStore? tasks,
  FoodStore? food,
}) async {
  final original = await _recoveryManifest(folder);
  final manifest = jsonDecode(utf8.decode(original)) as Map;
  final space = manifest['id'] as String;
  await profile.serialize(() async {
    if (!isCanonicalId(writer) ||
        LocalSettings.protectedValues(profile)['writer'] != writer) {
      throw FormatFailure(
        'Recovery installation differs from protected identity.',
      );
    }
    _assertRecoveryPhase(profile, space);
  });

  if (tasks != null &&
      (tasks.unified != null ||
          !identical(tasks.profileDatabase, profile) ||
          tasks.folder.location != folder.location ||
          tasks.writer != writer ||
          tasks.space != space)) {
    throw FormatFailure(
      'Task recovery handle belongs to a different workspace or profile.',
    );
  }
  if (food != null &&
      (food.unified != null ||
          !identical(food.profile, profile) ||
          food.folder.location != folder.location ||
          food.writer != foodWriter(writer) ||
          food.space != space)) {
    throw FormatFailure(
      'Food recovery handle belongs to a different workspace or profile.',
    );
  }

  Future<void> check() async {
    final current = await _recoveryManifest(folder);
    if (!_equalRecoveryBytes(current, original)) {
      throw FormatFailure(
        'Workspace manifest changed. Saved recovery bytes were preserved.',
      );
    }
    await profile.serialize(() async => _assertRecoveryPhase(profile, space));
  }

  final pending = await profile.serialize(() async {
    final guard = SqliteWriterGuard(profile);
    final taskGuard = await guard.load(space, writer);
    final foodGuard = await guard.load(space, foodWriter(writer));
    return (
      tasks:
          ProfileTextIntents(profile).pending(space, writer).isNotEmpty ||
          (taskGuard?.pending.isNotEmpty ?? false),
      food:
          ProfileFoodIntents(
            profile,
          ).pending(space, foodWriter(writer)).isNotEmpty ||
          (foodGuard?.pending.isNotEmpty ?? false),
    );
  });
  TaskStore? openedTasks;
  FoodStore? openedFood;
  try {
    // Do not initialize a previously unused module just to discover no work.
    if (pending.tasks) {
      await check();
      final active =
          tasks ??
          (openedTasks = await TaskStore.open(
            folder,
            profile.root,
            profileDatabase: profile,
            writerIdentity: writer,
            textEngine: textEngine,
            initializeNewWorkspaceText: false,
          ));
      await active.refresh(); // Admits already-present uncertain append once.
      final receipts = active.pendingTextOperations.toList(growable: false);
      await profile.serialize(() async {
        final guard = await SqliteWriterGuard(profile).load(space, writer);
        final exact = {
          for (final receipt in receipts)
            LogEvent.decode(receipt.raw).sequence: LogEvent.decode(
              receipt.raw,
            ).hash,
        };
        if (guard != null &&
            guard.pending.any(
              (record) => exact[record.sequence] != record.hash,
            )) {
          throw WriterGuardFailure(
            'An earlier Task save has no exact protected recovery bytes. Restore its exact prepared history; this profile and workspace were preserved.',
          );
        }
      });
      for (final receipt in receipts) {
        await check();
        await active.retryTextOperation(receipt);
      }
      final remaining = await profile.serialize(
        () => SqliteWriterGuard(profile).load(space, writer),
      );
      if (active.pendingTextOperations.isNotEmpty ||
          (remaining?.pending.isNotEmpty ?? false)) {
        throw WriterGuardFailure.unresolvedAppend();
      }
    }

    if (pending.food) {
      await check();
      final active =
          food ??
          (openedFood = await FoodStore.open(
            folder,
            profile: profile,
            installationWriter: writer,
            space: space,
          ));
      await check();
      await active.recoverPrepared();
      final remaining = await profile.serialize(
        () => SqliteWriterGuard(profile).load(space, foodWriter(writer)),
      );
      if (active.hasPreparedAppend ||
          (remaining?.pending.isNotEmpty ?? false) ||
          ProfileFoodIntents(
            profile,
          ).pending(space, foodWriter(writer)).isNotEmpty) {
        throw WriterGuardFailure.unresolvedAppend();
      }
    }
    await check();
  } finally {
    // Caller-owned handles remain live. Never close the shared profile/engine.
    try {
      await openedFood?.close();
    } finally {
      await openedTasks?.close();
    }
  }
}

Future<Uint8List> _recoveryManifest(LogFolder folder) async {
  final names = (await folder.list()).map((entry) => entry.name).toList();
  if (names.toSet().length != names.length ||
      names.any(
        (name) =>
            RegExp(r'^upgrade-.*-staging\.json$').hasMatch(name) ||
            name.contains('.applog'),
      )) {
    throw FormatFailure(
      'Recovery is only available before upgrade staging. Saved recovery bytes were preserved.',
    );
  }
  if (folder is! BoundedLogFolder) {
    throw FormatFailure('This folder cannot enforce recovery read limits.');
  }
  if (folder is LocalLogFolder &&
      await FileSystemEntity.type(
            folder.file('tandemlog-space.json').path,
            followLinks: false,
          ) !=
          FileSystemEntityType.file) {
    throw FormatFailure('Recovery manifest must be a regular file.');
  }
  final raw = await (folder as BoundedLogFolder).readBounded(
    'tandemlog-space.json',
    4096,
  );
  final manifest = jsonDecode(utf8.decode(raw));
  if (manifest is! Map ||
      manifest.length != 2 ||
      manifest['v'] != 3 ||
      !isCanonicalId(manifest['id'])) {
    throw FormatFailure(
      'Only the original v3 workspace can finish these saves.',
    );
  }
  if (names.contains('tandemlog-upgrade.json')) {
    final session = WorkspaceUpgradeGuard.decodeSession(
      await (folder as BoundedLogFolder).readBounded(
        'tandemlog-upgrade.json',
        1024 * 1024,
      ),
      space: manifest['id'] as String,
    );
    if (!_equalRecoveryBytes(
      base64Decode(session['manifest'] as String),
      raw,
    )) {
      throw FormatFailure(
        'Upgrade source manifest changed. Saved recovery bytes were preserved.',
      );
    }
  } else if (names.any(WorkspaceUpgradeGuard.isUpgradeArtifact)) {
    throw FormatFailure(
      'Upgrade coordination is missing. Restore it before recovering saves.',
    );
  }
  return raw;
}

void _assertRecoveryPhase(LocalProfileDatabase profile, String space) {
  // Use the same strict protected journal/session binding as command admission.
  WorkspaceUpgradeGuard.isFrozen(profile, space);
  for (final row in profile.database.select(
    'SELECT plan,state FROM protected_app_migrations WHERE space=?',
    [space],
  )) {
    final plan = jsonDecode(utf8.decode(row['plan'] as List<int>));
    if (plan is! Map) {
      throw FormatFailure('Upgrade recovery journal is invalid.');
    }
    if (plan['kind'] != 'workspace-upgrade-v1' &&
        !(plan['kind'] == null &&
            plan['v'] == 1 &&
            plan['participants'] is List &&
            plan['sources'] is Map &&
            plan['phase'] is String)) {
      throw FormatFailure(
        'Unknown upgrade journal. Saved recovery bytes were preserved.',
      );
    }
    if (plan['kind'] == 'workspace-upgrade-v1' &&
        !{'frozen', 'input', 'invalidated', 'aborted'}.contains(row['state'])) {
      throw FormatFailure(
        'Recovery is only available before upgrade staging. Saved recovery bytes were preserved.',
      );
    }
  }
}

bool _equalRecoveryBytes(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((index) => a[index] == b[index]);
