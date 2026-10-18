// Test-only controlled interruption through real SAF transport, never app UI.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart' show canonicalDataJson;
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_profile_migration.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/workspace_upgrade.dart';
import 'package:tandemlog/text/native_text_engine.dart';

String _hash(List<int> bytes) => sha256.convert(bytes).toString();
void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

bool _equal(Object? a, Object? b) =>
    canonicalDataJson(a) == canonicalDataJson(b);

Map<String, Object?> _seal(List<int> bytes) => {
  'bytes': bytes.length,
  'sha256': _hash(bytes),
};

/// The core journals full desired bytes first. This transport deliberately
/// submits a shorter replacement to the REAL provider, confirms that prefix,
/// and reports an uncertain outcome. It does not simulate a provider exception
/// or promise coverage of provider-origin failures, power loss or all providers.
class _InterruptedSaf
    implements
        LogFolder,
        BoundedLogFolder,
        RangeLogFolder,
        CheckedReplaceLogFolder {
  _InterruptedSaf(this.inner, this.journal, this.faults);
  final AndroidLogFolder inner;
  final Map<String, dynamic> Function() journal;
  final List<Map<String, Object?>> faults;
  String? armed;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) =>
      inner.readBounded(name, maximumBytes);
  @override
  Future<Uint8List?> readFrom(String name, int offset) =>
      inner.readFrom(name, offset);
  @override
  Future<void> append(String name, Uint8List bytes) =>
      inner.append(name, bytes);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> checkReplacementSupport(String name, int maximumBytes) =>
      inner.checkReplacementSupport(name, maximumBytes);
  @override
  Future<void> replaceOwned(
    String name,
    Uint8List expected,
    Uint8List bytes,
  ) async {
    final phase = armed;
    if (phase == null || name != 'tandemlog-space.json') {
      return inner.replaceOwned(name, expected, bytes);
    }
    final state = journal();
    final intent = state['replacement'];
    _require(
      state['phase'] == phase,
      'Core replacement phase was not journaled',
    );
    _require(
      intent is Map &&
          intent['expected'] == base64Encode(expected) &&
          intent['desired'] == base64Encode(bytes),
      'Core exact replacement intent must exist before real provider mutation',
    );
    _require(bytes.length > 2, 'Expected bounded nonempty manifest');
    final prefix = Uint8List.fromList(bytes.take(bytes.length ~/ 2).toList());
    final fault = <String, Object?>{
      'phase': phase,
      'journalVerifiedBeforeWrite': true,
      'expected': _seal(expected),
      'desired': _seal(bytes),
      'prefix': _seal(prefix),
      'checkedTransportPrefixReplacementConfirmed': false,
      'realAndroidProviderReplacementConfirmed': false,
    };
    faults.add(fault);
    armed = null;
    await inner.replaceOwned(name, expected, prefix);
    _require(
      _equal(await inner.read(name), prefix),
      'Provider prefix readback differs',
    );
    fault['checkedTransportPrefixReplacementConfirmed'] = true;
    fault['realAndroidProviderReplacementConfirmed'] = Platform.isAndroid;
    throw OwnedReplacementFailure(
      'QA controlled interruption after confirmed real SAF prefix replacement',
      phase: 'qa_controlled_interruption',
      mayHaveChanged: true,
    );
  }
}

/// [root] MUST be newly created app-private QA storage, never a normal profile.
/// The caller obtains one explicit tree grant and confirms a NEW EMPTY folder.
/// The empty check is repeated immediately before creating any synthetic data.
Future<Map<String, Object?>> runWorkspaceUpgradeSafQa(
  Directory root,
  AndroidLogFolder realFolder, {
  required void Function(String) progress,
  String? libraryPath,
}) async {
  _require(await root.list().isEmpty, 'QA private root must be new and empty');
  final steps = <String>[];
  final faults = <Map<String, Object?>>[];
  final report = <String, Object?>{
    'v': 1,
    'testOnly': true,
    'syntheticOnly': true,
    'source': const String.fromEnvironment('WORKSPACE_UPGRADE_QA_SOURCE'),
    'target': 'tool/android_workspace_upgrade/main.dart',
    'transport': Platform.isAndroid
        ? 'AndroidLogFolder / existing MainActivity / selected SAF tree'
        : 'Host filesystem adapter smoke only; not Android or SAF acceptance',
    'runtimePlatform': Platform.operatingSystem,
    'actualAndroidSafAcceptance': false,
    'controlledInterruptionNotProviderOriginFailure': true,
    'coldSqliteReopenNotAndroidProcessKill': true,
    'passed': false,
    'steps': steps,
    'faults': faults,
  };
  LocalProfileDatabase? activeProfile;
  TaskStore? tasks;
  FoodStore? food;
  UnifiedHistory? history;
  NativeTextEngine? engine;
  void step(String text) {
    steps.add(text);
    progress(text);
  }

  try {
    _require(
      (await realFolder.list()).isEmpty,
      'Selected SAF folder is not empty; nothing was written',
    );
    report['selectedFolderInitiallyEmpty'] = true;
    step('Fresh empty SAF folder checked');
    final profileRoot = '${root.path}/qa-private-profile';
    activeProfile = await LocalProfileDatabase.open(profileRoot);
    await LocalProfileMigration(activeProfile).run();
    var settings = LocalSettings(profileRoot, profileDatabase: activeProfile);
    await settings.load();
    final writer = settings.writer, user = const Uuid().v4();
    engine = NativeTextEngine(libraryPath: libraryPath);
    tasks = await TaskStore.open(
      realFolder,
      profileRoot,
      profileDatabase: activeProfile,
      writerIdentity: writer,
      textEngine: engine,
      initializeNewWorkspaceText: true,
    );
    final space = tasks.space, task = const Uuid().v4();
    await tasks.command(user, 'user.created', {
      'name': 'Synthetic QA household',
    });
    await tasks.createTasks({task: 'Synthetic native task'}, user);
    final capture = await tasks.captureTaskText(task);
    try {
      final field = capture.fields['title']!;
      final draft = field.document.captureDraft(actorClientId: field.actor);
      try {
        draft.replaceText('Synthetic native task edited before upgrade');
        final prepared = draft.prepareSave();
        await tasks.command(task, 'task.textEdited', {
          'changes': {
            'title': {
              'context': field.context,
              'allocation': field.allocation,
              'actor': field.actor,
              'update': prepared.update.encoded,
            },
          },
        });
      } finally {
        draft.cancel();
      }
    } finally {
      tasks.releaseTextCapture(capture);
    }
    final item = await tasks.addChecklistItem(
      task,
      'Synthetic checklist item',
      notes: 'Synthetic native notes',
    );
    await tasks.setChecklistCompleted(item.entity, true);
    food = await FoodStore.open(
      realFolder,
      profile: activeProfile,
      installationWriter: writer,
      space: space,
    );
    await food.add(
      const FoodDetails(
        name: 'Synthetic rice',
        location: 'QA shelf',
        expiry: '2027-01-01',
      ),
      2,
    );
    await food.add(
      const FoodDetails(name: 'Synthetic beans', expiry: '2027-01-02'),
      1,
    );
    final rice = food.state.containers.firstWhere(
      (c) => c.details.name == 'Synthetic rice',
    );
    await food.remove([rice.id]);
    await food.undoOperations(food.lastPreparedRecords);
    settings.folder = realFolder.location;
    settings.user = user;
    settings.appearance = Appearance.dark;
    await settings.save();

    Map<String, Object?> projection() => {
      'tasks': [
        for (final row in tasks!.db.select(
          'SELECT id,raw FROM ${tasks.tables.views} ORDER BY id',
        ))
          {'id': row['id'], 'raw': jsonDecode(row['raw'] as String)},
      ],
      'nativeFields': [
        for (final row in tasks.db.select(
          'SELECT * FROM ${tasks.tables.textFields} ORDER BY entity,field',
        ))
          {
            for (final entry in row.entries)
              entry.key: entry.value is Uint8List
                  ? {'base64': base64Encode(entry.value as Uint8List)}
                  : entry.value,
          },
      ],
      'food': (food!.state.containers.map((c) => c.toJson()).toList()
        ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String))),
    };
    final beforeProjection = projection();
    _require(
      (beforeProjection['nativeFields'] as List).isNotEmpty,
      'Native text fixture missing',
    );
    final settingsBytes = base64Encode(
      activeProfile.database
              .select('SELECT raw FROM protected_settings')
              .single['raw']
          as List<int>,
    );
    final baseline = <String, Uint8List>{};
    for (final info in await realFolder.list()) {
      baseline[info.name] = await realFolder.read(info.name);
    }
    _require(
      jsonDecode(utf8.decode(baseline['tandemlog-space.json']!))['v'] == 3,
      'Fixture must be legitimate v3',
    );
    report['baseline'] = {
      for (final e in baseline.entries) e.key: _seal(e.value),
    };
    report['baselineProjection'] = beforeProjection;
    await food.close();
    food = null;
    await tasks.close();
    tasks = null;
    step(
      'Production commands created native Tasks, checklist and Food v3 fixture',
    );

    Map<String, dynamic> journal() {
      final row = activeProfile!.database.select(
        'SELECT plan FROM protected_app_migrations WHERE space=?',
        [space],
      ).single;
      return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(row['plan'] as List<int>)) as Map,
      );
    }

    final folder = _InterruptedSaf(realFolder, journal, faults);
    var upgrade = await WorkspaceUpgrade.start(
      folder: folder,
      profile: activeProfile,
      writer: writer,
      participants: {writer},
      textEngine: engine,
    );
    _require(
      upgrade.hasLocalConsent,
      'Coordinator consent must be durably recorded',
    );
    await upgrade.consentToUpgrade();
    await upgrade.acknowledgeInput();
    _require(
      upgrade.inputAcknowledged.contains(writer),
      'Actual local input acknowledgement missing',
    );

    Future<void> interrupt(
      String phase,
      Future<void> Function() operation,
    ) async {
      folder.armed = phase;
      OwnedReplacementFailure? observed;
      try {
        await operation();
      } on OwnedReplacementFailure catch (failure) {
        observed = failure;
      }
      _require(
        observed?.phase == 'qa_controlled_interruption' &&
            observed?.mayHaveChanged == true &&
            folder.armed == null,
        'Expected controlled uncertain replacement was not observed',
      );
      final intent = journal()['replacement'] as Map;
      final desired = base64Decode(intent['desired'] as String);
      final partial = await realFolder.read('tandemlog-space.json');
      _require(
        partial.length < desired.length &&
            _equal(partial, desired.take(partial.length).toList()),
        'Real provider did not retain intended partial bytes',
      );
      await File(
        '${root.path}/$phase-partial-manifest.bin',
      ).writeAsBytes(partial, flush: true);
      await activeProfile!.close();
      activeProfile = null;
      activeProfile = await LocalProfileDatabase.open(profileRoot);
      await LocalProfileMigration(activeProfile!).run();
      settings = LocalSettings(profileRoot, profileDatabase: activeProfile);
      await settings.load();
      _require(
        settings.writer == writer,
        'Protected writer changed across cold SQLite reopen',
      );
      _require(
        base64Encode(
              activeProfile!.database
                      .select('SELECT raw FROM protected_settings')
                      .single['raw']
                  as List<int>,
            ) ==
            settingsBytes,
        'Protected settings changed across recovery',
      );
      upgrade = (await WorkspaceUpgrade.open(
        folder: folder,
        profile: activeProfile!,
        writer: writer,
        textEngine: engine,
      ))!;
      _require(
        phase == 'staging'
            ? upgrade.canResumeStaging
            : upgrade.canResumeActivation,
        'Cold core did not offer the journaled recovery phase',
      );
      if (phase == 'staging') {
        await upgrade.stage();
      } else {
        await upgrade.activate();
      }
      _require(
        _equal(await realFolder.read('tandemlog-space.json'), desired),
        'Recovery differs from exact journaled desired manifest',
      );
      step(
        'Recovered $phase after real SAF prefix write and cold SQLite reopen',
      );
    }

    await interrupt('staging', () => upgrade.stage());
    _require(
      upgrade.phase == 'staged',
      'Expected staged manifest after recovery',
    );
    await upgrade.acknowledgeOutput();
    _require(
      upgrade.outputAcknowledged.contains(writer),
      'Actual output acknowledgement missing',
    );
    await interrupt('activating', () => upgrade.activate());
    _require(
      upgrade.phase == 'ready',
      'Expected ready manifest after recovery',
    );
    final convertedFiles = <String, List<int>>{
      for (final entry in upgrade.conversion.files.entries)
        entry.key: entry.value,
    };
    for (final entry in convertedFiles.entries) {
      _require(
        _equal(await realFolder.read(entry.key), entry.value),
        'Converted history differs from sealed output',
      );
    }
    final saved = journal();
    _require(
      _equal(
        base64Decode(saved['manifest'] as String),
        baseline['tandemlog-space.json'],
      ),
      'Original manifest backup differs',
    );
    final legacyNames =
        baseline.keys.where((name) => name != 'tandemlog-space.json').toList()
          ..sort();
    final backupNames = (saved['sources'] as Map).keys.cast<String>().toList()
      ..sort();
    _require(
      _equal(backupNames, legacyNames),
      'Protected backup source inventory differs',
    );
    for (final entry in (saved['sources'] as Map).entries) {
      _require(
        _equal(base64Decode(entry.value as String), baseline[entry.key]),
        'Saved legacy source backup differs',
      );
    }
    await upgrade.complete();
    _require(upgrade.phase == 'complete', 'Upgrade did not finish');
    _require(
      !WorkspaceUpgrade.isFrozen(activeProfile!, space),
      'Profile remained frozen',
    );
    history = await UnifiedHistory.open(
      realFolder,
      profile: activeProfile!,
      writer: writer,
      textEngine: engine,
    );
    tasks = await TaskStore.openUnified(history);
    food = await FoodStore.openUnified(history);
    _require(
      _equal(projection(), beforeProjection),
      'Task/Food views or full native text fields changed',
    );
    _require(!history.hasPending, 'Unexpected pending unified write');
    for (final entry in baseline.entries.where(
      (e) => e.key != 'tandemlog-space.json',
    )) {
      _require(
        _equal(await realFolder.read(entry.key), entry.value),
        'Original legacy bytes changed',
      );
    }
    final after = <String, Object?>{};
    for (final info in await realFolder.list()) {
      final bytes = await realFolder.read(info.name);
      after[info.name] = _seal(bytes);
      if (info.name.endsWith('.applog')) {
        _require(
          convertedFiles.containsKey(info.name),
          'Unexpected duplicate writer output',
        );
        _require(
          _equal(bytes, convertedFiles[info.name]),
          'Completion appended unexpected history',
        );
      }
    }
    _require(
      base64Encode(
            activeProfile!.database
                    .select('SELECT raw FROM protected_settings')
                    .single['raw']
                as List<int>,
          ) ==
          settingsBytes,
      'Completion changed protected settings',
    );
    _require(
      LocalSettings.protectedValues(activeProfile!)['writer'] == writer,
      'Completion changed protected writer',
    );
    report['after'] = after;
    report['writerPreserved'] = true;
    report['settingsRawPreserved'] = true;
    report['legacyBytesAndProtectedBackupExact'] = true;
    report['taskFoodAndFullNativeTextProjectionExact'] = true;
    report['sealedConvertedOutputsExactNoDuplicateWrites'] = true;
    _require(
      faults.length == 2 &&
          faults.every(
            (f) => f['checkedTransportPrefixReplacementConfirmed'] == true,
          ),
      'Both checked transport interruption cases required',
    );
    step(
      'Both recoveries preserve exact history, native text, views, settings and writer',
    );
    report['passed'] = true;
  } catch (error, stack) {
    report['errorType'] = error.runtimeType.toString();
    report['error'] = error.toString();
    report['stack'] = stack.toString();
    progress('FAILED; private evidence retained');
  } finally {
    // Each handle is closed even when another close fails; never erase evidence.
    final cleanup = <String, Object?>{};
    for (final entry in <String, Future<void> Function()>{
      'food': () async {
        await food?.close();
      },
      'tasks': () async {
        await tasks?.close();
      },
      'history': () async {
        await history?.close();
      },
      'profile': () async {
        await activeProfile?.close();
      },
    }.entries) {
      try {
        await entry.value();
        cleanup[entry.key] = true;
      } catch (error) {
        cleanup[entry.key] = error.runtimeType.toString();
        report['passed'] = false;
      }
    }
    try {
      engine?.dispose();
      cleanup['nativeEngine'] = true;
    } catch (error) {
      cleanup['nativeEngine'] = error.runtimeType.toString();
      report['passed'] = false;
    }
    report['actualAndroidSafAcceptance'] =
        report['passed'] == true && Platform.isAndroid;
    report['cleanup'] = cleanup;
    report['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();
    await File('${root.path}/report.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      flush: true,
    );
  }
  return report;
}
