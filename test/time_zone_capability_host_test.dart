import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/domain/time_zone_policy.dart';
import 'package:tandemlog/domain/wall_time.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/form_validation.dart';
import 'package:tandemlog/presentation/section_menu.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_trial.dart';

import 'section_navigation_host_test.dart' as host;
import 'unified_host_test.dart' as unified;

/// Real synthetic files and checked replacement. The optional partial write is
/// a controlled non-atomic provider interruption, not actual Android SAF proof.
/// Omitting watch hints keeps reconciliation deterministic in this host test.
class _CapabilityFolder
    implements LogFolder, BoundedLogFolder, RecoverableReplaceLogFolder {
  _CapabilityFolder(this.inner);
  final LocalLogFolder inner;
  int? replacementCut, appendCut;
  int replacements = 0, recoveries = 0, appends = 0, creates = 0;
  int manifestReads = 0;
  int get mutations => replacements + recoveries + appends + creates;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) {
    if (name == 'tandemlog-space.json') manifestReads++;
    return inner.readBounded(name, maximumBytes);
  }

  @override
  Future<void> create(String name, Uint8List bytes) {
    creates++;
    return inner.create(name, bytes);
  }

  @override
  Future<void> append(String name, Uint8List bytes) async {
    appends++;
    final cut = appendCut;
    appendCut = null;
    if (cut == null) return inner.append(name, bytes);
    await inner.append(name, Uint8List.fromList(bytes.take(cut).toList()));
    throw const FileSystemException('Synthetic pending-save interruption');
  }

  @override
  Future<void> checkReplacementSupport(String name, int maximumBytes) =>
      inner.checkReplacementSupport(name, maximumBytes);
  @override
  Future<void> replaceOwned(
    String name,
    Uint8List expected,
    Uint8List desired,
  ) async {
    replacements++;
    final cut = replacementCut;
    replacementCut = null;
    if (cut == null) return inner.replaceOwned(name, expected, desired);
    final actual = await inner.read(name);
    if (actual.length != expected.length ||
        Iterable<int>.generate(
          actual.length,
        ).any((index) => actual[index] != expected[index])) {
      throw StateError(
        'Controlled replacement base differs from exact expected bytes.',
      );
    }
    // The production controller must have committed its replacing journal.
    await inner
        .file(name)
        .writeAsBytes(desired.take(cut).toList(), flush: true);
    throw OwnedReplacementFailure(
      'Synthetic partial capability manifest',
      phase: 'write',
      mayHaveChanged: true,
    );
  }

  @override
  Future<void> recoverOwned(
    String name,
    Uint8List expected,
    Uint8List desired,
  ) {
    recoveries++;
    return inner.recoverOwned(name, expected, desired);
  }
}

typedef _Fixture = ({UnifiedTrial trial, String profile, String writer});

/// Pump real I/O and FakeAsync together: a previously accepted host queue
/// continuation may still belong to the fake zone.
Future<void> _work(WidgetTester tester, Future<void> Function() action) async {
  var done = false;
  Object? failure;
  StackTrace? trace;
  await tester.runAsync(() async {
    unawaited(
      Future<void>.sync(action).then<void>(
        (_) => done = true,
        onError: (Object error, StackTrace stack) {
          failure = error;
          trace = stack;
          done = true;
        },
      ),
    );
  });
  await host.ready(tester, () => done, settle: false);
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  await tester.pumpAndSettle();
}

Future<void> _settings(WidgetTester tester) async {
  final identity = find.byKey(const ValueKey('identity-menu'));
  if (identity.evaluate().isEmpty) {
    // Before the first user, the actual toolbar presents a Settings icon.
    await tester.tap(find.byTooltip('Settings'));
  } else {
    tester.widget<PopupMenuButton<String>>(identity).onSelected!('settings');
  }
  await host.ready(
    tester,
    () => find
        .byKey(const ValueKey('additional-time-zones-setting'))
        .evaluate()
        .isNotEmpty,
  );
}

Future<void> _confirmation(WidgetTester tester) async {
  await _settings(tester);
  final setting = find.byKey(const ValueKey('additional-time-zones-setting'));
  expect(tester.widget<ListTile>(setting).enabled, isTrue);
  await tester.ensureVisible(setting);
  await tester.tap(setting);
  await host.ready(
    tester,
    () => find
        .byKey(const ValueKey('additional-time-zones-enable'))
        .evaluate()
        .isNotEmpty,
  );
}

Future<void> _answer(WidgetTester tester, bool enable) async {
  await tester.tap(
    find.byKey(
      ValueKey(
        enable ? 'additional-time-zones-enable' : 'additional-time-zones-later',
      ),
    ),
  );
  await tester.pump();
}

class _Harness {
  _Harness(this.data, this.folder);
  final _Fixture data;
  final _CapabilityFolder folder;
  dynamic state;
  bool mounted = false;
  TaskStore get tasks => state.store as TaskStore;
  UnifiedHistory get history => tasks.unified!;
  String get taskId =>
      tasks.rows.singleWhere((r) => r['kind'] == 'task')['id'] as String;

  static Future<_Harness> open(WidgetTester tester) async {
    final data = (await tester.runAsync(unified.unifiedFixture))!;
    final harness = _Harness(data, _CapabilityFolder(data.trial.folder));
    await harness.start(tester);
    return harness;
  }

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(
      TandemlogApp(
        profilePath: data.profile,
        folderFactory: (_) => folder,
        textEngineFactory: host.createHostTextEngine,
        timeSourceFactory: host.createHostTimeSource,
      ),
    );
    mounted = true;
    state = tester.state(find.byType(TasksPage)) as dynamic;
    await host.ready(
      tester,
      () =>
          state.store != null &&
          state.foodStore != null &&
          state.busy == false &&
          state.syncing == null,
    );
    expect(state.error, isNull);
    expect(state.sharedSafetyError, isNull);
    state.importer.stop();
  }

  Future<void> stop(WidgetTester tester) async {
    if (!mounted) return;
    final resources = host.hostResources(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await host.waitForHostShutdown(tester, resources);
    mounted = false;
  }

  Future<void> dispose(WidgetTester tester) async {
    await stop(tester);
    await tester.runAsync(() async {
      await data.trial.close();
      await data.trial.root.delete(recursive: true);
    });
  }

  Future<Map<String, List<int>>> bytes(WidgetTester tester) async =>
      (await tester.runAsync(() => host.canonical(data.trial.folder)))!;
  String get protectedManifest =>
      state.profileDatabase.database.select(
            'SELECT manifest FROM protected_app_workspaces WHERE space=?',
            [history.manifest.space],
          ).single['manifest']
          as String;
  List<List<int>> get journals => [
    for (final row in state.profileDatabase.database.select(
      'SELECT journal FROM protected_workspace_capabilities',
    ))
      List<int>.of(row['journal'] as List<int>),
  ];
  List<String> get phases => [
    for (final row in state.profileDatabase.database.select(
      'SELECT state FROM protected_workspace_capabilities',
    ))
      row['state'] as String,
  ];
}

Future<_Fixture> _emptyUnifiedFixture() async {
  // Empty canonical legacy sources are valid conversion inputs. Trial APIs
  // create, validate, acknowledge and activate the complete synthetic output;
  // no existing log/profile is rewritten to remove users.
  final writer = const Uuid().v4();
  final trial = await UnifiedTrial.createSynthetic(
    space: const Uuid().v4(),
    owners: {writer},
    participants: {writer},
    sources: const {},
  );
  final engine = NativeTextEngine(libraryPath: host.nativeHostLibraryPath);
  try {
    await trial.acknowledgeInput(writer, textEngine: engine);
    await trial.stage();
    await trial.acknowledgeOutput(writer, textEngine: engine);
    await trial.activate(textEngine: engine);
    await trial.retireSyntheticSources();
  } finally {
    engine.dispose();
  }
  final profile = trial.profileRoot(writer);
  final db = await trial.openParticipant(writer);
  try {
    final settings = LocalSettings(profile, profileDatabase: db);
    await settings.load();
    settings.folder = trial.folder.location;
    settings.user = null;
    await settings.save();
  } finally {
    await db.close();
  }
  return (trial: trial, profile: profile, writer: writer);
}

Finder _field(String key) => find.byKey(ValueKey(key), skipOffstage: false);

class _Draft {
  _Draft(
    this.editor,
    this.editorKey,
    this.session,
    this.capture,
    this.notes,
    this.zone,
    this.focus,
    this.notesValue,
    this.zoneValue,
  );
  final TaskEditorState editor;
  final Object editorKey, session, capture;
  final TextEditingController notes, zone;
  final FocusNode focus;
  final TextEditingValue notesValue, zoneValue;

  static Future<_Draft> open(WidgetTester tester, _Harness harness) async {
    await tester.tap(find.byKey(ValueKey('task-title-${harness.taskId}')));
    await host.ready(
      tester,
      () =>
          _field('description').evaluate().isNotEmpty &&
          harness.state.editingText != null &&
          harness.state.syncing == null,
    );
    for (final entry in {
      'dueDate': '2026-11-02',
      'dueTime': '09:00',
      'timeZone': 'CST6CDT',
      'description': 'Keep this native draft exactly',
    }.entries) {
      await tester.ensureVisible(_field(entry.key));
      await tester.enterText(_field(entry.key), entry.value);
    }
    await tester.pumpAndSettle();
    final notes = tester.widget<TextField>(_field('description')).controller!;
    notes.selection = const TextSelection(baseOffset: 5, extentOffset: 16);
    final zone = tester.widget<TextField>(_field('timeZone')).controller!;
    final focus = tester
        .widget<EditableText>(
          find.descendant(
            of: _field('description'),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode;
    expect(focus.hasFocus, isTrue);
    expect(
      tester.widget<TaskEditor>(find.byType(TaskEditor)).timeZonePolicy,
      TimeZoneNamePolicy.legacy,
    );
    expect(
      tester.widget<TextField>(_field('timeZone')).decoration!.errorText,
      timeZoneUpgradeRequiredMessage,
    );
    return _Draft(
      tester.state<TaskEditorState>(find.byType(TaskEditor)),
      harness.state.editorKey as Object,
      harness.state.editingText as Object,
      harness.state.editingText.capture as Object,
      notes,
      zone,
      focus,
      notes.value,
      zone.value,
    );
  }

  void expectExact(
    WidgetTester tester,
    _Harness harness, {
    bool focused = true,
  }) {
    expect(
      identical(
        tester.state<TaskEditorState>(
          find.byType(TaskEditor, skipOffstage: false),
        ),
        editor,
      ),
      isTrue,
    );
    expect(identical(harness.state.editorKey, editorKey), isTrue);
    expect(identical(harness.state.editingText, session), isTrue);
    expect(identical(harness.state.editingText.capture, capture), isTrue);
    expect(
      identical(
        tester.widget<TextField>(_field('description')).controller,
        notes,
      ),
      isTrue,
    );
    expect(
      identical(tester.widget<TextField>(_field('timeZone')).controller, zone),
      isTrue,
    );
    expect(
      identical(
        tester.widget<TextField>(_field('description')).focusNode,
        focus,
      ),
      isTrue,
    );
    expect(notes.value, notesValue);
    expect(zone.value, zoneValue);
    expect(
      tester.widget<TextField>(_field('dueDate')).controller!.text,
      '2026-11-02',
    );
    expect(
      tester.widget<TextField>(_field('dueTime')).controller!.text,
      '09:00',
    );
    expect(focus.hasFocus, focused);
  }
}

void _expectControlledInterruption(_Harness harness) {
  expect(
    harness.state.sharedSafetyError,
    contains('Synthetic partial capability manifest'),
    reason: jsonEncode({
      'sharedSafetyError': harness.state.sharedSafetyError,
      'coordinatorFailure': harness.history.safetyFailure.toString(),
      'replacements': harness.folder.replacements,
      'recoveries': harness.folder.recoveries,
      'replacementCutStillArmed': harness.folder.replacementCut,
    }),
  );
  expect(harness.folder.replacements, 1);
  expect(harness.folder.replacementCut, isNull);
}

void main() {
  final library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];
  if (library == null || library.isEmpty || !File(library).existsSync()) {
    throw StateError(
      'Capability host regressions require the real native text library.',
    );
  }
  host.nativeHostLibraryPath = File(library).absolute.path;

  Future<void> wide(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1100);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'Later and live Enable preserve alias draft; one Save survives reopen',
    (tester) async {
      await wide(tester);
      final harness = await _Harness.open(tester);
      try {
        final draft = await _Draft.open(tester, harness);
        final original = await harness.bytes(tester);
        final store = harness.tasks, history = harness.history;
        await _confirmation(tester);
        await _answer(tester, false);
        await host.ready(
          tester,
          () =>
              harness.state.busy == false &&
              find
                  .byKey(const ValueKey('additional-time-zones-later'))
                  .evaluate()
                  .isEmpty,
        );
        draft.expectExact(tester, harness);
        expect(await harness.bytes(tester), original);
        expect(harness.phases, isEmpty);
        expect(harness.folder.mutations, 0);
        await _confirmation(tester);
        await _answer(tester, true);
        await host.ready(
          tester,
          () =>
              history.manifest.additionalTimeZonesEnabled &&
              harness.state.busy == false &&
              harness.state.syncing == null,
        );
        draft.expectExact(tester, harness);
        expect(identical(harness.tasks, store), isTrue);
        expect(identical(harness.history, history), isTrue);
        expect(
          tester.widget<TaskEditor>(find.byType(TaskEditor)).timeZonePolicy,
          TimeZoneNamePolicy.additional2026eV1,
        );
        expect(
          tester.widget<TextField>(_field('timeZone')).decoration!.errorText,
          isNull,
        );
        final enabled = await harness.bytes(tester);
        expect(
          {...enabled}..remove('tandemlog-space.json'),
          {...original}..remove('tandemlog-space.json'),
        );
        expect(
          enabled['tandemlog-space.json'],
          isNot(original['tandemlog-space.json']),
        );
        expect(harness.phases, ['complete']);
        final sequence = history.physicalSequence;
        final action = find.descendant(
          of: find.byType(ValidationActionButton),
          matching: find.byType(FilledButton),
        );
        await tester.ensureVisible(action);
        final submit = tester.widget<FilledButton>(action).onPressed!;
        submit();
        submit();
        await host.ready(
          tester,
          () =>
              harness.state.busy == false &&
              harness.tasks.rows.singleWhere(
                    (r) => r['id'] == harness.taskId,
                  )['schedule']['timeZone'] ==
                  'CST6CDT',
        );
        final appended = history.snapshot.records
            .where((r) => r.writer == history.writer && r.sequence > sequence)
            .toList();
        expect(appended, isNotEmpty);
        expect(
          appended.map((r) => r.transactionStart).toSet(),
          hasLength(1),
          reason:
              'Repeated primary callback must accept only one durable Save.',
        );
        final saved = await harness.bytes(tester);
        final id = harness.taskId;
        await harness.stop(tester);
        await harness.start(tester);
        final row = harness.tasks.rows.singleWhere((r) => r['id'] == id);
        expect(row['schedule']['timeZone'], 'CST6CDT');
        expect(row['description'], draft.notesValue.text);
        expect(harness.history.manifest.additionalTimeZonesEnabled, isTrue);
        expect(await harness.bytes(tester), saved);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'own durable pending save disables capability activation without writes',
    (tester) async {
      await wide(tester);
      final harness = await _Harness.open(tester);
      try {
        harness.folder.appendCut = 7;
        await expectLater(
          _work(tester, () async {
            await harness.history.renameDevice('Interrupted own save');
          }),
          throwsA(isA<FileSystemException>()),
        );
        await host.ready(tester, () => harness.state.busy == false);
        expect(harness.history.hasPending, isTrue);
        final before = await harness.bytes(tester);
        final mutations = harness.folder.mutations;
        // Isolate the pending-save gate: successful admission clears the shared
        // failure but must not retry the physical append or retire its receipt.
        await tester.tap(find.byKey(const ValueKey('retry-shared-read')));
        await host.ready(
          tester,
          () =>
              harness.state.busy == false &&
              harness.state.sharedSafetyError == null,
        );
        expect(harness.history.safetyFailure, isNull);
        expect(harness.history.hasPending, isTrue);
        expect(harness.folder.mutations, mutations);
        expect(await harness.bytes(tester), before);
        await _settings(tester);
        final setting = find.byKey(
          const ValueKey('additional-time-zones-setting'),
        );
        expect(tester.widget<ListTile>(setting).enabled, isFalse);
        await tester.tap(find.widgetWithText(TextButton, 'Done'));
        await tester.pumpAndSettle();
        expect(harness.phases, isEmpty);
        expect(harness.folder.mutations, mutations);
        expect(await harness.bytes(tester), before);
        expect(harness.history.manifest.additionalTimeZonesEnabled, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'enabled workspace never grants another host workspace alias permission',
    (tester) async {
      await wide(tester);
      final enabled = await _Harness.open(tester);
      _Harness? legacy;
      try {
        await _confirmation(tester);
        await _answer(tester, true);
        await host.ready(
          tester,
          () =>
              enabled.history.manifest.additionalTimeZonesEnabled &&
              enabled.state.busy == false,
        );
        final firstBytes = await enabled.bytes(tester);
        final firstSpace = enabled.history.manifest.space;
        await enabled.stop(tester);
        final second = legacy = await _Harness.open(tester);
        expect(second.history.manifest.space, isNot(firstSpace));
        final draft = await _Draft.open(tester, second);
        final before = await second.bytes(tester);
        final primary = find.descendant(
          of: find.byType(ValidationActionButton),
          matching: find.byType(FilledButton),
        );
        await tester.ensureVisible(primary);
        await tester.tap(primary);
        await tester.pumpAndSettle();
        expect(second.history.hasPending, isFalse);
        expect(second.history.manifest.additionalTimeZonesEnabled, isFalse);
        expect(
          tester.widget<TaskEditor>(find.byType(TaskEditor)).timeZonePolicy,
          TimeZoneNamePolicy.legacy,
        );
        expect(draft.zone.text, 'CST6CDT');
        expect(
          tester.widget<TextField>(_field('timeZone')).decoration!.errorText,
          timeZoneUpgradeRequiredMessage,
        );
        expect(await second.bytes(tester), before);
        expect(await enabled.bytes(tester), firstBytes);
        expect(second.phases, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        if (legacy != null) await legacy.dispose(tester);
        await enabled.dispose(tester);
      }
    },
  );

  testWidgets(
    'partial activation blocks both sections; read Retry never repairs; Resume retains draft',
    (tester) async {
      await wide(tester);
      final harness = await _Harness.open(tester);
      try {
        final draft = await _Draft.open(tester, harness);
        final original = await harness.bytes(tester);
        final store = harness.tasks, history = harness.history;
        final protectedBefore = harness.protectedManifest;
        harness.folder.replacementCut = 31;
        await _confirmation(tester);
        await _answer(tester, true);
        await host.ready(
          tester,
          () =>
              harness.state.sharedSafetyError != null &&
              harness.state.busy == false,
        );
        _expectControlledInterruption(harness);
        draft.expectExact(tester, harness, focused: false);
        expect(history.manifest.additionalTimeZonesEnabled, isFalse);
        expect(harness.phases, ['replacing']);
        final retainedJournal = harness.journals;
        expect(harness.protectedManifest, protectedBefore);
        expect(harness.state.workspaceState.health.taskWriteReady, isFalse);
        expect(harness.state.workspaceState.health.foodWriteReady, isFalse);
        // The stopped Tasks surface removes its command toolbar entirely.
        // Both module write lanes remain blocked behind the recovery overlay.
        expect(find.byType(SectionMenu), findsNothing);
        expect(find.text('Workspace requires recovery'), findsOneWidget);
        final partial = await harness.bytes(tester);
        expect(partial['tandemlog-space.json'], hasLength(31));
        expect(
          {...partial}..remove('tandemlog-space.json'),
          {...original}..remove('tandemlog-space.json'),
        );
        final mutations = harness.folder.mutations;
        await tester.tap(find.byKey(const ValueKey('retry-shared-read')));
        await host.ready(
          tester,
          () => harness.state.busy == false && harness.state.syncing == null,
        );
        expect(harness.state.sharedSafetyError, isNotNull);
        expect(harness.folder.mutations, mutations);
        expect(await harness.bytes(tester), partial);
        expect(harness.phases, ['replacing']);
        expect(harness.journals, retainedJournal);
        expect(harness.protectedManifest, protectedBefore);
        draft.expectExact(tester, harness, focused: false);
        // The stopped Tasks toolbar is absent. Recovery must expose a real
        // Settings route so this same live draft can explicitly Resume.
        final recoverySettings = find.byKey(
          const ValueKey('shared-recovery-settings'),
        );
        expect(recoverySettings.hitTestable(), findsOneWidget);
        expect(
          tester.widget<TextButton>(recoverySettings).onPressed,
          isNotNull,
        );
        await tester.tap(recoverySettings);
        await host.ready(
          tester,
          () => find
              .byKey(const ValueKey('additional-time-zones-setting'))
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('Resume time zone update…'), findsOneWidget);
        final resume = find.byKey(
          const ValueKey('additional-time-zones-setting'),
        );
        expect(tester.widget<ListTile>(resume).enabled, isTrue);
        await tester.ensureVisible(resume);
        await tester.tap(resume);
        await host.ready(
          tester,
          () =>
              harness.state.busy == false &&
              harness.state.sharedSafetyError == null &&
              history.manifest.additionalTimeZonesEnabled,
        );
        // Recovery controls are now the user's focus choice. Re-enabling the
        // stopped body must not silently request focus back into the editor.
        draft.expectExact(tester, harness, focused: false);
        expect(identical(harness.tasks, store), isTrue);
        expect(identical(harness.history, history), isTrue);
        expect(harness.folder.recoveries, 1);
        expect(harness.phases, ['complete']);
        expect(
          tester.widget<TaskEditor>(find.byType(TaskEditor)).timeZonePolicy,
          TimeZoneNamePolicy.additional2026eV1,
        );
        final recovered = await harness.bytes(tester);
        expect(
          {...recovered}..remove('tandemlog-space.json'),
          {...original}..remove('tandemlog-space.json'),
        );
        final manifest =
            jsonDecode(utf8.decode(recovered['tandemlog-space.json']!)) as Map;
        expect(manifest.containsKey('requiredCapabilities'), isTrue);
        // A fresh visible field tap is an explicit choice to resume typing.
        // Compare the original selection above, before that click can move it.
        await tester.ensureVisible(_field('description'));
        await tester.tap(_field('description'));
        await tester.pumpAndSettle();
        expect(draft.focus.hasFocus, isTrue);
        expect(draft.notes.text, draft.notesValue.text);
        tester.testTextInput.updateEditingValue(draft.notesValue);
        await tester.pump();
        draft.expectExact(tester, harness);
        expect(tester.takeException(), isNull);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets(
    'zero-user setup keeps exact name draft and can explicitly Resume a partial activation',
    (tester) async {
      await wide(tester);
      final data = (await tester.runAsync(_emptyUnifiedFixture))!;
      final harness = _Harness(data, _CapabilityFolder(data.trial.folder));
      try {
        await harness.start(tester);
        expect(harness.state.user, isNull);
        expect(
          harness.tasks.rows.where((row) => row['kind'] == 'user'),
          isEmpty,
        );
        final nameField = find.widgetWithText(TextField, 'Your name');
        await tester.enterText(nameField, 'Synthetic unfinished name');
        final controller = tester.widget<TextField>(nameField).controller!;
        controller.selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 12,
        );
        final value = controller.value;
        final focus = tester
            .widget<EditableText>(
              find.descendant(
                of: nameField,
                matching: find.byType(EditableText),
              ),
            )
            .focusNode;
        expect(focus.hasFocus, isTrue);
        void expectNameKept({bool focused = true}) {
          expect(identical(harness.state.firstName, controller), isTrue);
          expect(
            identical(
              tester.widget<TextField>(nameField).controller,
              controller,
            ),
            isTrue,
          );
          expect(identical(harness.state.firstNameFocus, focus), isTrue);
          expect(
            identical(tester.widget<TextField>(nameField).focusNode, focus),
            isTrue,
          );
          expect(controller.value, value);
          expect(focus.hasFocus, focused);
          expect(harness.state.user, isNull);
          expect(harness.state.pendingUserId, isNull);
          expect(
            harness.tasks.rows.where((row) => row['kind'] == 'user'),
            isEmpty,
          );
        }

        final original = await harness.bytes(tester);
        final protectedBefore = harness.protectedManifest;
        harness.folder.replacementCut = 31;
        await _confirmation(tester);
        await _answer(tester, true);
        await host.ready(
          tester,
          () =>
              harness.state.sharedSafetyError != null &&
              harness.state.busy == false,
        );
        _expectControlledInterruption(harness);
        expectNameKept();
        expect(harness.phases, ['replacing']);
        final partial = await harness.bytes(tester);
        final journal = harness.journals;
        final mutations = harness.folder.mutations;
        expect(partial['tandemlog-space.json'], hasLength(31));
        expect(
          {...partial}..remove('tandemlog-space.json'),
          {...original}..remove('tandemlog-space.json'),
        );
        expect(harness.protectedManifest, protectedBefore);
        expect(harness.history.hasPending, isFalse);
        // Setup remains visible rather than being replaced with the normal
        // recovery overlay. Its Continue action may only retry admission.
        expect(find.text('Workspace requires recovery'), findsNothing);
        final continueAction = find.widgetWithText(FilledButton, 'Continue');
        await tester.ensureVisible(continueAction);
        final beforeContinueReads = harness.folder.manifestReads;
        await tester.tap(continueAction);
        await host.ready(
          tester,
          () =>
              harness.folder.manifestReads > beforeContinueReads &&
              harness.state.busy == false &&
              harness.state.syncing == null,
        );
        expectNameKept(focused: false);
        expect(harness.state.sharedSafetyError, isNotNull);
        expect(harness.history.hasPending, isFalse);
        expect(harness.folder.mutations, mutations);
        expect(await harness.bytes(tester), partial);
        expect(harness.journals, journal);
        expect(harness.protectedManifest, protectedBefore);

        final retry = find.widgetWithText(TextButton, 'Retry');
        expect(retry, findsOneWidget);
        await tester.ensureVisible(retry);
        final beforeRetryReads = harness.folder.manifestReads;
        await tester.tap(retry);
        await host.ready(
          tester,
          () =>
              harness.folder.manifestReads > beforeRetryReads &&
              harness.state.busy == false &&
              harness.state.syncing == null,
        );
        expectNameKept(focused: false);
        expect(harness.folder.mutations, mutations);
        expect(await harness.bytes(tester), partial);
        expect(harness.journals, journal);
        expect(harness.protectedManifest, protectedBefore);

        final recoverySettings = find.byKey(
          const ValueKey('shared-recovery-settings'),
        );
        expect(recoverySettings.hitTestable(), findsOneWidget);
        await tester.tap(recoverySettings);
        await host.ready(
          tester,
          () => find
              .byKey(const ValueKey('additional-time-zones-setting'))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          tester
              .widget<ListTile>(find.widgetWithText(ListTile, 'Theme'))
              .enabled,
          isFalse,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Open data folder'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Use a different folder'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('check-data-integrity')),
              )
              .onPressed,
          isNull,
        );
        final resume = find.byKey(
          const ValueKey('additional-time-zones-setting'),
        );
        expect(tester.widget<ListTile>(resume).enabled, isTrue);
        expect(find.text('Resume time zone update…'), findsOneWidget);
        await tester.ensureVisible(resume);
        await tester.tap(resume);
        await host.ready(
          tester,
          () =>
              harness.state.sharedSafetyError == null &&
              harness.state.busy == false &&
              harness.history.manifest.additionalTimeZonesEnabled,
        );
        expectNameKept(focused: false);
        expect(harness.phases, ['complete']);
        expect(harness.folder.recoveries, 1);
        final resumed = await harness.bytes(tester);
        expect(
          {...resumed}..remove('tandemlog-space.json'),
          {...original}..remove('tandemlog-space.json'),
        );
        expect(harness.history.hasPending, isFalse);
        // User selection after a new field tap is distinct from preserving the
        // selection before recovery; the application never steals focus late.
        await tester.ensureVisible(nameField);
        await tester.tap(nameField);
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        expect(controller.text, value.text);
        tester.testTextInput.updateEditingValue(value);
        await tester.pump();
        expectNameKept();
        expect(tester.takeException(), isNull);
      } finally {
        await harness.dispose(tester);
      }
    },
  );
}
