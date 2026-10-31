import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'application/undo_history.dart';
import 'presentation/activity_log.dart';
import 'application/food_undo_history.dart';
import 'application/task_text_session.dart';
import 'application/text_save_command.dart';
import 'application/checklist_completion_command.dart';
import 'application/workspace_session.dart';
import 'text/native_text_engine.dart';
import 'text/native_text_licenses.dart';
import 'domain/visible_task_move.dart';
import 'domain/event.dart' show LogEvent;
import 'presentation/editor_surface.dart';
import 'presentation/tandemlog_theme.dart';
import 'presentation/unavailable_completion.dart';
import 'presentation/task_completion_checkbox.dart';
import 'presentation/task_entry_area.dart';
import 'presentation/task_toolbar.dart';
import 'presentation/toolbar_action.dart';
import 'presentation/section_menu.dart';
import 'presentation/section_content.dart';
import 'presentation/list_row_surface.dart';
import 'presentation/list_selection.dart';
import 'presentation/task_drop_indicator.dart';
import 'presentation/sticky_task_group.dart';
import 'domain/task_view.dart';
import 'domain/schedule.dart' show formatCivilDate;
import 'domain/timed_view.dart';
import 'domain/time_zone_policy.dart';
import 'presentation/view_clock.dart';
import 'presentation/task_metadata.dart';
import 'presentation/tag_filter_picker.dart';
import 'presentation/task_editor.dart';
import 'presentation/form_validation.dart';
import 'presentation/name_entry_dialog.dart';
import 'presentation/device_name_dialog.dart';
import 'presentation/checklist_panel.dart';
import 'presentation/checklist_disclosure_ink_border.dart';
import 'presentation/task_actions_menu.dart';
import 'presentation/checklist_item_editor.dart';
import 'presentation/failure_message.dart';
import 'presentation/release_version_tile.dart';
import 'platform/view_time_source.dart';
import 'platform/log_folder.dart';
import 'platform/folder_actions.dart';
import 'platform/foreground_importer.dart';
import 'platform/android_section_navigation.dart';
import 'storage/local_settings.dart';
import 'storage/local_durability.dart';
import 'storage/local_profile_database.dart';
import 'storage/task_store.dart';
import 'storage/workspace_state.dart';
import 'storage/checklist_expansion_store.dart';
import 'food/food_page.dart';
import 'food/food_store.dart';
import 'food/food_record.dart';
import 'food/inventory.dart' show FoodContainer;

void main() {
  debugPrint('TANDEMLOG_MAIN');
  WidgetsFlutterBinding.ensureInitialized();
  registerNativeTextLicenses();
  runApp(const TandemlogApp());
}

class TandemlogApp extends StatefulWidget {
  const TandemlogApp({
    super.key,
    this.profilePath,
    this.folderActions,
    this.timeSourceFactory,
    this.folderFactory,
    this.sectionNavigation,
    this.textEngineFactory,
  });
  final LogFolder Function(String)? folderFactory;
  final String? profilePath;
  final FolderActions? folderActions;
  final ViewTimeSource Function(void Function())? timeSourceFactory;
  final AndroidSectionNavigation? sectionNavigation;
  final NativeTextEngine Function()? textEngineFactory;
  @override
  State<TandemlogApp> createState() => _TandemlogAppState();
}

class _TandemlogAppState extends State<TandemlogApp> {
  final appearance = ValueNotifier<Appearance>(Appearance.system);
  @override
  void dispose() {
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Appearance>(
    valueListenable: appearance,
    builder: (_, value, _) => MaterialApp(
      title: 'Tandemlog',
      debugShowCheckedModeBanner: false,
      theme: tandemlogTheme(Brightness.light),
      darkTheme: tandemlogTheme(Brightness.dark),
      themeMode: switch (value) {
        Appearance.system => ThemeMode.system,
        Appearance.light => ThemeMode.light,
        Appearance.dark => ThemeMode.dark,
      },
      home: TasksPage(
        profilePath: widget.profilePath,
        appearance: appearance,
        folderActions: widget.folderActions ?? FolderActions(),
        timeSourceFactory: widget.timeSourceFactory,
        folderFactory: widget.folderFactory,
        sectionNavigation: widget.sectionNavigation,
        textEngineFactory: widget.textEngineFactory,
      ),
    ),
  );
}

class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    this.profilePath,
    required this.appearance,
    required this.folderActions,
    this.timeSourceFactory,
    this.folderFactory,
    this.sectionNavigation,
    this.textEngineFactory,
  });
  final LogFolder Function(String)? folderFactory;
  final String? profilePath;
  final ValueNotifier<Appearance> appearance;
  final FolderActions folderActions;
  final ViewTimeSource Function(void Function())? timeSourceFactory;
  final AndroidSectionNavigation? sectionNavigation;
  final NativeTextEngine Function()? textEngineFactory;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> with WidgetsBindingObserver {
  TaskStore? store;
  FoodStore? foodStore;
  bool foodVisible = false;
  AndroidSectionNavigation? sectionNavigation;
  int sectionRevision = 0;
  ({bool food, int revision, bool waitForFolderChoice})? requestedSection;
  Future<void>? sectionWork;
  String? foodError, sharedSafetyError;
  String? occurrenceMigrationError;

  final foodPageKey = GlobalKey<FoodInventoryPageState>();
  final foodUndoHistory = FoodUndoHistory();
  ({
    FoodStore origin,
    String fingerprint,
    List<FoodRecord> records,
    String verb,
    FoodUndoEntry? undoEntry,
  })?
  pendingFoodCommand;
  NativeTextEngine? textEngine;
  TaskTextSession? editingText;
  TextSaveCommand? textSaveCommand;
  String? editingTextStatus;
  final undoHistory = SessionUndoHistory();
  String? user, error;
  final selectedTags = <String>{};
  final selectedTasks = <String>{};
  bool selecting = false;
  bool mobileEditorOpen = false, wideLayout = false;
  String? selectionAnchor;
  final rowFocus = <String, FocusNode>{};
  Map<String, dynamic>? editingTask;
  List<Map<String, dynamic>>? editingBulk;
  TaskStore? editorStore;
  String? bulkSnapshot;
  List<String> bulkPending = [];
  String lastSearchText = '';
  bool closingEditor = false, bulkConflict = false;
  var editorKey = GlobalKey<TaskEditorState>();
  var bulkEditorKey = GlobalKey<BulkTaskEditorState>();
  GlobalKey<ChecklistItemEditorState>? checklistEditorKey;
  BuildContext? checklistDialogContext;
  bool openingChecklistEditor = false;
  bool checklistEditorClosing = false;
  Completer<void>? checklistEditorDone;
  Future<bool>? checklistCloseRequest;
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final bodyFocusScope = FocusScopeNode(debugLabel: 'Task and Food body');
  late bool _lastTextFocus;
  bool captureMode = false;
  String get searchQuery => captureMode ? '' : search.text.trim();
  bool get searching => searchQuery.isNotEmpty;
  List<TaskViewEntry> get visibleEntries => searching
      ? [...?taskView?.open, ...?taskView?.completed]
      : (showCompleted ? taskView?.completed : taskView?.open) ?? [];

  final taskScroll = ScrollController();
  final taskViewport = GlobalKey();
  Timer? dragScrollTimer;
  Offset? dragPointer;
  bool dragReleased = false;
  final dragScrollTick = ValueNotifier<int>(0);
  final dropKeys = <String, GlobalKey>{};
  final groupHeadingKeys = <String, GlobalKey>{};
  final taskMenuKeys = <String, GlobalKey>{};
  final checklistAddFocus = <String, FocusNode>{};
  Set<String> expandedChecklists = {};
  bool taskMenuOpen = false;
  bool busy = true, all = false, showCompleted = false, showUpcoming = false;
  bool choosingFolder = false;
  // Keep private setup input mounted and focused during additive metadata I/O.
  // This does not grant workspace permission or bypass busy command guards.
  // Consent retains command admission/lifecycle ownership without displaying
  // a running operation while the user is deciding.
  bool awaitingCompletionConfirmation = false;
  String? privateRoot;
  LocalSettings? settings;
  LocalProfileDatabase? profileDatabase;
  Future<void>? starting;
  Future<void>? _shutdownFuture;
  Future<AppExitResponse>? _exitRequest;
  bool _exitQuiescing = false, _shutdownFailureReported = false;
  Completer<void>? activeActionDone;
  bool settingsLoaded = false;
  final firstName = TextEditingController();
  final firstNameFocus = FocusNode();
  late final setupValidation = FormValidation(
    validate: () {
      final name = (pendingUserName ?? firstName.text).trim();
      return [
        if (pendingUserName == null &&
            firstName.value.composing.isValid &&
            !firstName.value.composing.isCollapsed)
          const FieldIssue(
            'name',
            'Finish entering your name before continuing.',
          )
        else if (name.length > 100)
          const FieldIssue('name', 'Name must be 100 characters or fewer.'),
      ];
    },
    isComposing: (_) =>
        firstName.value.composing.isValid &&
        !firstName.value.composing.isCollapsed,
  );
  late final captureValidation = FormValidation(
    validate: () {
      if (pendingCapture.isNotEmpty) return [];
      final titles = capture.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty);
      return [
        if (titles.any((title) => title.length > 500))
          const FieldIssue(
            'capture',
            'Keep each task title to 500 characters or fewer.',
          ),
      ];
    },
    isComposing: (_) =>
        capture.value.composing.isValid && !capture.value.composing.isCollapsed,
  );

  String? pendingUserId;
  WorkspaceState? workspaceState;
  void Function()? _unsubscribeWorkspace;
  bool _taskProjectionDirty = true;
  List<Map<String, dynamic>> get rows =>
      workspaceState?.current.tasks.rows ?? const [];

  void _detachWorkspaceState() {
    _unsubscribeWorkspace?.call();
    _unsubscribeWorkspace = null;
    workspaceState?.close();
    workspaceState = null;
  }

  TimeZoneNamePolicy get _timeZonePolicy =>
      workspaceState?.current.timeZonePolicy ??
      TimeZoneNamePolicy.additional2026eV1;

  void _bindWorkspaceState() {
    final tasks = store, food = foodStore;
    final current = workspaceState;
    if (identical(current?.tasks, tasks) && identical(current?.food, food)) {
      return;
    }
    _detachWorkspaceState();
    _taskProjectionDirty = true;
    if (tasks == null) return;
    final session = workspaceState = WorkspaceState(tasks: tasks, food: food);
    var previous = session.current;
    _unsubscribeWorkspace = session.listen((next) {
      if (!mounted ||
          !identical(workspaceState, session) ||
          !identical(store, tasks) ||
          !identical(foodStore, food)) {
        return;
      }
      final tasksChanged = !identical(previous.tasks, next.tasks);
      final usersChanged = !identical(previous.tasks.users, next.tasks.users);
      final foodChanged = !identical(previous.food, next.food);
      final healthChanged = !identical(previous.health, next.health);
      final policyChanged = previous.timeZonePolicy != next.timeZonePolicy;
      previous = next;
      if (next.health.sharedFailure != null) {
        _stopForSharedSafety(next.health.sharedFailure!);
        return;
      }
      if (tasksChanged) _taskProjectionDirty = true;
      if (healthChanged ||
          policyChanged ||
          (foodVisible ? foodChanged || usersChanged : tasksChanged)) {
        setState(() {});
      }
      if (tasksChanged && !foodVisible) _invalidateView();
    });
  }

  final capture = TextEditingController();
  final captureFocus = FocusNode();
  bool captureFailure = false;
  List<({String id, String title})> pendingCapture = [];
  ForegroundImporter? importer;
  TaskStore? watchedStore;
  bool foreground = true, errorFromRefresh = false;
  String? pendingUserName;
  Future<void>? syncing;
  final startup = Stopwatch()..start();
  final viewElapsed = Stopwatch()..start();
  late final ViewTimeSource timeSource;
  late final ViewClock<TaskView> viewClock;
  TaskView? taskView;
  String? taskViewZoneId;
  DateTime? taskViewInstant;
  String? viewError;
  int viewRevision = 0;
  final taskMenuRevision = ValueNotifier<int>(0);
  ({
    String id,
    TaskStore? store,
    int revision,
    String snapshot,
    bool completed,
    bool everyone,
    bool upcoming,
    String? user,
    Set<String> tags,
    Set<String> selected,
    String query,
  })?
  taskDrag;
  bool startupReported = false, startupReportPending = false;

  String? get _startupMarker {
    if (busy || !settingsLoaded || error != null) return null;
    if (store == null || user == null) return 'TANDEMLOG_ONBOARDING_READY_MS';
    if (!timeSource.ready || viewError != null || taskView == null) return null;
    return 'TANDEMLOG_READY_MS';
  }

  void _reportStartupAfterFrame() {
    if (startupReported || startupReportPending || _startupMarker == null) {
      return;
    }
    startupReportPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      startupReportPending = false;
      if (!mounted || startupReported) return;
      final marker = _startupMarker;
      if (marker == null) return;
      startupReported = true;
      debugPrint(
        '$marker=${startup.elapsedMilliseconds} FILES_READ=${store?.readFiles ?? 0}',
      );
    });
  }

  void _invalidateView() {
    if (!mounted || _exitQuiescing || !foreground) return;
    if (foodVisible && taskView != null) {
      _taskProjectionDirty = true;
      viewClock.stop();
      return;
    }
    if (!timeSource.ready) {
      viewClock.stop();
      setState(() => viewError = timeSource.error);
      return;
    }
    try {
      viewError = null;
      viewClock.start();
    } catch (failure) {
      viewClock.stop();
      setState(() => viewError = 'Cannot update the task view: $failure');
    }
  }

  void _formValidationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _lastTextFocus = _textHasFocus;
    setupValidation.addListener(_formValidationChanged);
    captureValidation.addListener(_formValidationChanged);
    firstName.addListener(() {
      if (pendingUserName == null && firstName.text.trim().isEmpty) {
        setupValidation.reset();
      } else {
        setupValidation.changed('name');
      }
    });
    capture.addListener(() {
      if (pendingCapture.isEmpty && capture.text.trim().isEmpty) {
        captureValidation.reset();
      } else {
        captureValidation.changed('capture');
      }
    });
    FocusManager.instance.addListener(_focusChanged);
    WidgetsBinding.instance.addObserver(this);
    sectionNavigation =
        widget.sectionNavigation ??
        (Platform.isAndroid ? AndroidSectionNavigation() : null);
    unawaited(
      sectionNavigation?.start((section) {
        _requestSection(section == AppSection.food);
      }),
    );
    timeSource =
        widget.timeSourceFactory?.call(_invalidateView) ??
        ViewTimeSource(onChanged: _invalidateView);
    viewClock = ViewClock<TaskView>(
      readTime: timeSource.readTime,
      monotonicNow: () => viewElapsed.elapsed,
      project: (time) {
        try {
          viewError = null;
          final projected = projectTaskView(
            rows,
            time,
            assignee: all ? null : user,
            includeUpcoming: showUpcoming,
            tags: Set.of(selectedTags),
            searchQuery: searchQuery,
          );
          _taskProjectionDirty = false;
          taskViewZoneId = time.localZoneId;
          taskViewInstant = time.instant;
          return projected;
        } catch (failure) {
          viewError = 'Cannot update the task view: $failure';
          return TimedView(taskView ?? TaskView([], []));
        }
      },
      onView: (view) {
        if (mounted) {
          setState(() {
            taskView = view.value;
            final visible = visibleEntries
                .map((entry) => entry.task['id'] as String)
                .toSet();
            final selection = retainVisibleListSelection<String>(
              selected: selectedTasks,
              selecting: selecting,
              anchor: selectionAnchor,
              visibleRows: visible,
              visibleIds: visible,
              editorOpen: editingTask != null || editingBulk != null,
            );
            selectedTasks
              ..clear()
              ..addAll(selection.selected);
            selecting = selection.selecting;
            selectionAnchor = selection.anchor;
            viewRevision++;
          });
          if (taskMenuOpen) taskMenuRevision.value++;
          _reportStartupAfterFrame();
        }
      },
    );
    timeSource.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('TANDEMLOG_FIRST_FRAME_MS=${startup.elapsedMilliseconds}');
    });
    _start();
  }

  Future<void> _start() => starting ??= _startLocked();

  Future<void> _startLocked() async {
    try {
      privateRoot =
          widget.profilePath ??
          Platform.environment['TANDEMLOG_PROFILE'] ??
          (await getApplicationSupportDirectory()).path;
      profileDatabase ??= await LocalProfileDatabase.open(privateRoot!);
      privateRoot = profileDatabase!.root;
      await LocalSettings.initialize(profileDatabase!);
      if (!mounted) return;
      settings = LocalSettings(privateRoot!, profileDatabase: profileDatabase);
      await settings!.load();
      settingsLoaded = true;
      if (!mounted) return;
      widget.appearance.value = settings!.appearance;
      user = settings!.user;
      if (sectionRevision == 0) {
        requestedSection = (
          food: settings!.lastSection == AppSection.food,
          revision: ++sectionRevision,
          waitForFolderChoice: true,
        );
      }
      if (settings!.folder != null) await _open(settings!.folder!);
    } catch (e) {
      error = failureMessage(e);
    }
    if (!mounted) return;
    setState(() => busy = false);
    _configureImporter();
    _reportStartupAfterFrame();
    _wakeSectionRequests();
  }

  Future<void> _retryStartup() async {
    if (!mounted || busy || settingsLoaded) return;
    setState(() {
      busy = true;
      error = null;
    });
    starting = null;
    await _start();
  }

  Future<bool> _open(String location, {bool closeEditors = true}) async {
    if (closeEditors && (!await _closeEditor() || !await _closeFoodEditor())) {
      return false;
    }
    final LogFolder folder =
        widget.folderFactory?.call(location) ??
        (Platform.isAndroid
            ? AndroidLogFolder(location)
            : LocalLogFolder(location));
    final engine = textEngine ??=
        widget.textEngineFactory?.call() ?? NativeTextEngine();
    final session = await WorkspaceSession.open(
      folder,
      profile: profileDatabase!,
      writer: settings!.writer,
      textEngine: engine,
      alive: () => mounted,
    );
    if (session == null) return false;
    final opened = session.tasks;
    occurrenceMigrationError = session.occurrenceMigrationError == null
        ? null
        : failureMessage(session.occurrenceMigrationError!);
    Set<String> expanded;
    try {
      expanded = ChecklistExpansionStore(
        opened.db,
        tables: opened.tables,
        profileDatabase: profileDatabase,
      ).load();
    } catch (_) {
      await session.close();
      rethrow;
    }
    store = opened;
    foodStore = session.food;
    foodError = null;
    expandedChecklists = expanded;
    _bindWorkspaceState();
    if (_hasPendingOperation(store!)) {
      error =
          'An earlier saved operation needs confirmation. Retry to finish it.';
      errorFromRefresh = true;
    }
    debugPrint('TANDEMLOG_ROWS ${jsonEncode(store!.lastReadTimings)}');
    debugPrint(
      'TANDEMLOG_STARTUP_CACHE ${jsonEncode({'warmTaskProjectionReuses': store!.warmProjectionReuses, 'decodedCacheReuses': store!.unified?.decodedCacheReuses ?? 0, 'strictDecodedRecords': store!.unified?.decodedRecords ?? 0})}',
    );
    if (!rows.any((r) => r['kind'] == 'user' && r['id'] == user)) {
      user = null;
      if (foodVisible) {
        if (requestedSection == null) _requestSection(true);
        foodVisible = false;
      }
    }
    return true;
  }

  Future<bool> _closeFoodEditor() async {
    final page = foodPageKey.currentState;
    if (page == null) return true;
    if (!await page.requestCloseEditor()) return false;
    await page.editorDone;
    return true;
  }

  Widget _sectionMenu(bool compact) => SectionMenu(
    food: foodVisible,
    compact: compact,
    onSelected: busy ? null : _switchModule,
  );

  Future<void> _switchModule(bool food) async {
    sectionNavigation?.manualNavigation();
    _requestSection(food, waitForFolderChoice: false);
    await sectionWork;
  }

  void _requestSection(bool food, {bool waitForFolderChoice = true}) {
    if (_exitQuiescing) return;
    requestedSection = (
      food: food,
      revision: ++sectionRevision,
      waitForFolderChoice: waitForFolderChoice,
    );
    unawaited(_drainSectionRequests());
  }

  void _wakeSectionRequests() {
    if (!mounted || _exitQuiescing || requestedSection == null) return;
    // Save callbacks return before their child clears its saving/route state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_drainSectionRequests());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool get _sectionReady =>
      mounted &&
      !_exitQuiescing &&
      !busy &&
      !openingChecklistEditor &&
      !closingEditor &&
      !checklistEditorClosing &&
      !(editorKey.currentState?.closeBusy ?? (editingTask != null)) &&
      !(bulkEditorKey.currentState?.closeBusy ?? (editingBulk != null)) &&
      !(checklistEditorKey?.currentState?.closeBusy ?? false) &&
      !(foodPageKey.currentState?.closeBusy ?? false) &&
      (checklistEditorKey == null ||
          checklistEditorKey!.currentState != null) &&
      settingsLoaded &&
      store != null &&
      user != null &&
      sharedSafetyError == null;

  bool get _sectionRequestReady =>
      _sectionReady &&
      requestedSection != null &&
      (!choosingFolder || !requestedSection!.waitForFolderChoice);

  Future<void> _drainSectionRequests() {
    final running = sectionWork;
    if (running != null) return running;
    if (!_sectionRequestReady) return Future<void>.value();
    final completion = Completer<void>();
    sectionWork = completion.future;
    unawaited(_runSectionRequests(completion));
    return completion.future;
  }

  Future<void> _runSectionRequests(Completer<void> completion) async {
    try {
      while (_sectionRequestReady) {
        final origin = store;
        if (requestedSection!.food != foodVisible) {
          if (!await _closeEditor() || !await _closeFoodEditor()) {
            // Cancel also dismisses requests coalesced while this prompt was up.
            requestedSection = null;
            break;
          }
        }
        if (!mounted || !_sectionRequestReady) {
          break;
        }
        if (!identical(store, origin)) {
          continue;
        }
        final latest = requestedSection!;
        if (latest.food != foodVisible) {
          FocusManager.instance.primaryFocus?.unfocus();
          _clearSelection();
          ScaffoldMessenger.of(context).clearSnackBars();
          setState(() => foodVisible = latest.food);
          _invalidateView();
        }
        final section = latest.food ? AppSection.food : AppSection.tasks;
        if (settings!.lastSection != section) {
          await settings!.saveSection(section);
        }
        if (requestedSection?.revision == latest.revision) {
          requestedSection = null;
        }
      }
    } catch (failure) {
      requestedSection = null;
      if (mounted) {
        setState(
          () =>
              error = 'Cannot remember the section: ${failureMessage(failure)}',
        );
      }
    } finally {
      completion.complete();
      if (identical(sectionWork, completion.future)) sectionWork = null;
      _wakeSectionRequests();
    }
  }

  Future<void> _foodAct(
    FoodStore expected,
    Future<void> Function(FoodStore) command,
  ) async {
    final origin = foodStore;
    if (!mounted ||
        _exitQuiescing ||
        busy ||
        sharedSafetyError != null ||
        origin == null ||
        !identical(origin, expected)) {
      throw StateError('Food is busy; try again.');
    }
    final completion = activeActionDone = Completer<void>();
    setState(() => busy = true);
    try {
      await syncing;
      if (!mounted ||
          sharedSafetyError != null ||
          !identical(foodStore, origin)) {
        throw StateError('The food workspace changed.');
      }
      await command(origin);
      if (mounted && identical(foodStore, origin)) {
        setState(() => foodError = null);
      }
    } catch (e) {
      // Read back any successful prefix without losing the initiating error.
      try {
        await origin.refresh();
      } catch (refreshFailure) {
        if (refreshFailure is! FoodHistoryFailure) {
          _stopForSharedSafety(refreshFailure);
        }
        // Retain the last admitted view; no further command is admitted after
        // a shared safety failure.
      }
      if (mounted && identical(foodStore, origin)) {
        setState(() => foodError = failureMessage(e));
      }
      rethrow;
    } finally {
      completion.complete();
      if (identical(activeActionDone, completion)) activeActionDone = null;
      if (mounted) {
        setState(() => busy = false);
        _configureImporter();
        importer?.request();
        _wakeSectionRequests();
      }
    }
  }

  Future<void> _foodCommand(
    FoodStore expected,
    String fingerprint,
    Future<void> Function(FoodStore) action, {
    required String verb,
    FoodUndoEntry? undoEntry,
  }) => _foodAct(expected, (origin) async {
    foodUndoHistory.setWorkspace(
      // Installation identity is stable across the v3 Food-module writer
      // and its validated v4 envelope. Workspace/location remain part of scope.
      jsonEncode([origin.folder.location, origin.space, settings!.writer]),
    );
    final pending = pendingFoodCommand;
    if (pending != null && identical(pending.origin, origin)) {
      if (pending.fingerprint != fingerprint) {
        throw StateError(
          'Retry the earlier food save before making a different change.',
        );
      }
      await origin.recoverPrepared();
      if (!pending.records.every(origin.isAdmitted)) {
        throw StateError('The earlier food save still needs confirmation.');
      }
      _confirmFoodAction(
        origin,
        pending.records,
        verb: pending.verb,
        undoEntry: pending.undoEntry,
      );
      pendingFoodCommand = null;
      return;
    }
    final previous = origin.lastPreparedRecords;
    try {
      await action(origin);
      final records = identical(previous, origin.lastPreparedRecords)
          ? <FoodRecord>[]
          : origin.lastPreparedRecords;
      _confirmFoodAction(origin, records, verb: verb, undoEntry: undoEntry);
      pendingFoodCommand = null;
    } catch (_) {
      if (!identical(previous, origin.lastPreparedRecords) &&
          origin.lastPreparedRecords.isNotEmpty) {
        pendingFoodCommand = (
          origin: origin,
          fingerprint: fingerprint,
          records: origin.lastPreparedRecords,
          verb: verb,
          undoEntry: undoEntry,
        );
      }
      rethrow;
    }
  });

  void _confirmFoodAction(
    FoodStore origin,
    List<FoodRecord> records, {
    required String verb,
    FoodUndoEntry? undoEntry,
  }) {
    if (!records.every(origin.isAdmitted)) {
      throw StateError('The food save still needs confirmation.');
    }
    if (undoEntry != null) {
      // Success also covers idempotent Undo with no newly prepared records.
      // Failed/partial inverses retain this exact entry until full recovery.
      foodUndoHistory.complete(undoEntry);
    } else {
      foodUndoHistory.record(verb, records, confirmed: origin.isAdmitted);
    }
  }

  Future<void> _undoFoodLatest(FoodStore expected) async {
    final entry = foodUndoHistory.latest;
    if (!foodVisible ||
        busy ||
        entry == null ||
        sharedSafetyError != null ||
        pendingFoodCommand != null ||
        expected.hasPreparedAppend ||
        !identical(foodStore, expected) ||
        !await _closeFoodEditor() ||
        !mounted ||
        !foodVisible ||
        busy ||
        !identical(foodStore, expected) ||
        !identical(foodUndoHistory.latest, entry) ||
        pendingFoodCommand != null ||
        expected.hasPreparedAppend) {
      return;
    }
    await _foodCommand(
      expected,
      'undo:${entry.records.map((record) => '${record.id}:${record.hash}').join(',')}',
      (origin) async {
        await origin.undoOperations(entry.records);
      },
      verb: entry.verb,
      undoEntry: entry,
    );
  }

  Future<void> _retryFoodOpen(TaskStore expected) async {
    if (busy || !identical(store, expected) || foodStore != null) return;
    await _act(() async {
      await syncing;
      if (!mounted || !identical(store, expected)) return;
      FoodStore? opened;
      try {
        await expected.refresh();
        if (expected.folder is! BoundedLogFolder) {
          throw const FoodHistoryFailure(
            'This folder cannot enforce safe Food reads. Tasks remain available.',
          );
        }
        opened = await FoodStore.openUnified(expected.unified!);
        if (!mounted || !identical(store, expected)) {
          await opened.close();
          return;
        }
        setState(() {
          foodStore = opened;
          foodError = null;
          _bindWorkspaceState();
        });
      } on FoodHistoryFailure catch (failure) {
        if (mounted && identical(store, expected)) {
          setState(() => foodError = failure.message);
        }
      } catch (failure) {
        _stopForSharedSafety(failure);
        rethrow;
      }
    });
  }

  Widget _foodSurface() {
    final origin = foodStore;
    final users = rows.where((row) => row['kind'] == 'user').toList();
    final name =
        users.where((entry) => entry['id'] == user).firstOrNull?['name']
            as String?;
    if (origin == null) {
      final taskOrigin = store!;
      return Column(
        children: [
          FoodInventoryToolbar(
            sectionMenu: _sectionMenu,
            userName: name,
            identityMenu: (child) => _identityMenu(users, child: child),
            showActions: false,
          ),
          toolbarProgress(busy: busy && !awaitingCompletionConfirmation),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Food is unavailable'),
                    const SizedBox(height: 12),
                    Text(foodError ?? 'Food could not be opened.'),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: busy ? null : () => _retryFoodOpen(taskOrigin),
                      child: const Text('Retry food'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    final pending = pendingFoodCommand;
    final hasPendingCommand =
        pending != null && identical(pending.origin, origin);
    final undo = foodUndoHistory.latest;
    Future<void> restoreItems(List<FoodContainer> items) => _foodCommand(
      origin,
      'restore:${jsonEncode([
        for (final item in items) [item.id, item.deletions.toList()..sort()],
      ])}',
      (store) async {
        await store.restore(items);
      },
      verb: 'restoring',
    );
    return Column(
      children: [
        // Prepared receipts exist briefly during every healthy append. Recovery
        // copy belongs to an unresolved outcome, not the in-flight command.
        if (!busy &&
            (workspaceState!.health.hasPendingFoodSave ||
                hasPendingCommand ||
                workspaceState!.health.foodPendingReferences > 0))
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    workspaceState!.health.hasPendingFoodSave ||
                            hasPendingCommand
                        ? 'An earlier food save needs confirmation. Retry to finish it.'
                        : 'Waiting for related food changes from folder sync.',
                  ),
                ),
                TextButton(
                  key: const ValueKey('retry-food-save'),
                  onPressed: busy ? null : () => _recoverFood(origin),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        Expanded(
          child: FoodInventoryPage(
            key: foodPageKey,
            onCloseReadinessChanged: _wakeSectionRequests,
            state: workspaceState!.current.food!.state,
            workspaceIdentity: origin,
            progress: toolbarProgress(
              busy: busy && !awaitingCompletionConfirmation,
            ),
            sectionMenu: _sectionMenu,
            userName: name,
            identityMenu: (child) => _identityMenu(users, child: child),
            busy: busy,
            error: foodError,
            savePending:
                workspaceState!.health.hasPendingFoodSave ||
                pendingFoodCommand != null,
            hasPendingSave: () =>
                workspaceState!.health.hasPendingFoodSave ||
                pendingFoodCommand != null,
            onAdd: (details, count) => _foodCommand(
              origin,
              'add:$count:${details.groupKey}',
              (store) async {
                await store.add(details, count);
              },
              verb: 'adding',
            ),
            onRemove: (ids) =>
                _foodCommand(origin, 'remove:${ids.join(',')}', (store) async {
                  await store.remove(ids);
                }, verb: 'removing'),
            onRestore: (item) => restoreItems([item]),
            onRestoreBatch: restoreItems,
            onDetails: (items, details, fields, products) => _foodCommand(
              origin,
              'details:${items.map((e) => e.id).join(',')}:${details.groupKey}:${fields.join(',')}:${jsonEncode([products.roots, products.changes])}',
              (store) async {
                await store.changeDetails(
                  items.map((e) => e.id).toList(),
                  details,
                  fields,
                  products: products,
                );
              },
              verb: 'editing',
            ),
            undoLabel: undo == null ? 'Undo' : 'Undo ${undo.label}',
            onUndo:
                undo == null ||
                    workspaceState!.health.hasPendingFoodSave ||
                    hasPendingCommand
                ? null
                : () => _undoFoodLatest(origin),
          ),
        ),
      ],
    );
  }

  Future<void> _recoverFood(FoodStore origin) async {
    try {
      await _foodAct(origin, (store) async {
        await store.recoverPrepared();
        final pending = pendingFoodCommand;
        if (pending != null) {
          if (!identical(pending.origin, store) ||
              !pending.records.every(store.isAdmitted)) {
            throw StateError(
              'The earlier food save is still waiting for admission.',
            );
          }
          _confirmFoodAction(
            store,
            pending.records,
            verb: pending.verb,
            undoEntry: pending.undoEntry,
          );
          pendingFoodCommand = null;
        }
      });
    } catch (_) {
      /* _foodAct exposes the initiating failure */
    }
  }

  Future<void> _saveSettings() async {
    final preferences = settings!;
    preferences.folder = store?.folder.location ?? preferences.folder;
    preferences.user = user;
    await preferences.save();
  }

  Future<void> _selectUser(String? selected, {int? tasksRevision}) async {
    if (!await _closeEditor()) return;
    _clearSelection();
    // Manage users explicitly visits Tasks setup after draft guards succeed.
    // A later shortcut may still wait for the next user selection.
    final destinationRevision = selected == null
        ? tasksRevision ?? ++sectionRevision
        : null;
    if (destinationRevision != null && tasksRevision == null) {
      sectionNavigation?.manualNavigation();
    }
    if (selected == null) {
      // Finish any earlier section preference write before changing its shared
      // settings object. The admitted action is busy, so new requests wait.
      await sectionWork;
      if (!mounted) return;
    }
    final previous = settings!.user;
    settings!.folder = store!.folder.location;
    settings!.user = selected;
    try {
      if (selected == null) {
        await settings!.saveSection(AppSection.tasks);
      } else {
        await settings!.save();
      }
    } catch (_) {
      settings!.user = previous;
      rethrow;
    }
    if (!mounted) return;

    user = selected;
    if (destinationRevision != null) {
      if (requestedSection != null &&
          requestedSection!.revision <= destinationRevision) {
        requestedSection = null;
      }
      foodVisible = false;
    }
  }

  Future<void> _startDefault() => _act(() async {
    if (!settingsLoaded || settings!.folder != null) return;
    final location = await settings!.desktopDefaultFolder();
    await ensureDirectoryDurable(Directory(location));
    if (!await _open(location) || !mounted) return;
    await _saveSettings();
  });

  Future<void> _setAppearance(Appearance value) => _act(() async {
    final previous = settings!.appearance;
    settings!.appearance = value;
    try {
      await _saveSettings();
      if (mounted) widget.appearance.value = value;
    } catch (_) {
      settings!.appearance = previous;
      rethrow;
    }
  });

  Future<void> _showSettings() async {
    if (_exitQuiescing) return;
    final origin = store, owner = profileDatabase, preferences = settings;
    final location = origin?.folder.location ?? preferences?.folder;
    bool current() =>
        mounted &&
        !_exitQuiescing &&
        identical(store, origin) &&
        identical(profileDatabase, owner) &&
        identical(settings, preferences) &&
        location == (store?.folder.location ?? settings?.folder);
    bool canOpen = false;
    if (location != null) {
      try {
        canOpen = await widget.folderActions.canOpen(location);
      } catch (_) {
        /* unavailable */
      }
    }
    if (!mounted || !current()) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settings'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Theme'),
                  subtitle: Text(switch (widget.appearance.value) {
                    Appearance.system => 'System',
                    Appearance.light => 'Light',
                    Appearance.dark => 'Dark',
                  }),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: settingsLoaded && sharedSafetyError == null,
                  onTap: settingsLoaded && sharedSafetyError == null
                      ? () async {
                          final choice = await showDialog<Appearance>(
                            context: ctx,
                            builder: (themeContext) => AlertDialog(
                              title: const Text('Theme'),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              content: SingleChildScrollView(
                                child: RadioGroup<Appearance>(
                                  groupValue: widget.appearance.value,
                                  onChanged: (value) =>
                                      Navigator.pop(themeContext, value),
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      RadioListTile<Appearance>(
                                        value: Appearance.system,
                                        title: Text('System'),
                                      ),
                                      RadioListTile<Appearance>(
                                        value: Appearance.light,
                                        title: Text('Light'),
                                      ),
                                      RadioListTile<Appearance>(
                                        value: Appearance.dark,
                                        title: Text('Dark'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(themeContext),
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          );
                          if (choice != null && ctx.mounted) {
                            Navigator.pop(ctx, choice.name);
                          }
                        }
                      : null,
                ),
                if (store != null) ...[
                  const Divider(height: 32),
                  const Text('This installation'),
                  SelectableText(settings!.writer),
                ],
                if (store?.unified != null) ...[
                  const Divider(height: 32),
                  ListTile(
                    key: const ValueKey('device-name-setting'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Device name'),
                    subtitle: Text(
                      '${store!.unified!.snapshot.deviceName(settings!.writer) ?? 'Unnamed device'} · ${settings!.writer.substring(0, 8)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    enabled:
                        !busy &&
                        sharedSafetyError == null &&
                        !_hasPendingOperation(store!),
                    onTap: () => Navigator.pop(ctx, 'device-name'),
                  ),
                ],
                const Divider(height: 32),
                const Text('Data folder'),
                const SizedBox(height: 8),
                if (location != null && !widget.folderActions.requiresPicker)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SelectableText(location),
                  ),
                Text(
                  location == null
                      ? 'A data folder will be set up when you start.'
                      : widget.folderActions.requiresPicker
                      ? 'Tasks are stored in this folder. Manage it in Android’s Files and use your sync app to share changes between devices. Switching folders does not move or delete tasks.'
                      : 'Tasks are stored in this folder. Use your sync app to share changes between devices, and back up the folder before removing app data. Switching folders does not move or delete tasks.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (location != null &&
                        !widget.folderActions.requiresPicker)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(64, 48),
                          visualDensity: VisualDensity.standard,
                        ),
                        onPressed: canOpen && sharedSafetyError == null
                            ? () => Navigator.pop(ctx, 'open')
                            : null,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Open data folder'),
                      ),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 48),
                        visualDensity: VisualDensity.standard,
                      ),
                      onPressed:
                          settingsLoaded &&
                              !busy &&
                              !choosingFolder &&
                              sharedSafetyError == null
                          ? () => Navigator.pop(ctx, 'choose')
                          : null,
                      child: Text(
                        location == null
                            ? 'Choose an existing folder'
                            : 'Use a different folder',
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('check-data-integrity'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(64, 48),
                        visualDensity: VisualDensity.standard,
                      ),
                      onPressed:
                          store != null && !busy && sharedSafetyError == null
                          ? () => Navigator.pop(ctx, 'verify')
                          : null,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Check data integrity'),
                    ),
                  ],
                ),
                if (location != null &&
                    !widget.folderActions.requiresPicker &&
                    !canOpen)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'No file manager is available to open this folder.',
                    ),
                  ),
                const Divider(height: 32),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Licenses'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(ctx, 'licenses'),
                ),
                const ReleaseVersionTile(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (!current() || action == null) return;
    if (action == 'device-name') {
      await _editDeviceName();
    } else if (action == 'choose') {
      await _chooseFolder();
    } else if (action == 'open') {
      await _act(() => widget.folderActions.open(location!));
    } else if (action == 'verify') {
      await _checkDataIntegrity();
    } else if (action == 'licenses') {
      if (mounted) {
        showLicensePage(context: context, applicationName: 'Tandemlog');
      }
    } else {
      await _setAppearance(Appearance.values.byName(action));
    }
  }

  Future<void> _editDeviceName() async {
    final origin = store, history = store?.unified;
    if (origin == null ||
        history == null ||
        busy ||
        sharedSafetyError != null) {
      return;
    }
    final change = await showDialog<DeviceNameChange>(
      context: context,
      builder: (_) =>
          DeviceNameDialog(name: history.snapshot.deviceName(history.writer)),
    );
    if (change == null || !mounted || !identical(store, origin)) return;
    await _act(() async {
      if (!mounted || !identical(store, origin)) return;
      await history.renameDevice(change.name);
    });
  }

  Future<void> _checkDataIntegrity() async {
    final origin = store;
    if (!mounted || busy || origin == null) return;
    String? report;
    var passed = false;
    await _act(() async {
      if (!mounted || !identical(store, origin)) return;
      try {
        await origin.verifyHistory();
        if (!mounted || !identical(store, origin)) return;
        undoHistory.reconcile(origin.confirmedOperations);
        passed = true;
        final summary = origin.lastHistoryVerification!;
        report =
            'Data integrity check passed.\n\n'
            'Data folder: ${origin.folder.location}\n\n'
            'Checked ${summary.checkedLogCount} '
            '${summary.checkedLogCount == 1 ? 'log' : 'logs'}, '
            '${summary.checkedRecordCount} complete records and '
            '${summary.checkedByteCount} bytes.\n\n'
            'Checked the full current canonical history and compared it with '
            'the previously cached history baseline. '
            '${summary.importedEventCount > 0 ? 'New valid complete events were imported (${summary.importedEventCount}).' : 'No new events were imported.'}\n\n'
            'This checks consistency, not authenticity or remote sync. '
            'Without a previous baseline, a wholly rewritten valid chain or '
            'a deleted final tail may be undetectable. No repair was performed.';
      } catch (failure) {
        report =
            'Data integrity check failed.\n\n'
            'Data folder: ${origin.folder.location}\n\n'
            '${failureMessage(failure)}\n\n'
            'No repair was performed. Keep the data folder intact while '
            'reviewing the affected log and record.';
        rethrow;
      }
    });
    if (!mounted || !identical(store, origin) || report == null) return;
    final result = report!;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          passed ? 'Data integrity checked' : 'Integrity check failed',
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(
              result,
              key: const ValueKey('data-integrity-report'),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('copy-integrity-report'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: result));
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Integrity report copied')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy report'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _requireCommandSafety(TaskStore origin) {
    if (!mounted || sharedSafetyError != null || !identical(store, origin)) {
      throw StateError('The workspace requires recovery. Your draft is kept.');
    }
  }

  void _stopForSharedSafety(Object failure) {
    if (!mounted) return;
    importer?.stop();
    setState(() {
      sharedSafetyError = failureMessage(failure);
      if (user == null && !foodVisible) {
        error = sharedSafetyError;
        errorFromRefresh = true;
      }
    });
  }

  Future<void> _act(Future<void> Function() action) async {
    if (!mounted || _exitQuiescing || busy || sharedSafetyError != null) {
      return;
    }
    final completion = activeActionDone = Completer<void>();
    setState(() => busy = true);
    try {
      await syncing;
      if (!mounted || sharedSafetyError != null) return;
      await action();
      if (mounted) {
        setState(() {
          error = null;
          errorFromRefresh = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final sharedFailure = store?.unified?.safetyFailure;
        if (sharedFailure != null) {
          _stopForSharedSafety(sharedFailure);
        } else {
          setState(() {
            error = failureMessage(e);
            errorFromRefresh = false;
          });
        }
      }
    } finally {
      completion.complete();
      if (identical(activeActionDone, completion)) activeActionDone = null;
      if (mounted) {
        setState(() => busy = false);
        _configureImporter();
        importer?.request();
        _wakeSectionRequests();
      }
    }
  }

  bool get _textHasFocus {
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus is! Element || focus.renderObject?.attached != true) return false;
    return focus.widget is EditableText ||
        focus.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _focusChanged() {
    if (!mounted) return;
    final textHasFocus = _textHasFocus;
    if (textHasFocus == _lastTextFocus) return;
    setState(() => _lastTextFocus = textHasFocus);
  }

  Future<T> _recordAction<T>(
    TaskStore origin,
    String verb,
    Future<T> Function(void Function(OperationReceipt)) action, {
    Object? group,
    bool notice = false,
    String noun = 'task',
  }) async {
    await syncing;
    _requireCommandSafety(origin);
    final prepared = <OperationReceipt>[];
    final moveEditor = bulkEditorKey, moveBaseline = bulkSnapshot;
    var failed = true;
    try {
      final result = await action(prepared.add);
      failed = false;
      return result;
    } finally {
      if (failed &&
          mounted &&
          identical(store, origin) &&
          prepared.isNotEmpty) {
        try {
          await origin.refresh();
        } catch (_) {}
      }
      if (mounted && identical(store, origin) && prepared.isNotEmpty) {
        if (verb == 'moving' && moveBaseline != null) {
          _advanceBulkForOwnMoves(origin, moveEditor, moveBaseline, prepared);
        }
        final previous = undoHistory.latest;
        final retainedBefore = undoHistory.retainedOperationIds;
        undoHistory.record(verb, prepared, group: group, noun: noun);
        undoHistory.reconcile(origin.confirmedOperations);
        origin.releaseTextOperations(
          retainedBefore.difference(undoHistory.retainedOperationIds),
        );
        final latest = undoHistory.latest;
        final confirmed = origin.confirmedOperations(prepared);
        final confirmedLatest =
            latest != null && latest.operations.any(confirmed.contains);
        _invalidateView();
        if (latest != null &&
            confirmedLatest &&
            (notice || !identical(previous, latest))) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();
          if (notice) {
            const past = {'completing': 'Completed', 'deleting': 'Deleted'};
            final n = latest.operations
                .map((id) => latest.entities[id])
                .toSet()
                .length;
            final successor = prepared.any(
              (r) => origin.hasEntity(const Uuid().v5(r.entity, 'successor')),
            );
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  '${failed ? 'Confirmed ' : ''}${past[verb] ?? verb} $n $noun${n == 1 ? '' : 's'}.${successor ? ' Next occurrence kept.' : ''}',
                ),
                duration: const Duration(seconds: 10),
                persist: false,
                action: SnackBarAction(label: 'Undo', onPressed: _undoLatest),
              ),
            );
          }
        }
      }
    }
  }

  // Rebase only this editor's order token across exact confirmed local moves.
  // Content changes or an unexpected external order remain conflicts. Keeping
  // its key/baseline content retains draft controllers, focus and scroll.
  void _advanceBulkForOwnMoves(
    TaskStore origin,
    GlobalKey<BulkTaskEditorState> session,
    String baseline,
    List<OperationReceipt> receipts,
  ) {
    if (!identical(store, origin) ||
        !identical(bulkEditorKey, session) ||
        editingBulk == null ||
        bulkConflict ||
        bulkSnapshot != baseline) {
      return;
    }
    final expected = List<Map<String, dynamic>>.from(
      (jsonDecode(baseline) as List).map(
        (row) => Map<String, dynamic>.from(row),
      ),
    );
    final confirmed = origin.confirmedOperations(receipts);
    for (final receipt in receipts.where((r) => confirmed.contains(r.id))) {
      final event = LogEvent.decode(receipt.raw);
      if (event.type != 'task.moved') return;
      final index = expected.indexWhere((row) => row['id'] == event.entity);
      if (index < 0) return;
      final task = expected.removeAt(index);
      final before = event.data['before'];
      final target = before == null
          ? expected.length
          : expected.indexWhere((row) => row['id'] == before);
      if (target < 0) return;
      expected.insert(target, task);
    }
    if (jsonEncode(expected) == origin.taskSnapshot) {
      bulkSnapshot = origin.taskSnapshot;
    }
  }

  bool _sameTaskContent(String before, String after) {
    Map<String, String> content(String snapshot) => {
      for (final row in jsonDecode(snapshot) as List)
        row['id'] as String: jsonEncode(row),
    };
    return mapEquals(content(before), content(after));
  }

  Future<void> _undoLatest() async {
    if (foodVisible || busy || closingEditor || undoHistory.latest == null) {
      return;
    }
    if (!await _closeChecklistEditor() || foodVisible || busy) return;
    final origin = store!, requested = undoHistory.latest;
    final preserveEditor = requested?.verb == 'moving';
    if (!preserveEditor && !await _closeEditor()) return;
    if (!mounted || foodVisible || busy || !identical(store, origin)) return;
    await _act(() async {
      await origin.refresh();
      if (!mounted || foodVisible || !identical(store, origin)) return;
      undoHistory.reconcile(origin.confirmedOperations);
      if (!identical(requested, undoHistory.latest)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The latest change updated. Use Undo again.'),
          ),
        );
        return;
      }
      final entry = requested!, label = entry.label;
      final beforeUndo = preserveEditor && !bulkConflict && editingBulk != null
          ? origin.taskSnapshot
          : null;
      final rebaseBulk = beforeUndo != null && bulkSnapshot == beforeUndo;
      final result = await origin.undoOperations(entry.operations.toList());
      final retainedBefore = undoHistory.retainedOperationIds;
      undoHistory.acknowledge(entry, result.undone);
      // Undone operations leave session history; release their native Undo
      // owners now rather than at store close.
      origin.releaseTextOperations(
        retainedBefore.difference(undoHistory.retainedOperationIds),
      );
      if (!mounted || !identical(store, origin)) return;
      setState(() {
        if (!preserveEditor) _clearSelection();
        if (rebaseBulk && _sameTaskContent(beforeUndo, origin.taskSnapshot)) {
          bulkSnapshot = origin.taskSnapshot;
        }
      });
      _invalidateView();
      final newer = result.keptNewerChanges ? ' Newer changes were kept.' : '';
      final retained = result.retainedSuccessorCount == 0
          ? ''
          : result.retainedSuccessorCount == 1
          ? ' Next occurrence kept to preserve other changes.'
          : ' Next occurrences kept to preserve other changes.';
      final removed = result.removedSuccessorCount == 0
          ? ''
          : result.removedSuccessorCount == 1
          ? ' Untouched next occurrence retracted.'
          : ' Untouched next occurrences retracted.';
      final text = result.error == null
          ? 'Undid $label.$removed$retained$newer'
          : '${result.undone.length} confirmed undone; ${result.remaining.length} remain. ${failureMessage(result.error!)}$removed$retained$newer';
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 10),
          persist: false,
          action: result.remaining.isEmpty
              ? null
              : SnackBarAction(label: 'Retry', onPressed: _undoLatest),
        ),
      );
    });
  }

  void _undoShortcut() {
    if (!_textHasFocus) unawaited(_undoLatest());
  }

  void _configureImporter() {
    if (_exitQuiescing) {
      importer?.stop();
      return;
    }
    _bindWorkspaceState();
    if (_taskProjectionDirty) _invalidateView();
    if (!identical(watchedStore, store)) {
      importer?.dispose();
      watchedStore = store;
      final origin = store;
      importer = origin == null
          ? null
          : ForegroundImporter(
              events: switch (origin.folder) {
                LocalLogFolder folder => () => Directory(
                  folder.location,
                ).watch(),
                AndroidLogFolder folder => folder.watch,
                _ => null,
              },
              reconcile: _refresh,
            );
    }
    if (foreground && sharedSafetyError == null) {
      importer?.start();
    } else {
      importer?.stop();
    }
  }

  Future<void> _refresh() async {
    if (!mounted ||
        _exitQuiescing ||
        !foreground ||
        store == null ||
        busy ||
        syncing != null ||
        sharedSafetyError != null) {
      return;
    }
    final origin = store!;
    syncing = () async {
      try {
        final previousClockWarning = origin.clockWarning;
        final previousMigrationError = occurrenceMigrationError;
        final session = workspaceState!;
        final previousTasks = session.current.tasks;
        final result = await session.refresh(
          migrateOccurrenceDates:
              editingTask == null &&
              editingBulk == null &&
              !openingChecklistEditor &&
              checklistEditorDone == null &&
              pendingCapture.isEmpty,
          canMigrate: () =>
              mounted &&
              identical(workspaceState, session) &&
              identical(store, origin) &&
              !busy &&
              editingTask == null &&
              editingBulk == null &&
              !openingChecklistEditor &&
              checklistEditorDone == null &&
              pendingCapture.isEmpty &&
              foreground &&
              sharedSafetyError == null,
        );
        final changed = !identical(previousTasks, result.snapshot.tasks);
        final nextFoodError = result.snapshot.health.foodFailure;
        final message = nextFoodError == null
            ? null
            : failureMessage(nextFoodError);
        if (mounted &&
            identical(workspaceState, session) &&
            foodError != message) {
          setState(() => foodError = message);
        }
        if (result.migration != null) {
          occurrenceMigrationError = result.migrationError == null
              ? null
              : failureMessage(result.migrationError!);
        }
        undoHistory.reconcile(origin.confirmedOperations);
        final clockWarningChanged = previousClockWarning != origin.clockWarning;
        final reconcileCapture = captureFailure && pendingCapture.isNotEmpty;
        if (mounted && identical(store, origin) && reconcileCapture) {
          final unsaved = pendingCapture
              .where((entry) => !origin.isCaptureConfirmed(entry.id))
              .toList();
          capture.text = unsaved.map((entry) => entry.title).join('\n');
          pendingCapture
            ..clear()
            ..addAll(unsaved);
          captureFailure = unsaved.isNotEmpty;
          if (unsaved.isEmpty) error = null;
        }
        if (mounted &&
            identical(store, origin) &&
            (changed ||
                previousMigrationError != occurrenceMigrationError ||
                clockWarningChanged ||
                errorFromRefresh ||
                reconcileCapture)) {
          setState(() {
            if (captureFailure && pendingCapture.isNotEmpty) {
              // Capture owns the detailed created/remaining progress and Retry.
              // Its reserved placement is also a pending workspace operation.
              errorFromRefresh = false;
            } else if (_hasPendingOperation(origin)) {
              error =
                  'An earlier saved operation needs confirmation. Retry to finish it.';
              errorFromRefresh = true;
            } else {
              if (errorFromRefresh) error = null;
              errorFromRefresh = false;
            }
          });
          _invalidateView();
        }
      } catch (e) {
        if (mounted && identical(store, origin)) {
          if (origin.unified != null) {
            _stopForSharedSafety(e);
            return;
          }
          // Shared health already shows this failure in the recovery panel.
          // Keep the action-owned diagnostic for admission-only recovery.
          if (sharedSafetyError != null) return;
          setState(() {
            error = failureMessage(e);
            errorFromRefresh = true;
          });
        }
      }
    }();
    await syncing;
    syncing = null;
  }

  bool _hasPendingOperation(TaskStore origin) =>
      identical(workspaceState?.tasks, origin)
      ? workspaceState!.health.hasPendingTaskSave
      : origin.unified?.hasPending ?? origin.pendingTextOperations.isNotEmpty;

  Future<void> _retryFolderRead() async {
    final origin = store;
    if (origin == null || busy) return;
    if (sharedSafetyError != null) {
      await _retrySharedRead();
      return;
    }
    if (!_hasPendingOperation(origin)) {
      await _refresh();
      return;
    }
    await _act(() async {
      if (origin.unified != null) {
        await origin.unified!.recoverPrepared();
        return;
      }
      for (final receipt in origin.pendingTextOperations) {
        await origin.retryTextOperation(receipt);
      }
    });
  }

  Future<void> _retrySharedRead() async {
    final origin = store, foodOrigin = foodStore, owner = profileDatabase;
    if (!mounted ||
        busy ||
        sharedSafetyError == null ||
        origin == null ||
        owner == null) {
      return;
    }
    final space = origin.space, writer = settings!.writer;
    final completion = activeActionDone = Completer<void>();
    importer?.stop();
    setState(() => busy = true);
    FoodStore? openedFood;
    String? isolatedFoodError;
    void checkOrigin() {
      if (!mounted ||
          !identical(store, origin) ||
          !identical(foodStore, foodOrigin) ||
          !identical(profileDatabase, owner) ||
          origin.space != space ||
          origin.writer != writer ||
          settings?.writer != writer ||
          LocalSettings.protectedValues(owner)['writer'] != writer ||
          (foodOrigin != null &&
              (foodOrigin.space != space || foodOrigin.writer != writer))) {
        throw StateError(
          'The workspace identity changed. Preserve the profile before recovery.',
        );
      }
    }

    try {
      await syncing;
      checkOrigin();
      // This is admission only: no canonical append, pending-operation retry,
      // settings reload, owner reset, or editor close occurs during recovery.
      checkOrigin();
      await origin.refresh();
      checkOrigin();
      try {
        if (foodOrigin != null) {
          await foodOrigin.refresh();
        } else {
          if (origin.folder is! BoundedLogFolder) {
            throw const FoodHistoryFailure(
              'This folder cannot enforce safe Food reads. Tasks remain available.',
            );
          }
          openedFood = await FoodStore.openUnified(origin.unified!);
        }
      } on FoodHistoryFailure catch (failure) {
        isolatedFoodError = failure.message;
      }
      checkOrigin();
      // Food's typed failure has checked shared authority. Recheck Tasks and
      // the installation identity before publishing either admitted projection.
      await origin.refresh();
      checkOrigin();
      undoHistory.reconcile(origin.confirmedOperations);
      setState(() {
        foodStore = foodOrigin ?? openedFood;
        foodError = isolatedFoodError;
        sharedSafetyError = null;
        _bindWorkspaceState();
        if (!captureFailure) error = null;
        errorFromRefresh = false;
        // Admission-only recovery keeps capture-owned progress and Retry.
        if (!(captureFailure && pendingCapture.isNotEmpty) &&
            _hasPendingOperation(origin)) {
          error =
              'An earlier saved operation needs confirmation. Retry to finish it.';
          errorFromRefresh = true;
        }
      });
      openedFood = null;
      _invalidateView();
    } catch (failure) {
      if (mounted && identical(store, origin)) _stopForSharedSafety(failure);
    } finally {
      await openedFood?.close();
      completion.complete();
      if (identical(activeActionDone, completion)) activeActionDone = null;
      if (mounted) {
        setState(() => busy = false);
        _configureImporter();
        if (sharedSafetyError == null) importer?.request();
        _wakeSectionRequests();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_exitQuiescing) return;
    foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (foreground) {
      timeSource.start();
    } else {
      _stopDragScroll();
      taskDrag = null;
      timeSource.stop();
      viewClock.stop();
    }
    _configureImporter();
    if (state == AppLifecycleState.resumed) {
      importer?.request();
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() => _exitRequest ??=
      _requestAppExit().whenComplete(() => _exitRequest = null);

  Future<AppExitResponse> _requestAppExit() async {
    if (_shutdownFuture == null) {
      if (!mounted || busy) return AppExitResponse.cancel;
      try {
        if (!await _closeEditor() ||
            busy ||
            !await _closeFoodEditor() ||
            busy) {
          return AppExitResponse.cancel;
        }
      } catch (failure, stack) {
        // The framework catches observer exceptions and may still exit. A
        // failed/canceled draft decision must instead explicitly keep the app.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: failure,
            stack: stack,
            context: ErrorDescription(
              'while deciding whether to close Tandemlog',
            ),
          ),
        );
        return AppExitResponse.cancel;
      }
      final shutdown = _shutdownOnce(foodPageKey.currentState?.editorDone);
      Object? barrierFailure;
      StackTrace? barrierStack;
      try {
        if (mounted) {
          // Cover existing Settings/dialog routes too. No new input may start
          // after accepted closure while private queues and native owners drain.
          unawaited(
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => const PopScope(
                canPop: false,
                child: Dialog(
                  key: ValueKey('app-closing'),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 20),
                        Text('Closing…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      } catch (failure, stack) {
        barrierFailure = failure;
        barrierStack = stack;
      }
      await _observeShutdown(shutdown);
      if (barrierFailure != null) {
        _reportShutdownFailure(barrierFailure, barrierStack!);
      }
    } else {
      await _observeShutdown(_shutdownFuture!);
    }
    // Cleanup errors have already been reported and every close attempted.
    // Keep the app quiescent and explicitly exit; never expose half-closed
    // resources behind an interactive canceled window or rely on a thrown
    // observer exception to choose the native response.
    return AppExitResponse.exit;
  }

  Future<void> _observeShutdown(Future<void> shutdown) async {
    try {
      await shutdown;
    } catch (failure, stack) {
      _reportShutdownFailure(failure, stack);
    }
  }

  void _reportShutdownFailure(Object failure, StackTrace stack) {
    if (_shutdownFailureReported) return;
    _shutdownFailureReported = true;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: failure,
        stack: stack,
        context: ErrorDescription('while closing Tandemlog'),
      ),
    );
  }

  Future<void> _shutdownOnce(
    Future<void>? foodEditorDone, {
    bool repaint = true,
  }) {
    final running = _shutdownFuture;
    if (running != null) return running;
    final completion = Completer<void>();
    _shutdownFuture = completion.future;
    _exitQuiescing = true;
    busy = true;
    foreground = false;
    requestedSection = null;
    if (repaint && mounted) setState(() {});
    unawaited(
      _shutdown(
        foodEditorDone,
      ).then(completion.complete, onError: completion.completeError),
    );
    return completion.future;
  }

  Future<void> _chooseFolder() async {
    if (!mounted ||
        busy ||
        choosingFolder ||
        !settingsLoaded ||
        sharedSafetyError != null) {
      return;
    }
    final origin = store, owner = profileDatabase, preferences = settings;
    final originalFood = foodStore;
    final writer = preferences!.writer;
    bool current() =>
        mounted &&
        !_exitQuiescing &&
        identical(store, origin) &&
        identical(foodStore, originalFood) &&
        identical(profileDatabase, owner) &&
        identical(settings, preferences) &&
        preferences.writer == writer &&
        sharedSafetyError == null;
    setState(() => choosingFolder = true);
    try {
      if (!await _closeEditor() ||
          !await _closeFoodEditor() ||
          !current() ||
          busy) {
        return;
      }
      final selected = await widget.folderActions.pick();
      if (selected == null || !current() || busy) return;
      if (selected == store?.folder.location) return;
      // Editors can be opened while the user is choosing. Ask about those
      // drafts before starting work or changing the active workspace.
      if (!await _closeEditor() ||
          !await _closeFoodEditor() ||
          !current() ||
          busy) {
        return;
      }
      await _act(() async {
        if (!current()) return;
        final previousStore = store;
        final previousFood = foodStore, previousFoodError = foodError;
        final previousUser = user;
        final previousFolder = settings!.folder;
        final previousExpanded = expandedChecklists;
        final previousError = error;
        final previousErrorFromRefresh = errorFromRefresh;
        try {
          if (!await _open(selected, closeEditors: false) || !mounted) return;
          await _saveSettings();
        } catch (_) {
          _detachWorkspaceState();
          if (!identical(foodStore, previousFood)) await foodStore?.close();
          if (!identical(store, previousStore)) {
            final failed = store;
            await failed?.close();
            await failed?.unified?.close();
          }
          store = previousStore;
          foodStore = previousFood;
          _bindWorkspaceState();
          foodError = previousFoodError;
          user = previousUser;
          expandedChecklists = previousExpanded;
          error = previousError;
          errorFromRefresh = previousErrorFromRefresh;
          settings!.folder = previousFolder;
          settings!.user = previousUser;
          rethrow;
        }
        await previousFood?.close();
        await previousStore?.close();
        await previousStore?.unified?.close();
        if (!mounted) return;
        foodUndoHistory.clear();
        pendingFoodCommand = null;
        undoHistory.clear();
        _clearSelection();
        ScaffoldMessenger.of(context).clearSnackBars();
        pendingCapture.clear();
        showCompleted = false;
        capture.clear();
        captureValidation.reset();
        firstName.clear();
        setupValidation.reset();
        pendingUserId = null;
        pendingUserName = null;
      });
    } catch (e) {
      if (current()) {
        setState(() {
          error = failureMessage(e);
          errorFromRefresh = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => choosingFolder = false);
        _wakeSectionRequests();
      }
    }
  }

  Future<void> _createFirstUser() async {
    final name = firstName.text.trim();
    final origin = store, owner = profileDatabase;
    final capturedPendingId = pendingUserId,
        capturedPendingName = pendingUserName;
    if (busy ||
        user != null ||
        origin == null ||
        (pendingUserName == null && name.isEmpty)) {
      return;
    }
    if (pendingUserName == null && !await setupValidation.reviewAndReveal()) {
      return;
    }
    if (!mounted || busy || user != null || !identical(store, origin)) return;
    // Continue is the existing setup retry for the retained name. Revalidate
    // both modules before admitting that explicit intent after a shared stop.
    if (sharedSafetyError != null) {
      await _retrySharedRead();
      if (!mounted || busy || sharedSafetyError != null) return;
    }
    if (user != null ||
        !identical(store, origin) ||
        !identical(profileDatabase, owner) ||
        firstName.text.trim() != name ||
        pendingUserId != capturedPendingId ||
        pendingUserName != capturedPendingName) {
      return;
    }
    await _act(() async {
      _requireCommandSafety(origin);
      pendingUserId ??= const Uuid().v4();
      pendingUserName ??= name;
      await origin.refresh();
      _requireCommandSafety(origin);
      if (!origin.hasEntity(pendingUserId!)) {
        await origin.command(pendingUserId!, 'user.created', {
          'name': pendingUserName,
        });
      }
      await _selectUser(pendingUserId);
      pendingUserId = null;
      pendingUserName = null;
      firstName.clear();
      setupValidation.reset();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && user == null) firstNameFocus.requestFocus();
    });
  }

  Future<void> _addUser() async {
    final name = await _textDialog('Who is using Tandemlog?', label: 'Name');
    if (name == null) return;
    await _act(() async {
      final id = const Uuid().v4();
      await store!.command(id, 'user.created', {'name': name});
      await _selectUser(id);
    });
  }

  Future<String?> _textDialog(String title, {required String label}) =>
      showDialog<String>(
        context: context,
        builder: (_) => NameEntryDialog(title: title, label: label),
      );

  void _submitCaptureButton() {
    if (busy) return;
    if (capture.value.composing.isValid &&
        !capture.value.composing.isCollapsed) {
      // Deliberate Add accepts the visible draft. Use Flutter's normal editor
      // finalization to clear composition and finish the IME connection before
      // onSubmitted invokes the one capture path. Hardware Enter still leaves
      // active composition to the IME, including candidate selection.
      captureFocus.context!
          .findAncestorStateOfType<EditableTextState>()!
          .performAction(TextInputAction.done);
      return;
    }
    unawaited(_capture());
  }

  Future<void> _capture() async {
    if (busy ||
        (capture.value.composing.isValid &&
            !capture.value.composing.isCollapsed)) {
      return;
    }
    final capturedText = capture.text;
    // An empty quick-capture draft is an ordinary ready state. This guard also
    // covers keyboard/IME submission without reserving IDs or losing focus.
    if (pendingCapture.isEmpty && capturedText.trim().isEmpty) return;
    if (pendingCapture.isEmpty && !await captureValidation.reviewAndReveal()) {
      return;
    }
    if (!mounted ||
        busy ||
        (pendingCapture.isEmpty && capture.text != capturedText)) {
      return;
    }
    final titles = capturedText
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (pendingCapture.isEmpty) {
      pendingCapture = titles
          .map((title) => (id: const Uuid().v4(), title: title))
          .toList();
    }
    await _act(() async {
      final result = await store!.createTasks({
        for (final entry in pendingCapture) entry.id: entry.title,
      }, user!);
      pendingCapture.removeWhere(
        (entry) => result.committedIds.contains(entry.id),
      );
      if (result.committedIds.isNotEmpty || result.error == null) {
        capture.text = pendingCapture.map((entry) => entry.title).join('\n');
      }
      if (result.error != null) {
        throw StateError(
          '${result.createdIds.length} tasks confirmed created; '
          '${pendingCapture.length} remain to finish capture. ${failureMessage(result.error!)}',
        );
      }
    });
    captureFailure = pendingCapture.isNotEmpty;
    if (pendingCapture.isEmpty) captureValidation.reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && captureMode && !foodVisible && user != null && !busy) {
        captureFocus.requestFocus();
      }
    });
  }

  Future<bool> _closeEditor({bool retainSurface = false}) async {
    if (!await _closeChecklistEditor()) return false;
    if (editingTask == null && editingBulk == null) return true;
    if (!mounted || closingEditor) return false;
    setState(() => closingEditor = true);
    try {
      final okay =
          await ((editingTask != null
                  ? editorKey.currentState?.canClose()
                  : bulkEditorKey.currentState?.canClose()) ??
              Future.value(true));
      if (okay && mounted && !retainSurface) {
        editingText?.cancel();
        if (editingText != null) {
          editorStore?.releaseTextCapture(editingText!.capture);
        }
        setState(() {
          editingTask = null;
          editingBulk = null;
          editorStore = null;
          editingText = null;
          textSaveCommand = null;
          editingTextStatus = null;
        });
      }
      return okay;
    } finally {
      // Focus/viewport changes can rebuild Undo as disabled while the guard
      // is open. Cancel must invalidate that view as well as release the flag.
      if (mounted) {
        setState(() => closingEditor = false);
      } else {
        closingEditor = false;
      }
      _wakeSectionRequests();
    }
  }

  Future<void> _changeSearch(String value) async {
    if (!await _closeEditor()) {
      search.text = lastSearchText;
      return;
    }
    lastSearchText = value;
    _clearSelection();
    _invalidateView();
  }

  Future<void> _clearTaskSelection() async {
    if (!await _closeEditor() || !mounted) return;
    setState(_clearSelection);
  }

  Future<void> _openSelectionSession() async {
    if (_exitQuiescing) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final origin = store;
    if (origin == null || busy || sharedSafetyError != null) return;
    final tasks = rows
        .where(
          (row) => row['kind'] == 'task' && selectedTasks.contains(row['id']),
        )
        .toList();
    if (tasks.length != selectedTasks.length) return;
    if (tasks.length == 1) {
      final id = tasks.single['id'] as String;
      TaskTextSession? session;
      TaskTextCapture? openedCapture;
      String? status;
      try {
        final captured = await origin.captureTaskText(id);
        openedCapture = captured;
        session = TaskTextSession(
          captured,
          registerDraftActor: (field, allocation, actor) =>
              origin.registerTextDraftActor(captured, field, allocation, actor),
        );
      } catch (e) {
        if (openedCapture != null) origin.releaseTextCapture(openedCapture);
        status = origin.sharedTextInitialized
            ? failureMessage(e)
            : 'This workspace has no verified shared text setup. Restore its initialized history before editing.';
      }
      if (!mounted ||
          _exitQuiescing ||
          busy ||
          sharedSafetyError != null ||
          !identical(store, origin) ||
          selectedTasks.length != 1 ||
          !selectedTasks.contains(id)) {
        session?.cancel();
        if (session != null) origin.releaseTextCapture(session.capture);
        return;
      }
      final current = origin.visibleTaskRow(id);
      if (current == null) {
        session?.cancel();
        if (session != null) origin.releaseTextCapture(session.capture);
        return;
      }
      editingText?.cancel();
      if (editingText != null) {
        editorStore?.releaseTextCapture(editingText!.capture);
      }
      setState(() {
        editorStore = origin;
        editorKey = GlobalKey<TaskEditorState>();
        editingTask = _displayTask(current);
        editingText = session;
        textSaveCommand = session == null
            ? null
            : TextSaveCommand(origin, session);
        editingTextStatus = status;
        editingBulk = null;
      });
    } else if (tasks.isNotEmpty) {
      editingText?.cancel();
      if (editingText != null) {
        editorStore?.releaseTextCapture(editingText!.capture);
      }
      setState(() {
        editorStore = origin;
        editingText = null;
        textSaveCommand = null;
        editingTextStatus = null;
        bulkSnapshot = origin.taskSnapshot;
        bulkConflict = false;
        bulkEditorKey = GlobalKey<BulkTaskEditorState>();
        editingBulk = tasks
            .map((task) => Map<String, dynamic>.from(task))
            .toList();
        editingTask = null;
        bulkPending = tasks.map((task) => task['id'] as String).toList();
      });
    }
  }

  Future<bool> _selectTask(
    Map<String, dynamic> task, {
    SelectionGesture gesture = SelectionGesture.plain,
  }) async {
    final id = task['id'] as String;
    final before = Set<String>.of(selectedTasks);
    final visible = visibleEntries.map((entry) => entry.task['id']).toSet();
    // A retained editor snapshot may outlive a row. New gestures operate only
    // on the current visible list, never on that captured hidden selection.
    final visibleSelection = before.intersection(visible);
    final range = gesture == SelectionGesture.range;
    final result = nextListSelection<String>(
      selected: visibleSelection,
      selecting: selecting,
      anchor: selectionAnchor,
      target: id,
      order: [for (final entry in visibleEntries) entry.task['id'] as String],
      members: (row) => [row],
      gesture: gesture,
    );
    final next = result.selected;
    if (setEquals(before, next) && result.selecting == selecting) return true;
    var nextIntent = result.selecting;
    var anchor = result.anchor;
    if (wideLayout && visibleSelection.length >= 2 && next.length == 1) {
      nextIntent = false;
    }
    if (next.isEmpty) nextIntent = false;
    final origin = store;
    final plannedOrder = visibleEntries
        .map((entry) => entry.task['id'])
        .toList();
    if (!await _closeEditor(retainSurface: next.isNotEmpty && wideLayout) ||
        !mounted) {
      return false;
    }
    if (busy || !identical(origin, store) || !timeSource.ready) return false;
    final current = projectTaskView(
      store!.rows,
      timeSource.readTime(),
      assignee: all ? null : user,
      includeUpcoming: showUpcoming,
      tags: Set.of(selectedTags),
      searchQuery: searchQuery,
    ).value;
    final currentEntries = searching
        ? [...current.open, ...current.completed]
        : (showCompleted ? current.completed : current.open);
    final currentOrder = currentEntries
        .map((entry) => entry.task['id'])
        .toList();
    if (!next.every(currentOrder.contains) ||
        (range && !listEquals(plannedOrder, currentOrder))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The task list changed. Select the tasks again.'),
        ),
      );
      return false;
    }
    if (!listEquals(plannedOrder, currentOrder) ||
        !currentOrder.contains(anchor)) {
      anchor = null;
    }
    setState(() {
      selectedTasks
        ..clear()
        ..addAll(next);
      selecting = nextIntent;
      selectionAnchor = next.isEmpty ? null : anchor;
      mobileEditorOpen = !nextIntent;
    });
    if (next.isNotEmpty) await _openSelectionSession();
    return true;
  }

  Future<void> _editSelected() async {
    if (selectedTasks.isEmpty || !await _closeEditor() || !mounted) return;
    final visible = visibleEntries.map((entry) => entry.task['id']).toSet();
    if (!selectedTasks.every(visible.contains)) return;
    setState(() {
      mobileEditorOpen = true;
    });
    await _openSelectionSession();
  }

  Future<void> _focusRelativeTask(
    Map<String, dynamic> task,
    int direction,
    bool range,
  ) async {
    final entries = visibleEntries.toList();
    final index = entries.indexWhere((entry) => entry.task['id'] == task['id']);
    final nextIndex = index + direction;
    if (index < 0 || nextIndex < 0 || nextIndex >= entries.length) return;
    final target = entries[nextIndex].task;
    if (range && !await _selectTask(target, gesture: SelectionGesture.range)) {
      return;
    }
    final id = target['id'] as String;
    var targetContext = dropKeys[id]?.currentContext;
    if (targetContext == null && taskScroll.hasClients) {
      final box = dropKeys[task['id']]?.currentContext?.findRenderObject();
      final step = box is RenderBox && box.hasSize ? box.size.height : 72.0;
      await taskScroll.animateTo(
        (taskScroll.offset + direction * step).clamp(
          0.0,
          taskScroll.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
      await WidgetsBinding.instance.endOfFrame;
      targetContext = dropKeys[id]?.currentContext;
    }
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 120),
        alignmentPolicy: direction > 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      if (!targetContext.mounted) return;
      final box = targetContext.findRenderObject() as RenderBox?;
      if (box != null &&
          box.hasSize &&
          _pointerOverGroupHeading(
            box.localToGlobal(box.size.center(Offset.zero)),
          )) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: .5,
          duration: const Duration(milliseconds: 120),
        );
      }
    }
    rowFocus[id]?.requestFocus();
  }

  bool Function() _bulkGuard(List<String> ids) {
    final origin = store,
        query = searchQuery,
        assignee = user,
        everyone = all,
        upcoming = showUpcoming,
        completed = showCompleted;
    final tags = Set<String>.of(selectedTags);
    final original = {
      for (final row in origin!.rows.where((row) => ids.contains(row['id'])))
        row['id']: jsonEncode(row),
    };
    return () {
      if (!mounted ||
          !foreground ||
          sharedSafetyError != null ||
          !identical(store, origin) ||
          !timeSource.ready ||
          query != searchQuery ||
          assignee != user ||
          everyone != all ||
          upcoming != showUpcoming ||
          completed != showCompleted ||
          !setEquals(tags, selectedTags)) {
        return false;
      }
      final view = projectTaskView(
        origin.rows,
        timeSource.readTime(),
        assignee: everyone ? null : assignee,
        includeUpcoming: upcoming,
        tags: tags,
        searchQuery: query,
      ).value;
      final entries = query.isNotEmpty
          ? [...view.open, ...view.completed]
          : (completed ? view.completed : view.open);
      return ids
          .where((id) {
            final row = origin.rows.where((row) => row['id'] == id).firstOrNull;
            return row != null && jsonEncode(row) == original[id];
          })
          .every((id) => entries.any((entry) => entry.task['id'] == id));
    };
  }

  Future<void> _saveBulk(BulkTaskEdit edit) => _recordAction(
    editorStore!,
    'editing',
    (prepared) => _saveBulkRecorded(edit, prepared),
    group: (bulkEditorKey, 'edit'),
  );

  Future<void> _saveBulkRecorded(
    BulkTaskEdit edit,
    void Function(OperationReceipt) prepared,
  ) async {
    final origin = editorStore!;
    final ids = List<String>.of(bulkPending);
    if (ids.isEmpty) return;
    if (bulkConflict) {
      throw StateError(
        'Selected tasks changed. Close this editor and review them before retrying.',
      );
    }
    await syncing;
    _requireCommandSafety(origin);
    try {
      final result = await origin.bulkEdit(
        ids,
        edit,
        expectedTaskSnapshot: bulkSnapshot!,
        canCommit: _bulkGuard(ids),
        onPrepared: prepared,
      );
      await origin.refresh();
      if (mounted) {
        _invalidateView();
      }
      if (result.error is StaleTaskSnapshot) bulkConflict = true;
      if (!bulkConflict) bulkSnapshot = origin.taskSnapshot;
      bulkPending = result.remainingIds.where((id) {
        final task = origin.rows
            .where((row) => row['id'] == id && row['kind'] == 'task')
            .firstOrNull;
        return task != null &&
            !((edit.assignee == null || edit.assignee == task['assignee']) &&
                edit.schedulePatch.entries.every(
                  (field) =>
                      (task['schedule'] as Map)[field.key] == field.value,
                ) &&
                edit.addTags.every(
                  (tag) => (task['tags'] as List).contains(tag),
                ) &&
                edit.removeTags.every(
                  (tag) => !(task['tags'] as List).contains(tag),
                ));
      }).toList();
      if (!result.succeeded) {
        selectedTasks
          ..clear()
          ..addAll(bulkPending);
        throw StateError(
          '${result.committedIds.length + result.remainingIds.length - bulkPending.length} confirmed saved after refresh; ${bulkPending.length} remain. ${failureMessage(result.error!)}',
        );
      }
      selectedTasks.clear();
    } catch (error) {
      if (error is StaleTaskSnapshot) bulkConflict = true;
      await origin.refresh();
      if (mounted) {
        _invalidateView();
      }
      rethrow;
    }
  }

  String _targetBaseline(Map<String, dynamic> task) => jsonEncode({
    for (final key in [
      'id',
      'title',
      'description',
      'schedule',
      'assignee',
      'tagRefs',
      'completed',
    ])
      key: task[key],
  });
  String _nonTextBaseline(Map<String, dynamic> task) => jsonEncode({
    for (final key in ['id', 'schedule', 'assignee', 'tagRefs', 'completed'])
      key: task[key],
  });
  bool _nonTextUnchanged(TaskStore origin, Map<String, dynamic> frozen) {
    final current = origin.visibleTaskRow(frozen['id'] as String);
    return sharedSafetyError == null &&
        identical(store, origin) &&
        current != null &&
        _nonTextBaseline(current) == _nonTextBaseline(frozen);
  }

  Map<String, dynamic> _displayTask(Map<String, dynamic> task) =>
      task['textUnavailable'] == null
      ? Map<String, dynamic>.from(task)
      : {...task, 'title': 'Text unavailable', 'description': ''};
  bool _targetUnchanged(TaskStore origin, Map<String, dynamic> frozen) {
    final current = origin.visibleTaskRow(frozen['id'] as String);
    return sharedSafetyError == null &&
        identical(store, origin) &&
        current != null &&
        _targetBaseline(current) == _targetBaseline(frozen);
  }

  // The narrow editor shares the host diagnostic without letting a sibling
  // notice take all of its keyboard-safe height. Wide panels keep the banner.
  bool get _taskModalOpen =>
      !foodVisible &&
      store != null &&
      user != null &&
      taskView != null &&
      viewError == null &&
      sharedSafetyError == null &&
      _taskEditorModalAtWidth(
        MediaQuery.sizeOf(context).width -
            MediaQuery.paddingOf(context).horizontal,
      );

  bool _taskEditorModalAtWidth(double width) =>
      width < 900 &&
      (editingTask != null || editingBulk != null) &&
      (!selecting ||
          mobileEditorOpen ||
          (wideLayout &&
              (editorKey.currentState != null ||
                  bulkEditorKey.currentState != null)));

  Widget _actionErrorNotice() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    child: Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 12),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  primary: false,
                  key: const ValueKey('action-error-scroll'),
                  child: Shortcuts(
                    shortcuts: const {
                      SingleActivator(LogicalKeyboardKey.arrowDown):
                          ScrollIntent(direction: AxisDirection.down),
                      SingleActivator(LogicalKeyboardKey.arrowUp): ScrollIntent(
                        direction: AxisDirection.up,
                      ),
                    },
                    child: Focus(
                      key: const ValueKey('action-error-details'),
                      child: Text(error!),
                    ),
                  ),
                ),
              ),
            ),
            if (errorFromRefresh && store != null)
              TextButton(
                onPressed: busy ? null : _retryFolderRead,
                child: const Text('Retry'),
              ),
            if (!settingsLoaded)
              TextButton(
                onPressed: busy ? null : _retryStartup,
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _editorSurface(
    Widget list,
    List<Map<String, dynamic>> users,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final panel = constraints.maxWidth >= EditorSurface.breakpoint;
      if (editingTask == null && editingBulk == null) {
        wideLayout = panel;
        return EditorSurface(list: list, panel: panel);
      }
      final modal = _taskEditorModalAtWidth(constraints.maxWidth);
      if (wideLayout &&
          modal &&
          (editorKey.currentState != null ||
              bulkEditorKey.currentState != null)) {
        mobileEditorOpen = true;
      }
      wideLayout = panel;
      if (!panel && !modal) return EditorSurface(list: list, panel: panel);
      final task = editingTask;
      final editor = task != null
          ? TaskEditor(
              key: editorKey,
              timeZonePolicy: _timeZonePolicy,
              onCloseReadinessChanged: _wakeSectionRequests,
              contextNotice:
                  !panel && error != null && sharedSafetyError == null
                  ? _actionErrorNotice()
                  : null,
              task: task,
              tagInventory: _tagInventory(),
              textSession: editingText,
              textStatus: editingTextStatus,
              disableTextFields: editingText == null,
              users: users,
              panel: panel,
              onClose: () {
                editingText?.cancel();
                if (editingText != null) {
                  editorStore?.releaseTextCapture(editingText!.capture);
                }
                setState(() {
                  editingTask = null;
                  editingText = null;
                  textSaveCommand = null;
                  editingTextStatus = null;
                  _clearSelection();
                });
              },
              onDelete: () async {
                final origin = editorStore!;
                await origin.refresh();
                if (!_targetUnchanged(origin, task)) {
                  throw StateError(
                    'This task changed. Close and reopen it to review before deleting.',
                  );
                }
                await _recordAction(
                  origin,
                  'deleting',
                  (prepared) => origin.deleteTask(
                    task['id'],
                    expectedTaskSnapshot: null,
                    canCommit: () => _targetUnchanged(origin, task),
                    onPrepared: prepared,
                  ),
                  notice: true,
                );
                await origin.refresh();
                if (mounted) {
                  _invalidateView();
                }
              },
              save: (fields, addedTags, removedTags) async {
                final origin = editorStore!;
                await syncing;
                _requireCommandSafety(origin);
                if (!identical(store, origin)) {
                  throw StateError('The data folder changed. Reopen the task.');
                }
                await origin.refresh();
                if (!_nonTextUnchanged(origin, task) &&
                    !(editingText?.hasPendingReceipt ?? false)) {
                  throw StateError(
                    'This task’s other details changed. Your draft is kept; close and reopen it to review before saving.',
                  );
                }
                final tags = Set<String>.from(task['tags'] as List? ?? [])
                  ..addAll(addedTags)
                  ..removeAll(removedTags);
                if (textSaveCommand != null) {
                  final result = await _recordAction(
                    origin,
                    'editing',
                    (prepared) => textSaveCommand!.save(
                      fields: fields,
                      tags: tags.toList(),
                      observedTagRefs: Map<String, String>.from(
                        task['tagRefs'] as Map? ?? {},
                      ),
                      canCommit: () => _nonTextUnchanged(origin, task),
                      onPrepared: prepared,
                    ),
                  );
                  if (result.sessionError != null) {
                    throw StateError(
                      'Saved to the folder. Use Retry Save to finish opening the next editor draft.',
                    );
                  }
                  if (result.undoError != null && mounted && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Saved. Undo is unavailable for this change.',
                        ),
                      ),
                    );
                  }
                } else if (fields.isNotEmpty ||
                    addedTags.isNotEmpty ||
                    removedTags.isNotEmpty) {
                  await _recordAction(
                    origin,
                    'editing',
                    (prepared) => origin.edit(
                      task['id'],
                      fields,
                      tags: tags.toList(),
                      observedTagRefs: Map<String, String>.from(
                        task['tagRefs'] as Map? ?? {},
                      ),
                      canCommit: () => _nonTextUnchanged(origin, task),
                      onPrepared: prepared,
                    ),
                  );
                }
                if (mounted) {
                  setState(() {
                    final saved = rows
                        .where(
                          (row) =>
                              row['id'] == task['id'] && row['kind'] == 'task',
                        )
                        .firstOrNull;
                    if (saved != null) editingTask = _displayTask(saved);
                  });
                  _invalidateView();
                }
              },
            )
          : BulkTaskEditor(
              key: bulkEditorKey,
              timeZonePolicy: _timeZonePolicy,
              onCloseReadinessChanged: _wakeSectionRequests,
              contextNotice:
                  !panel && error != null && sharedSafetyError == null
                  ? _actionErrorNotice()
                  : null,
              tasks: editingBulk!,
              tagInventory: _tagInventory(),
              users: users,
              panel: panel,
              onClose: () {
                setState(() {
                  editingBulk = null;
                  _clearSelection();
                });
              },
              onSave: _saveBulk,
              onDelete: () async {
                final origin = editorStore!;
                final ids = List<String>.of(bulkPending);
                if (ids.isEmpty) return;
                if (bulkConflict) {
                  throw StateError(
                    'These tasks changed. Close and reopen the selection to review before deleting.',
                  );
                }
                final result = await _recordAction(
                  origin,
                  'deleting',
                  (prepared) => origin.deleteTasks(
                    ids,
                    expectedTaskSnapshot: bulkSnapshot!,
                    canCommit: _bulkGuard(ids),
                    onPrepared: prepared,
                  ),
                  group: (bulkEditorKey, 'delete'),
                  notice: true,
                );
                await origin.refresh();
                if (result.error is StaleTaskSnapshot) {
                  bulkConflict = true;
                } else {
                  bulkSnapshot = origin.taskSnapshot;
                }
                bulkPending = result.remainingIds
                    .where(
                      (id) => origin.rows.any(
                        (row) => row['id'] == id && row['kind'] == 'task',
                      ),
                    )
                    .toList();
                if (mounted) {
                  _invalidateView();
                }
                if (!result.succeeded) {
                  throw StateError(
                    '${ids.length - bulkPending.length} confirmed deleted after refresh; ${bulkPending.length} remain. ${failureMessage(result.error!)}',
                  );
                }
              },
            );
      return EditorSurface(list: list, editor: editor, panel: panel);
    },
  );

  Future<void> _keyboardMove(Map<String, dynamic> task, bool up) =>
      _act(() async {
        final entries = visibleEntries;
        final index = entries.indexWhere(
          (entry) => entry.task['id'] == task['id'],
        );
        final neighbor = index + (up ? -1 : 1);
        if (index < 0 ||
            neighbor < 0 ||
            neighbor >= entries.length ||
            !entries[index].sharesOrderBucket(entries[neighbor])) {
          return;
        }
        final global = rows
            .where((row) => row['kind'] == 'task' && row['id'] != task['id'])
            .toList();
        final target = entries[neighbor].task['id'] as String;
        final anchor = global.indexWhere((row) => row['id'] == target);
        final before = up
            ? target
            : (anchor + 1 < global.length
                  ? global[anchor + 1]['id'] as String
                  : null);
        await _moveBeforeGuarded(
          task['id'],
          before,
          store!.taskSnapshot,
          _moveCommitGuard(task['id'], target),
        );
      });

  Future<void> _moveBeforeGuarded(
    String id,
    String? before,
    String snapshot,
    bool Function() canCommit,
  ) async {
    try {
      final origin = store!;
      await _recordAction(
        origin,
        'moving',
        (prepared) => origin.moveBefore(
          id,
          before,
          expectedTaskSnapshot: snapshot,
          canCommit: canCommit,
          onPrepared: prepared,
        ),
      );
    } on StaleTaskSnapshot {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The task list changed. Try moving the task again.'),
        ),
      );
    }
  }

  bool Function() _moveCommitGuard(
    String source,
    String target, {
    bool Function(List<TaskViewEntry>, List<Map<String, dynamic>>)?
    permitsProjection,
  }) {
    final origin = store,
        revision = viewRevision,
        completed =
            visibleEntries
                .where((entry) => entry.task['id'] == source)
                .firstOrNull
                ?.task['completed'] ==
            true,
        query = searchQuery,
        everyone = all,
        upcoming = showUpcoming,
        selected = user,
        tags = Set<String>.of(selectedTags);
    final entries = visibleEntries;
    final expected = entries
        .where((entry) => entry.task['id'] == source)
        .firstOrNull;
    return () {
      if (!mounted ||
          origin == null ||
          expected == null ||
          !identical(origin, store) ||
          revision != viewRevision ||
          query != searchQuery ||
          (!searching && completed != showCompleted) ||
          everyone != all ||
          upcoming != showUpcoming ||
          selected != user ||
          !setEquals(tags, selectedTags) ||
          !timeSource.ready) {
        return false;
      }
      try {
        // Evaluate the actual current wall clock at the serialized write boundary;
        // a delayed timer callback must not authorize an expired sort bucket.
        final currentRows = origin.rows;
        final current = projectTaskView(
          currentRows,
          timeSource.readTime(),
          assignee: everyone ? null : selected,
          includeUpcoming: upcoming,
          tags: tags,
          searchQuery: query,
        ).value;
        final visible = completed ? current.completed : current.open;
        final from = visible
            .where((entry) => entry.task['id'] == source)
            .firstOrNull;
        final to = visible
            .where((entry) => entry.task['id'] == target)
            .firstOrNull;
        return from != null &&
            to != null &&
            (from.task['completed'] == true) == completed &&
            (to.task['completed'] == true) == completed &&
            from.sharesOrderBucket(expected) &&
            to.sharesOrderBucket(expected) &&
            (permitsProjection?.call(visible, currentRows) ?? true);
      } catch (_) {
        return false;
      }
    };
  }

  bool _dragIsCurrent() {
    final drag = taskDrag;
    return drag != null &&
        foreground &&
        !busy &&
        identical(drag.store, store) &&
        drag.revision == viewRevision &&
        drag.query == searchQuery &&
        (searching || drag.completed == showCompleted) &&
        drag.everyone == all &&
        drag.upcoming == showUpcoming &&
        drag.user == user &&
        setEquals(drag.tags, selectedTags) &&
        setEquals(
          drag.selected,
          selecting && selectedTasks.contains(drag.id)
              ? selectedTasks
              : {drag.id},
        );
  }

  bool _canDropTask(String source, String target) {
    if (!_dragIsCurrent() || taskDrag!.id != source || source == target) {
      return false;
    }
    final entries = visibleEntries;
    final ids = taskDrag!.selected;
    if (ids.contains(target)) return false;
    final to = entries.where((entry) => entry.task['id'] == target).firstOrNull;
    return to != null &&
        ids.every((id) {
          final from = entries
              .where((entry) => entry.task['id'] == id)
              .firstOrNull;
          return from != null && from.sharesOrderBucket(to);
        });
  }

  void _cancelDrag() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _dragIsCurrent()
              ? 'Reorder canceled. Drop beside a task with the same group, date and time.'
              : 'The task list changed. Try dragging again.',
        ),
      ),
    );
  }

  VisibleTaskMovePlan? _taskDropPlan(
    String target,
    bool after,
    Set<String> moving, {
    List<TaskViewEntry>? entries,
    List<Map<String, dynamic>>? taskRows,
  }) {
    final visible = entries ?? visibleEntries;
    final to = visible.where((entry) => entry.task['id'] == target).firstOrNull;
    if (to == null ||
        !moving.every((id) {
          final from = visible
              .where((entry) => entry.task['id'] == id)
              .firstOrNull;
          return from != null && from.sharesOrderBucket(to);
        })) {
      return null;
    }
    return resolveVisibleTaskMove(
      globalOrder: (taskRows ?? rows)
          .where((row) => row['kind'] == 'task')
          .map((row) => row['id'] as String)
          .toList(),
      visibleOrder: visible
          .where((entry) => entry.sharesOrderBucket(to))
          .map((entry) => entry.task['id'] as String)
          .toList(),
      moving: moving,
      target: target,
      after: after,
    );
  }

  Future<void> _dropTask(String source, String target, bool after) async {
    // Capture the session before Draggable ends it; await any in-flight import,
    // then recheck the projection before writing a relative-order event.
    final drag = taskDrag;
    if (!_canDropTask(source, target)) {
      _cancelDrag();
      return;
    }
    if (!mounted) return;
    await _act(() async {
      if (drag == null ||
          !identical(drag.store, store) ||
          drag.revision != viewRevision ||
          drag.query != searchQuery ||
          (!searching && drag.completed != showCompleted) ||
          drag.everyone != all ||
          drag.upcoming != showUpcoming ||
          drag.user != user ||
          !setEquals(drag.tags, selectedTags)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The task list changed. Try dragging again.'),
          ),
        );
        return;
      }
      void staleMove() => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The task list changed. Try moving the task again.'),
        ),
      );
      if (store!.taskSnapshot != drag.snapshot) {
        staleMove();
        return;
      }
      final insertion = _taskDropPlan(target, after, drag.selected);
      if (insertion == null) return;
      bool sameGap(
        List<TaskViewEntry> entries,
        List<Map<String, dynamic>> currentRows,
      ) {
        final fresh = _taskDropPlan(
          target,
          after,
          drag.selected,
          entries: entries,
          taskRows: currentRows,
        );
        return fresh != null && insertion.sameGap(fresh);
      }

      final guard = _moveCommitGuard(
        source,
        target,
        permitsProjection: sameGap,
      );
      // Even no-op drops must belong to the current projection. Preserve both
      // canonical bytes and existing Undo history when visible order is unchanged.
      if (!guard()) {
        staleMove();
        return;
      }
      if (insertion.noOp) return;
      final before = insertion.before;
      if (drag.selected.length == 1) {
        await _moveBeforeGuarded(source, before, drag.snapshot, guard);
      } else {
        final ids = drag.selected.toList();
        final contextGuard = _bulkGuard(ids);
        final expected = visibleEntries
            .where((entry) => entry.task['id'] == source)
            .first;
        bool canCommit() {
          if (!contextGuard()) return false;
          final currentRows = store!.rows;
          final view = projectTaskView(
            currentRows,
            timeSource.readTime(),
            assignee: all ? null : user,
            includeUpcoming: showUpcoming,
            tags: Set.of(selectedTags),
            searchQuery: searchQuery,
          ).value;
          final entries = searching
              ? [...view.open, ...view.completed]
              : (showCompleted ? view.completed : view.open);
          return sameGap(entries, currentRows) &&
              [...ids, target].every((id) {
                final entry = entries
                    .where((entry) => entry.task['id'] == id)
                    .firstOrNull;
                return entry != null && entry.sharesOrderBucket(expected);
              });
        }

        final origin = store!;
        final result = await _recordAction(
          origin,
          'moving',
          (prepared) => origin.moveBlockBefore(
            ids,
            before,
            expectedTaskSnapshot: drag.snapshot,
            canCommit: canCommit,
            onPrepared: prepared,
          ),
        );
        await store!.refresh();

        if (!result.succeeded) {
          throw StateError(
            '${result.committedIds.length} moves acknowledged; additional moves may have saved. The list was refreshed; review it before dragging again. ${failureMessage(result.error!)}',
          );
        }
      }
    });
  }

  void _stopDragScroll() {
    dragScrollTimer?.cancel();
    dragScrollTimer = null;
    final hadPointer = dragPointer != null;
    dragPointer = null;
    if (hadPointer) dragScrollTick.value++;
  }

  void _updateDragScroll(Offset pointer) {
    dragPointer = pointer;
    dragScrollTick.value++;
    dragScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_dragIsCurrent() || !taskScroll.hasClients) {
        _stopDragScroll();
        return;
      }
      final box = attachedTaskDropBox(taskViewport.currentContext);
      if (box == null || dragPointer == null) return;
      final y = box.globalToLocal(dragPointer!).dy;
      const edge = 72.0;
      final speed = y < edge
          ? -((edge - y) / edge).clamp(0.0, 1.0) * 12
          : y > box.size.height - edge
          ? ((y - box.size.height + edge) / edge).clamp(0.0, 1.0) * 12
          : 0.0;
      if (speed == 0) return;
      final position = taskScroll.position;
      dragScrollTick.value++;
      taskScroll.jumpTo(
        (position.pixels + speed).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  bool _pointerOverGroupHeading(Offset pointer) {
    for (final key in groupHeadingKeys.values) {
      final box = attachedTaskDropBox(key.currentContext);
      if (box != null &&
          box.attached &&
          box.hasSize &&
          (Offset.zero & box.size).contains(box.globalToLocal(pointer))) {
        return true;
      }
    }
    return false;
  }

  ({String target, bool after})? _dropTargetAtPointer(
    String source,
    Offset pointer,
  ) {
    final viewport = attachedTaskDropBox(taskViewport.currentContext);
    if (viewport == null ||
        _pointerOverGroupHeading(pointer) ||
        !(Offset.zero & viewport.size).contains(
          viewport.globalToLocal(pointer),
        )) {
      return null;
    }
    for (final entry in dropKeys.entries) {
      if (entry.key == source) continue;
      final box = attachedTaskDropBox(entry.value.currentContext);
      if (box == null || !box.attached || !box.hasSize) continue;
      final local = box.globalToLocal(pointer);
      if ((Offset.zero & box.size).contains(local)) {
        return (target: entry.key, after: local.dy >= box.size.height / 2);
      }
    }
    return null;
  }

  void _dropAtPointer(String source, Offset pointer) {
    final target = _dropTargetAtPointer(source, pointer);
    if (target == null) {
      _cancelDrag();
    } else {
      _dropTask(source, target.target, target.after);
    }
  }

  Rect? _taskInsertionRect() {
    final drag = taskDrag, pointer = dragPointer;
    if (drag == null || pointer == null || !_dragIsCurrent()) return null;
    final target = _dropTargetAtPointer(drag.id, pointer);
    if (target == null || !_canDropTask(drag.id, target.target)) return null;
    final plan = _taskDropPlan(target.target, target.after, drag.selected);
    if (plan == null) return null;
    final before = plan.visibleBefore;
    RenderBox? boxFor(String id) =>
        attachedTaskDropBox(dropKeys[id]?.currentContext);
    final viewport = attachedTaskDropBox(taskViewport.currentContext);
    if (viewport == null || !viewport.attached || !viewport.hasSize) {
      return null;
    }
    var anchor = before == null ? null : boxFor(before);
    final candidateTop = anchor != null && anchor.attached && anchor.hasSize
        ? viewport.globalToLocal(anchor.localToGlobal(Offset.zero))
        : null;
    final visibleTop =
        candidateTop != null &&
        candidateTop.dy >= 0 &&
        candidateTop.dy + 2 <= viewport.size.height &&
        _canDropTask(drag.id, before!);
    if (!visibleTop) {
      final earlier = plan.visibleAfter;
      anchor = earlier == null ? null : boxFor(earlier);
    }
    if (anchor == null || !anchor.attached || !anchor.hasSize) return null;
    // The visible edge comes from the same plan as the saved destination.
    // Hidden global successors at bucket end never become paint anchors.
    final top = visibleTop;
    final origin = viewport.globalToLocal(
      anchor.localToGlobal(Offset(0, top ? 0 : anchor.size.height - 2)),
    );
    return Rect.fromLTWH(origin.dx, origin.dy, anchor.size.width, 2);
  }

  Widget _reorderableTask(Map<String, dynamic> task, Widget tile) {
    var after = false;
    return ValueListenableBuilder<int>(
      valueListenable: dragScrollTick,
      builder: (_, _, _) => StatefulBuilder(
        builder: (context, updateHover) => DragTarget<String>(
          key: dropKeys.putIfAbsent(task['id'] as String, GlobalKey.new),
          onWillAcceptWithDetails: (details) =>
              _canDropTask(details.data, task['id']),
          onMove: (details) {
            final box = attachedTaskDropBox(context);
            if (box == null) return;
            final next =
                box.globalToLocal(details.offset).dy >= box.size.height / 2;
            if (next != after) updateHover(() => after = next);
          },
          // Draggable resolves the release geometry below: cached targets can
          // scroll away while the pointer remains stationary at an edge.
          onAcceptWithDetails: (_) {},
          builder: (context, candidates, rejected) {
            final box = attachedTaskDropBox(context);
            final localPointer =
                dragPointer == null || box == null || !box.hasSize
                ? null
                : box.globalToLocal(dragPointer!);
            final hovering =
                localPointer != null &&
                !_pointerOverGroupHeading(dragPointer!) &&
                (Offset.zero & box!.size).contains(localPointer);
            if (hovering) after = localPointer.dy >= box.size.height / 2;
            final invalid = dragPointer != null
                ? hovering && !_canDropTask(taskDrag!.id, task['id'])
                : rejected.isNotEmpty ||
                      candidates.whereType<String>().any(
                        (source) => !_canDropTask(source, task['id']),
                      );
            return MouseRegion(
              cursor: invalid
                  ? SystemMouseCursors.forbidden
                  : SystemMouseCursors.basic,
              child: Semantics(
                liveRegion: invalid,
                label: invalid
                    ? 'Cannot reorder here: different group, date or time, or the list changed.'
                    : null,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    color: invalid
                        ? Theme.of(
                            context,
                          ).colorScheme.errorContainer.withValues(alpha: 0.4)
                        : null,
                    border: invalid
                        ? Border.all(
                            color: Theme.of(context).colorScheme.error,
                            width: 2,
                          )
                        : null,
                  ),
                  child: Material(type: MaterialType.transparency, child: tile),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _taskMetadata(
    Map<String, dynamic> task,
    List<Map<String, dynamic>> users,
    String? groupDate,
    TaskViewEntry entry,
  ) {
    final schedule = task['schedule'] as Map<String, dynamic>? ?? {};
    return [
      if (all || searching)
        users
                .where((u) => u['id'] == task['assignee'])
                .map((u) => u['name'])
                .firstOrNull ??
            'Unknown user',
      if ((task['completed'] != true
              ? scheduleMetadata(
                  schedule,
                  groupDate:
                      entry.today &&
                          entry.effectiveDate != null &&
                          formatCivilDate(entry.effectiveDate!) != groupDate
                      ? null
                      : groupDate,
                  localZoneId: taskViewZoneId!,
                  viewInstant: taskViewInstant!,
                  unavailableStart:
                      !entry.available && task['completed'] != true
                      ? entry.availabilityStart
                      : null,
                )
              : '')
          case final String details when details.isNotEmpty)
        details,
      for (final tag in task['tags'] as List? ?? []) '#$tag',
    ].join(' · ');
  }

  Widget _taskTitle(
    Map<String, dynamic> task,
    List<Map<String, dynamic>> users,
    String? groupDate,
    TaskViewEntry entry,
  ) {
    final metadata = _taskMetadata(task, users, groupDate, entry);
    final title = Text(
      task['title'] as String,
      key: ValueKey('task-title-${task['id']}'),
      style: const TextStyle(fontWeight: FontWeight.w500),
    );
    if (metadata.isEmpty) return title;
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final details = Text(
      metadata,
      key: ValueKey('task-metadata-${task['id']}'),
      style: style,
    );
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [title, details],
    );
  }

  List<Map<String, dynamic>> _checklistItems(Map<String, dynamic> task) =>
      (task['checklist'] as List? ?? []).cast<Map<String, dynamic>>();

  Future<void> _setChecklistExpansion(
    TaskStore origin,
    Set<String> requested,
    bool expanded, {
    bool focusAdd = false,
  }) async {
    if (busy || !identical(store, origin)) return;
    if (!expanded && !await _closeChecklistEditor()) return;
    await syncing;
    if (!mounted || busy || !identical(store, origin)) return;
    final visible = visibleEntries.map((entry) => entry.task['id']).toSet();
    final ids = requested.intersection(visible.cast<String>());
    if (ids.isEmpty) return;
    try {
      ChecklistExpansionStore(
        origin.db,
        tables: origin.tables,
        profileDatabase: profileDatabase,
      ).setExpanded(ids, expanded);
    } catch (failure) {
      // Display preferences are dispensable; a cache preference failure must
      // not block opening items or alter canonical command/error ownership.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not remember checklist display. ${failureMessage(failure)}',
          ),
        ),
      );
    }
    setState(() {
      if (expanded) {
        expandedChecklists.addAll(ids);
      } else {
        expandedChecklists.removeAll(ids);
      }
    });
    if (focusAdd && ids.length == 1) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          !identical(store, origin) ||
          !expandedChecklists.contains(ids.single)) {
        return;
      }
      final node = checklistAddFocus[ids.single];
      final target = node?.context;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 120),
          alignment: .8,
        );
        if (mounted && identical(store, origin)) node!.requestFocus();
      }
    }
  }

  Future<void> _showTaskMenu(
    TaskStore origin,
    Map<String, dynamic> task, {
    Offset? position,
  }) async {
    if (_exitQuiescing || !identical(store, origin) || busy || taskMenuOpen) {
      return;
    }
    final id = task['id'] as String;
    final anchor = taskMenuKeys[id]?.currentContext?.findRenderObject();
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (anchor is! RenderBox || overlay is! RenderBox || !anchor.hasSize) {
      return;
    }
    final point = overlay.globalToLocal(
      position ?? anchor.localToGlobal(Offset(0, anchor.size.height)),
    );
    taskMenuOpen = true;
    try {
      final choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(point.dx, point.dy, 1, 1),
          Offset.zero & overlay.size,
        ),
        requestFocus: true,
        items: [
          TaskActionsMenuEntry(
            viewRevision: taskMenuRevision,
            canAddChecklist: () {
              if (!mounted || !identical(store, origin)) return false;
              final current = origin.currentTextRow(id);
              return current != null &&
                  current['kind'] == 'task' &&
                  _checklistItems(current).isEmpty;
            },
          ),
        ],
      );
      if (!mounted ||
          busy ||
          !identical(store, origin) ||
          origin.currentTextRow(id)?['kind'] != 'task') {
        return;
      }
      if (choice == 'checklist') {
        // A retained callback cannot revive Add checklist after incoming items.
        if (_checklistItems(origin.currentTextRow(id)!).isNotEmpty) return;
        await _setChecklistExpansion(origin, {id}, true, focusAdd: true);
      } else if (choice == 'delete') {
        await _deleteTaskFromMenu(origin, id);
      }
    } catch (failure) {
      if (mounted && identical(store, origin)) {
        setState(() => error = failureMessage(failure));
      }
    } finally {
      taskMenuOpen = false;
    }
  }

  Future<void> _deleteTaskFromMenu(TaskStore origin, String id) async {
    if (busy ||
        !identical(store, origin) ||
        !await _closeEditor() ||
        !mounted ||
        !identical(store, origin)) {
      return;
    }
    await origin.refresh();
    if (!mounted || !identical(store, origin)) return;
    final task = origin.currentTextRow(id);
    if (task == null || task['kind'] != 'task') return;
    var answered = false;
    void decide(BuildContext dialog, bool answer) {
      if (answered ||
          !dialog.mounted ||
          ModalRoute.of(dialog)?.isCurrent != true) {
        return;
      }
      answered = true;
      Navigator.pop(dialog, answer);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text(
          'Delete “${task['title']}”? Future repeating tasks are separate entries. You can undo this change.',
        ),
        actions: [
          TextButton(
            onPressed: () => decide(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => decide(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !identical(store, origin)) return;
    await _act(() async {
      if (!mounted || !identical(store, origin)) return;
      await _recordAction(
        origin,
        'deleting',
        (prepared) => origin.deleteTask(
          id,
          expectedTaskSnapshot: origin.taskSnapshot,
          canCommit: () =>
              mounted &&
              identical(store, origin) &&
              _targetUnchanged(origin, task),
          onPrepared: prepared,
        ),
        notice: true,
      );
      if (mounted && identical(store, origin)) {
        setState(() {
          selectedTasks.remove(id);
          if (selectedTasks.isEmpty) selecting = false;
          if (selectionAnchor == id) selectionAnchor = null;
        });
      }
    });
  }

  Widget _checklistDisclosure(TaskStore origin, Map<String, dynamic> task) {
    final id = task['id'] as String, items = _checklistItems(task);
    final expanded = expandedChecklists.contains(id);
    final complete = items.where((item) => item['completed'] == true).length;
    final label =
        '${expanded ? 'Collapse' : 'Expand'} checklist for ${task['title']}: $complete of ${items.length} complete';
    final count = items.isEmpty ? 'Checklist' : '$complete/${items.length}';
    final textStyle = Theme.of(context).textTheme.labelLarge!;
    final textMetrics = TextPainter(
      text: TextSpan(text: count, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final inkHeight =
        textMetrics.height.clamp(18, double.infinity).toDouble() + 4;
    final contentWidth = 13 + textMetrics.width;
    final targetWidth = contentWidth.clamp(48, double.infinity).toDouble();
    final targetHeight = inkHeight + 4;
    final inkWidth = contentWidth + 16;
    textMetrics.dispose();
    final defaults = TextButton(
      onPressed: () {},
      child: const SizedBox(),
    ).defaultStyleOf(context).merge(TextButtonTheme.of(context).style);
    final foreground = defaults.foregroundColor!.resolve({
      if (busy) WidgetState.disabled,
    });
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        container: true,
        button: true,
        enabled: !busy,
        expanded: expanded,
        label: label,
        child: SizedBox(
          width: targetWidth,
          height: targetHeight,
          // Material clips ink to its own bounds even with Clip.none. Extend
          // only its paint host; the Stack and inner InkResponse retain the original
          // target bounds. The extra paint margin never borrows a hit region.
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -8,
                right: -8,
                top: 0,
                bottom: 0,
                child: Material(
                  type: MaterialType.transparency,
                  textStyle: textStyle.copyWith(color: foreground),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: InkResponse(
                      key: ValueKey('checklist-disclosure-$id'),
                      onTap: busy
                          ? null
                          : () =>
                                _setChecklistExpansion(origin, {id}, !expanded),
                      canRequestFocus: !busy,
                      enableFeedback: defaults.enableFeedback ?? true,
                      // Rectangle highlights and InkSparkle draw only inside
                      // the target rect. Circle paint clipped to the rounded
                      // border fills both margins without expanding the hit area.
                      containedInkWell: true,
                      highlightShape: BoxShape.circle,
                      radius: inkWidth,
                      splashFactory: InkRipple.splashFactory,
                      overlayColor: defaults.overlayColor,
                      highlightColor: Colors.transparent,
                      customBorder: ChecklistDisclosureInkBorder(
                        inkWidth,
                        inkHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 6),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: IconTheme.merge(
                            data: IconThemeData(color: foreground),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Retain the glyph's visible title-column edge.
                                Align(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: 0.5,
                                  child: Transform.translate(
                                    offset: Offset(
                                      expanded ? -4.5 : -6.4425,
                                      0,
                                    ),
                                    child: Icon(
                                      expanded
                                          ? Icons.expand_more
                                          : Icons.chevron_right,
                                      size: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(count),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inlineChecklist(TaskStore origin, Map<String, dynamic> task) {
    final id = task['id'] as String,
        items = _checklistItems(task),
        revision = jsonEncode(task['checklist'] ?? []);
    return Padding(
      key: ValueKey('inline-checklist-$id'),
      padding: const EdgeInsets.fromLTRB(32, 0, 0, 8),
      child: ChecklistPanel(
        parentId: id,
        origin: origin,
        revision: revision,
        items: items,
        addFocusNode: checklistAddFocus.putIfAbsent(
          id,
          () => FocusNode(debugLabel: 'Add item to ${task['title']}'),
        ),
        enabled: !busy && !openingChecklistEditor,
        onAdd: () => _editChecklistItem(origin, id),
        onEdit: (item) => _editChecklistItem(origin, id, item: item),
        onToggle: (item, checked) => _checklistOperation(
          origin,
          'checking',
          (current, prepared) => current.setChecklistCompleted(
            item['id'] as String,
            checked,
            onPrepared: prepared,
          ),
        ),
        onMove: (item, before) => _checklistOperation(
          origin,
          'moving',
          (current, prepared) => current.moveChecklistItem(
            item['id'] as String,
            before,
            canCommit: () =>
                mounted &&
                identical(store, origin) &&
                current.checklistSnapshot(id) == revision,
            onPrepared: prepared,
          ),
        ),
        onDelete: (item) => _deleteChecklistItem(origin, item),
      ),
    );
  }

  Future<void> _reopen(Map<String, dynamic> task) async {
    final origin = store!, observed = store!.activeCompletionIds(task['id']);
    var confirmed = false;
    await _act(() async {
      await _recordAction(
        origin,
        'reopening',
        (prepared) => origin.reopen(task['id'], observed, onPrepared: prepared),
      );
      confirmed = true;
    });
    if (!confirmed || !mounted || !identical(store, origin)) return;
    if (origin.activeCompletionIds(task['id']).isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Another completion keeps this task completed.'),
        ),
      );
    } else if (origin.hasEntity(const Uuid().v5(task['id'], 'successor'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task reopened; next occurrence kept.')),
      );
    }
  }

  Future<void> _complete(Map<String, dynamic> task) async {
    final origin = store!;
    await _act(() async {
      final completed = await _recordAction(
        origin,
        'completing',
        (prepared) => ChecklistCompletionCommand(origin).complete(
          task['id'] as String,
          observeCompletionTime: timeSource.readTime,
          localZoneId: null,
          confirmUnfinished: (items) async {
            if (!mounted || !identical(store, origin)) return false;
            final unfinished = items
                .where((item) => item['completed'] != true)
                .toList();
            var decisionMade = false;
            void decide(BuildContext dialogContext, bool answer) {
              if (decisionMade ||
                  !dialogContext.mounted ||
                  ModalRoute.of(dialogContext)?.isCurrent != true) {
                return;
              }
              decisionMade = true;
              Navigator.pop(dialogContext, answer);
            }

            setState(() => awaitingCompletionConfirmation = true);
            try {
              return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      scrollable: true,
                      title: const Text('Unfinished checklist items'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${unfinished.length} ${unfinished.length == 1 ? 'item is' : 'items are'} still unchecked. Complete this task anyway?',
                          ),
                          const SizedBox(height: 12),
                          for (final item in unfinished)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text('• ${item['title']}'),
                            ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => decide(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => decide(ctx, true),
                          child: const Text('Complete anyway'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            } finally {
              if (mounted) {
                setState(() => awaitingCompletionConfirmation = false);
              }
            }
          },
          onPrepared: prepared,
        ),
        notice: true,
      );
      if (completed != null && mounted && identical(store, origin)) {
        final id = task['id'] as String;
        // Compact selection captures an editor without displaying it. Release
        // that stale capture before ending selection, otherwise the completed
        // task's editor becomes a modal as soon as selecting turns false.
        if (selectedTasks.contains(id) &&
            editorKey.currentState == null &&
            bulkEditorKey.currentState == null) {
          await _closeEditor();
          if (!mounted || !identical(store, origin)) return;
        }
        setState(() {
          selectedTasks.remove(id);
          if (selectedTasks.isEmpty) selecting = false;
          if (selectionAnchor == id) selectionAnchor = null;
        });
      }
    });
  }

  Future<bool> _closeChecklistEditor() =>
      checklistCloseRequest ??= _finishClosingChecklistEditor().whenComplete(
        () => checklistCloseRequest = null,
      );

  Future<bool> _finishClosingChecklistEditor() async {
    if (openingChecklistEditor) return false;
    final key = checklistEditorKey;
    if (key == null) return true;
    final done = checklistEditorDone;
    if (checklistEditorClosing) {
      await done?.future;
      return true;
    }
    final state = key.currentState;
    if (state == null || !await state.canClose()) return false;
    final dialog = checklistDialogContext;
    if (dialog != null && dialog.mounted && !checklistEditorClosing) {
      checklistEditorClosing = true;
      Navigator.pop(dialog);
    }
    await done?.future;
    return true;
  }

  Future<void> _checklistOperation(
    TaskStore origin,
    String verb,
    Future<LogEvent> Function(TaskStore, void Function(OperationReceipt))
    action,
  ) async {
    if (!identical(store, origin)) return;
    await _act(() async {
      if (!mounted || !identical(store, origin)) return;
      await _recordAction(
        origin,
        verb,
        (prepared) => action(origin, prepared),
        noun: 'checklist item',
        notice: verb == 'deleting',
      );
    });
  }

  Future<void> _deleteChecklistItem(
    TaskStore origin,
    Map<String, dynamic> item,
  ) async {
    if (busy || !identical(store, origin)) return;
    var answered = false;
    void decide(BuildContext dialog, bool answer) {
      if (answered ||
          !dialog.mounted ||
          ModalRoute.of(dialog)?.isCurrent != true) {
        return;
      }
      answered = true;
      Navigator.pop(dialog, answer);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete checklist item?'),
        content: Text('Remove “${item['title']}”? You can undo this change.'),
        actions: [
          TextButton(
            onPressed: () => decide(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => decide(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _checklistOperation(
      origin,
      'deleting',
      (origin, prepared) => origin.deleteChecklistItem(
        item['id'] as String,
        onPrepared: prepared,
      ),
    );
  }

  Future<void> _editChecklistItem(
    TaskStore origin,
    String parent, {
    Map<String, dynamic>? item,
  }) async {
    if (_exitQuiescing ||
        busy ||
        openingChecklistEditor ||
        checklistEditorKey != null) {
      return;
    }
    if (!identical(store, origin)) return;
    TaskTextCapture? captured;
    TaskTextSession? session;
    OperationReceipt? creationReceipt;
    Completer<void>? itemSaveDone;
    final id = item?['id'] as String? ?? const Uuid().v4();
    final key = GlobalKey<ChecklistItemEditorState>();
    final editorDone = checklistEditorDone = Completer<void>();
    setState(() => openingChecklistEditor = true);
    try {
      await syncing;
      await origin.refresh();
      if (origin.currentTextRow(parent)?['kind'] != 'task') {
        throw StateError('This task is no longer available.');
      }
      if (item != null) {
        captured = await origin.captureTaskText(id);
        final capture = captured;
        session = TaskTextSession(
          capture,
          registerDraftActor: (field, allocation, actor) =>
              origin.registerTextDraftActor(capture, field, allocation, actor),
        );
      }
      if (!mounted || !identical(store, origin)) return;
      final command = session == null ? null : TextSaveCommand(origin, session);
      checklistEditorKey = key;
      setState(() => openingChecklistEditor = false);
      final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          checklistDialogContext = ctx;
          return ChecklistItemEditor(
            key: key,
            onCloseReadinessChanged: _wakeSectionRequests,
            item: item,
            textSession: session,
            hasPendingReceipt: () => creationReceipt != null,
            onClose: () {
              if (checklistEditorClosing) return;
              checklistEditorClosing = true;
              Navigator.pop(ctx);
            },
            save: (title, notes) async {
              if (busy || !identical(store, origin)) {
                throw StateError(
                  'Wait for the current change, then retry Save.',
                );
              }
              // The shared recovery panel is behind this modal. An explicit
              // Save revalidates repaired history even if the earlier attempt
              // stopped before preparing a receipt. Identity checks, the command
              // fence and any retained receipt still guard the actual write.
              if (sharedSafetyError != null) await _retrySharedRead();
              if (!mounted || busy || !identical(store, origin)) {
                throw StateError(
                  'The workspace changed. Preserve this draft before retrying.',
                );
              }
              final done = activeActionDone = Completer<void>();
              itemSaveDone = done;
              setState(() => busy = true);
              try {
                await syncing;
                _requireCommandSafety(origin);
                if (command == null) {
                  if (creationReceipt != null) {
                    if (!origin
                        .confirmedOperations([creationReceipt!])
                        .contains(creationReceipt!.id)) {
                      await origin.retryTextOperation(creationReceipt!);
                    }
                  } else {
                    await origin.addChecklistItem(
                      parent,
                      title,
                      notes: notes,
                      id: id,
                      onPrepared: (receipt) => creationReceipt = receipt,
                    );
                  }
                } else {
                  final result = await _recordAction(
                    origin,
                    'editing',
                    (prepared) => command.save(
                      fields: {},
                      tags: [],
                      observedTagRefs: {},
                      onPrepared: prepared,
                    ),
                    noun: 'checklist item',
                  );
                  if (result.sessionError != null) {
                    throw StateError(
                      'Saved. Retry to finish reopening this item’s draft. ${failureMessage(result.sessionError!)}',
                    );
                  }
                  if (result.undoError != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Item saved. Undo is unavailable for this change.',
                        ),
                      ),
                    );
                  }
                }
              } finally {
                done.complete();
                if (identical(itemSaveDone, done)) itemSaveDone = null;
                if (identical(activeActionDone, done)) activeActionDone = null;
                if (mounted) {
                  setState(() {
                    busy = false;
                  });
                  _invalidateView();
                  _configureImporter();
                  importer?.request();
                  _wakeSectionRequests();
                }
              }
            },
          );
        },
      );
      // Navigator disposal need not complete its popped future. The transition
      // completion also fires when an application shutdown disposes the route.
      unawaited(Navigator.of(context).push(route));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _wakeSectionRequests();
      });
      await route.completed;
    } catch (failure) {
      if (mounted) setState(() => error = failureMessage(failure));
    } finally {
      // The route has finished disposing controllers before private leases close.
      try {
        await itemSaveDone?.future;
        if (mounted || session?.hasPendingReceipt != true) {
          session?.cancel();
          if (captured != null) origin.releaseTextCapture(captured);
        }
        // In-flight work owns its captured documents until shutdown waits for
        // it. Unacknowledged intent is memory-only and is not retried on restart.
      } finally {
        if (identical(checklistEditorKey, key)) {
          checklistEditorKey = null;
          checklistDialogContext = null;
          checklistEditorClosing = false;
        }
        editorDone.complete();
        if (identical(checklistEditorDone, editorDone)) {
          checklistEditorDone = null;
        }
        if (mounted) {
          setState(() => openingChecklistEditor = false);
          _wakeSectionRequests();
        }
      }
    }
  }

  @override
  void dispose() {
    // Capture route/native completion before disposing controllers. Normal
    // desktop exit already owns this same future even without an unmount.
    final shutdown = _shutdownOnce(
      foodPageKey.currentState?.editorDone,
      repaint: false,
    );
    _detachWorkspaceState();
    FocusManager.instance.removeListener(_focusChanged);
    requestedSection = null;
    _stopDragScroll();
    taskScroll.dispose();
    dragScrollTick.dispose();
    taskMenuRevision.dispose();
    importer?.dispose();
    viewClock.dispose();
    timeSource.dispose();
    WidgetsBinding.instance.removeObserver(this);
    for (final node in rowFocus.values) {
      node.dispose();
    }
    for (final node in checklistAddFocus.values) {
      node.dispose();
    }
    search.dispose();
    searchFocus.dispose();
    bodyFocusScope.dispose();
    capture.dispose();
    captureFocus.dispose();
    setupValidation.dispose();
    captureValidation.dispose();
    firstName.dispose();
    firstNameFocus.dispose();
    unawaited(_observeShutdown(shutdown));
    super.dispose();
  }

  Future<void> _shutdown(Future<void>? foodEditorDone) async {
    Object? firstFailure;
    StackTrace? firstStack;
    Future<void> cleanup(FutureOr<void> Function() close) async {
      try {
        await close();
      } catch (error, stack) {
        firstFailure ??= error;
        firstStack ??= stack;
      }
    }

    // Stop producers first. Existing queued work retains its captures/leases
    // until the same established drain and resource-close order completes.
    await cleanup(() => importer?.stop());
    final navigation = sectionNavigation;
    sectionNavigation = null;
    await cleanup(() => navigation?.dispose());
    await cleanup(_stopDragScroll);
    taskDrag = null;
    await cleanup(timeSource.stop);
    await cleanup(viewClock.stop);
    await cleanup(() => FocusManager.instance.primaryFocus?.unfocus());
    await cleanup(() => starting);
    await cleanup(() => sectionWork);
    await cleanup(() => activeActionDone?.future);
    await cleanup(() => syncing);
    await cleanup(() => checklistEditorDone?.future);
    await cleanup(() => foodEditorDone);
    await cleanup(() => foodStore?.close());
    await cleanup(() => store?.close());
    await cleanup(() => store?.unified?.close());
    await cleanup(() => textEngine?.dispose());
    await cleanup(() => profileDatabase?.close());
    if (firstFailure != null) {
      Error.throwWithStackTrace(firstFailure!, firstStack!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textHasFocus = _textHasFocus;
    _lastTextFocus = textHasFocus;
    if (_exitQuiescing) {
      return const Scaffold(body: Center(child: Text('Closing…')));
    }
    final users = rows.where((r) => r['kind'] == 'user').toList();
    // Setup keeps its private name/focus and established Continue retry. That
    // callback revalidates shared authority before any user creation; other
    // command callbacks retain the same stopped-state admission guard.
    final keepSetupInputs =
        store != null &&
        !foodVisible &&
        user == null &&
        (users.isEmpty || pendingUserId != null);
    // An ordinary diagnostic is a sibling of the protected body. Let its
    // controls participate in keyboard traversal while that notice is visible.
    bodyFocusScope.traversalEdgeBehavior =
        error != null && (sharedSafetyError == null || keepSetupInputs)
        ? TraversalEdgeBehavior.parentScope
        : TraversalEdgeBehavior.closedLoop;
    return PopScope(
      canPop:
          editingTask == null && editingBulk == null && selectedTasks.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_clearTaskSelection());
      },
      child: CallbackShortcuts(
        bindings: {
          if (!foodVisible && !textHasFocus) ...{
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                _undoShortcut,
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                _undoShortcut,
          },
          if (!foodVisible) ...{
            const SingleActivator(LogicalKeyboardKey.escape):
                _clearTaskSelection,
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _openSearch,
          },
        },
        child: FocusScope(
          child: Scaffold(
            // Task controls remain above a closing keyboard after Save takes
            // focus. Food dialogs own their insets without shrinking the page.
            resizeToAvoidBottomInset:
                !foodVisible ||
                ((ModalRoute.isCurrentOf(context) ?? true) && textHasFocus),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: sectionContentConstraints,
                  child: Column(
                    children: [
                      if (sharedSafetyError != null && keepSetupInputs)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              key: const ValueKey('shared-recovery-settings'),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(64, 48),
                                visualDensity: VisualDensity.standard,
                              ),
                              onPressed: busy ? null : _showSettings,
                              child: const Text('Settings'),
                            ),
                          ),
                        ),
                      if (!foodVisible && sharedSafetyError == null)
                        TaskToolbar(
                          sectionMenu: store == null ? null : _sectionMenu,
                          userName:
                              users
                                      .where((entry) => entry['id'] == user)
                                      .firstOrNull?['name']
                                  as String?,
                          count: taskView == null || user == null
                              ? null
                              : _taskCount(showCompleted),
                          countLabels: [_taskCount(false), _taskCount(true)],
                          filter: taskView == null || user == null
                              ? null
                              : _taskFilter,
                          identityMenu: (child) =>
                              _identityMenu(users, child: child),
                          undo: const SizedBox.shrink(),
                          undoAction: (compact) => toolbarAction(
                            compact: compact,
                            label: 'Undo',
                            iconSize: 24,
                            key: const ValueKey('undo-task-action'),
                            tooltip: undoHistory.latest == null
                                ? 'Undo'
                                : 'Undo ${undoHistory.latest!.label}',
                            onPressed:
                                busy ||
                                    closingEditor ||
                                    undoHistory.latest == null
                                ? null
                                : _undoLatest,
                            icon: const Icon(Icons.undo),
                          ),
                          inputModeAction: store != null && user != null
                              ? _taskInputModeControl
                              : null,
                        ),
                      if (!foodVisible || store == null)
                        toolbarProgress(
                          busy: busy && !awaitingCompletionConfirmation,
                        ),
                      if (error != null &&
                          (sharedSafetyError == null || keepSetupInputs) &&
                          !_taskModalOpen)
                        _actionErrorNotice(),
                      if (!foodVisible && occurrenceMigrationError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Some This occurrence dates could not be moved to Due. ${occurrenceMigrationError!}',
                              ),
                              TextButton(
                                onPressed: busy ? null : _refresh,
                                child: const Text('Retry conversion'),
                              ),
                            ],
                          ),
                        ),
                      if (!foodVisible && store?.clockWarning != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Semantics(
                            liveRegion: true,
                            child: Material(
                              color: Theme.of(
                                context,
                              ).colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.schedule_outlined,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onTertiaryContainer,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        store!.clockWarning!,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onTertiaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring:
                                    sharedSafetyError != null &&
                                    !keepSetupInputs,
                                child: ExcludeSemantics(
                                  excluding:
                                      sharedSafetyError != null &&
                                      !keepSetupInputs,
                                  child: FocusScope(
                                    node: bodyFocusScope,
                                    canRequestFocus:
                                        sharedSafetyError == null ||
                                        keepSetupInputs,
                                    descendantsAreFocusable:
                                        sharedSafetyError == null ||
                                        keepSetupInputs,
                                    child:
                                        foodVisible &&
                                            store != null &&
                                            user != null
                                        ? _foodSurface()
                                        : store == null
                                        ? _welcome()
                                        : user == null
                                        ? _users(users)
                                        : viewError != null
                                        ? Center(
                                            child: Padding(
                                              padding: const EdgeInsets.all(24),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(viewError!),
                                                  const SizedBox(height: 12),
                                                  TextButton(
                                                    onPressed: () {
                                                      timeSource.stop();
                                                      timeSource.start();
                                                    },
                                                    child: const Text('Retry'),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        : taskView == null
                                        ? const Center(
                                            child: CircularProgressIndicator(),
                                          )
                                        : _editorSurface(
                                            _tasks(
                                              searching
                                                  ? [
                                                      ...taskView!.openGroups,
                                                      ...taskView!
                                                          .completedGroups,
                                                    ]
                                                  : showCompleted
                                                  ? taskView!.completedGroups
                                                  : taskView!.openGroups,
                                              users,
                                            ),
                                            users,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            if (sharedSafetyError != null && !keepSetupInputs)
                              Positioned.fill(
                                child: ColoredBox(
                                  color: Theme.of(context).colorScheme.surface,
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: SingleChildScrollView(
                                          key: const ValueKey(
                                            'shared-recovery-error-scroll',
                                          ),
                                          primary: false,
                                          child: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Text(
                                                  'Workspace requires recovery',
                                                ),
                                                const SizedBox(height: 12),
                                                Shortcuts(
                                                  shortcuts: const {
                                                    SingleActivator(
                                                      LogicalKeyboardKey
                                                          .arrowDown,
                                                    ): ScrollIntent(
                                                      direction:
                                                          AxisDirection.down,
                                                    ),
                                                    SingleActivator(
                                                      LogicalKeyboardKey
                                                          .arrowUp,
                                                    ): ScrollIntent(
                                                      direction:
                                                          AxisDirection.up,
                                                    ),
                                                  },
                                                  child: Focus(
                                                    key: const ValueKey(
                                                      'shared-recovery-error-details',
                                                    ),
                                                    child: Text(
                                                      sharedSafetyError!,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                const Text(
                                                  'Preserve the profile and data folder. Retry after restoring their integrity.',
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Wrap(
                                          spacing: 12,
                                          runSpacing: 8,
                                          alignment: WrapAlignment.center,
                                          children: [
                                            TextButton(
                                              key: const ValueKey(
                                                'retry-shared-read',
                                              ),
                                              style: TextButton.styleFrom(
                                                minimumSize: const Size(64, 48),
                                                visualDensity:
                                                    VisualDensity.standard,
                                              ),
                                              onPressed: busy
                                                  ? null
                                                  : _retrySharedRead,
                                              child: const Text('Retry'),
                                            ),
                                            TextButton(
                                              key: const ValueKey(
                                                'shared-recovery-settings',
                                              ),
                                              style: TextButton.styleFrom(
                                                minimumSize: const Size(64, 48),
                                                visualDensity:
                                                    VisualDensity.standard,
                                              ),
                                              onPressed: busy
                                                  ? null
                                                  : _showSettings,
                                              child: const Text('Settings'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A little less to remember.',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Text(
            settings?.folder != null
                ? 'Your saved data folder needs attention. Retry it or choose a different folder in Settings.'
                : widget.folderActions.requiresPicker
                ? 'Keep household tasks together, even offline. Choose or create a Tandemlog folder so your sync app can access it.'
                : 'Keep household tasks together, even offline. We’ll create a data folder for you.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 48),
                  visualDensity: VisualDensity.standard,
                  textStyle: Theme.of(context).textTheme.labelLarge,
                ),
                onPressed: busy || choosingFolder || !settingsLoaded
                    ? null
                    : settings!.folder != null
                    ? () => _act(() async {
                        await _open(settings!.folder!);
                      })
                    : widget.folderActions.requiresPicker
                    ? _chooseFolder
                    : _startDefault,
                child: Text(settings?.folder != null ? 'Try again' : 'Start'),
              ),
              if (!widget.folderActions.requiresPicker &&
                  settings?.folder == null)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(64, 48),
                    visualDensity: VisualDensity.standard,
                    textStyle: Theme.of(context).textTheme.labelLarge,
                  ),
                  onPressed: busy || choosingFolder || !settingsLoaded
                      ? null
                      : _chooseFolder,
                  child: const Text('Choose an existing folder'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Set up folder sync whenever you’re ready.'),
        ],
      ),
    ),
  );
  Widget _users(List<Map<String, dynamic>> users) =>
      users.isEmpty || pendingUserId != null
      ? Align(
          alignment: Alignment.bottomCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'What should we call you?',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your name identifies your tasks. Everyone sharing this folder can see and edit them.',
                  ),
                  const SizedBox(height: 24),
                  setupValidation.field(
                    'name',
                    TextField(
                      controller: firstName,
                      focusNode: firstNameFocus,
                      readOnly: pendingUserName != null,
                      autofocus: true,
                      enabled: !busy,
                      maxLength: 100,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Your name',
                        errorText: setupValidation.errorFor('name'),
                        errorMaxLines: 6,
                        counterText: setupValidation.errorFor('name') == null
                            ? null
                            : '',
                        helperText: pendingUserName == null
                            ? null
                            : 'Continue to finish saving this name.',
                      ),
                      onEditingComplete: () {
                        if (pendingUserName == null &&
                            firstName.text.trim().isEmpty) {
                          return;
                        }
                        firstName.clearComposing();
                        firstNameFocus.unfocus();
                      },
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _createFirstUser(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (error != null) _formFailureNotice(error!),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: firstName,
                    builder: (context, draft, _) => ValidationActionButton(
                      validation: setupValidation,
                      enabled:
                          (ModalRoute.isCurrentOf(context) ?? true) &&
                          (pendingUserName != null ||
                              draft.text.trim().isNotEmpty),
                      label: 'Continue',
                      busy: busy,
                      retry: pendingUserName != null,
                      retryLabel: 'Continue',
                      onSubmit: _createFirstUser,
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
      : ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Who’s here?',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Names identify changes. Everyone in this folder can see and edit its tasks.',
            ),
            const SizedBox(height: 20),
            for (final u in users)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(u['name']),
                  onTap: busy
                      ? null
                      : () => _act(() => _selectUser(u['id'] as String)),
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: busy ? null : _addUser,
                icon: const Icon(Icons.add),
                label: const Text('Create user'),
              ),
            ),
          ],
        );
  void _clearSelection() {
    selectedTasks.clear();
    selecting = false;
    selectionAnchor = null;
    mobileEditorOpen = false;
  }

  bool get _canSwitchTaskInput =>
      mounted &&
      !busy &&
      pendingCapture.isEmpty &&
      sharedSafetyError == null &&
      !foodVisible &&
      store != null &&
      user != null;

  Future<void> _switchTaskInput(bool nextCapture) async {
    if (!_canSwitchTaskInput || !await _closeEditor() || !_canSwitchTaskInput) {
      return;
    }
    setState(() {
      if (captureMode != nextCapture) {
        final outgoing = captureMode ? capture.value : search.value;
        (nextCapture ? capture : search).value = outgoing;
        if (!nextCapture) lastSearchText = outgoing.text;
        captureValidation.reset();
        if (error == 'Keep each task title under 500 characters.') error = null;
        captureMode = nextCapture;
      }
      _clearSelection();
    });
    _invalidateView();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canSwitchTaskInput && captureMode == nextCapture && !selecting) {
        (nextCapture ? captureFocus : searchFocus).requestFocus();
      }
    });
  }

  Future<void> _openSearch() => _switchTaskInput(false);

  Widget _taskInputModeControl(bool compact) {
    final callback = _canSwitchTaskInput
        ? () => _switchTaskInput(!captureMode)
        : null;
    final label = captureMode ? 'Search' : 'Add';
    final tooltip = captureMode ? 'Search tasks (Ctrl+F)' : 'Add tasks';
    final key = ValueKey(captureMode ? 'open-search' : 'open-capture');
    return toolbarAction(
      key: key,
      compact: compact,
      tooltip: tooltip,
      icon: Icon(captureMode ? Icons.search : Icons.add),
      label: label,
      onPressed: callback,
    );
  }

  Future<void> _clearSearch() async {
    if (!_canSwitchTaskInput || !await _closeEditor() || !_canSwitchTaskInput) {
      return;
    }
    search.clear();
    lastSearchText = '';
    setState(_clearSelection);
    _invalidateView();
  }

  Widget _searchField() => TextField(
    key: const ValueKey('task-search'),
    controller: search,
    focusNode: searchFocus,
    selectAllOnFocus: false,
    enabled: !busy,
    maxLines: 1,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      labelText: 'Search tasks',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: search.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              onPressed: _canSwitchTaskInput ? _clearSearch : null,
              icon: const Icon(Icons.close),
            ),
    ),
    onChanged: _changeSearch,
  );

  bool get _filtersActive =>
      all || showCompleted || showUpcoming || selectedTags.isNotEmpty;

  void _resetFilters() {
    _clearSelection();
    setState(() {
      all = false;
      showCompleted = false;
      showUpcoming = false;
      selectedTags.clear();
    });
    _invalidateView();
  }

  List<String> _tagInventory({Iterable<String> selected = const []}) {
    final tags = rows
        .where((row) => row['kind'] == 'task')
        .expand((row) => (row['tags'] as List? ?? []).cast<String>())
        .toSet();
    tags.addAll(selected);
    final sortedTags = tags.toList()
      ..sort((a, b) {
        final order = a.toLowerCase().compareTo(b.toLowerCase());
        return order == 0 ? a.compareTo(b) : order;
      });
    return sortedTags;
  }

  Future<void> _showFilters() async {
    if (!await _closeEditor()) return;
    if (!mounted) return;
    final sortedTags = _tagInventory(selected: selectedTags);
    final pickerKey = GlobalKey<TagFilterPickerState>();
    late final _FilterDialogRoute route;
    route = _FilterDialogRoute(
      context: context,
      dropdownOpen: () => pickerKey.currentState?.dropdownOpen ?? false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) {
          void change(VoidCallback action) {
            setState(() {
              _clearSelection();
              action();
            });
            _invalidateView();
            updateDialog(() {});
          }

          final activeName =
              rows.where((row) => row['id'] == user).firstOrNull?['name']
                  as String? ??
              '';
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (!(pickerKey.currentState?.dismissDropdown() ?? false)) {
                  Navigator.pop(dialogContext);
                }
              },
            },
            child: AlertDialog(
              title: const Text('Filter tasks'),
              contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Assignee'),
                      ),
                      RadioGroup<bool>(
                        groupValue: all,
                        onChanged: (value) => change(() => all = value!),
                        child: Column(
                          children: [
                            RadioListTile<bool>(
                              value: false,
                              title: const Text('Active user'),
                              subtitle: Text(activeName),
                            ),
                            const RadioListTile<bool>(
                              value: true,
                              title: Text('Everyone'),
                            ),
                          ],
                        ),
                      ),
                      const Divider(),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Status'),
                      ),
                      RadioGroup<bool>(
                        groupValue: showCompleted,
                        onChanged: (value) =>
                            change(() => showCompleted = value!),
                        child: const Column(
                          children: [
                            RadioListTile<bool>(
                              value: false,
                              title: Text('Open'),
                            ),
                            RadioListTile<bool>(
                              value: true,
                              title: Text('Completed'),
                            ),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('Show upcoming'),
                        value: showUpcoming,
                        onChanged: (value) =>
                            change(() => showUpcoming = value),
                      ),
                      const Divider(),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Tags (match any)'),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TagFilterPicker(
                          key: pickerKey,
                          tags: sortedTags,
                          selected: Set.of(selectedTags),
                          onChanged: (tags) => change(() {
                            selectedTags
                              ..clear()
                              ..addAll(tags);
                          }),
                          onQueryChanged: () => updateDialog(() {}),
                          onDropdownChanged: (_) =>
                              route.changedExternalState(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      _filtersActive ||
                          (pickerKey.currentState?.hasQuery ?? false)
                      ? () {
                          _resetFilters();
                          pickerKey.currentState?.clearQuery();
                          updateDialog(() {});
                        }
                      : null,
                  child: const Text('Reset'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        },
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
  }

  Widget _identityMenu(List<Map<String, dynamic>> users, {Widget? child}) {
    final name =
        users.where((entry) => entry['id'] == user).firstOrNull?['name']
            as String?;
    if (name == null) {
      return IconButton(
        tooltip: 'Settings',
        onPressed: busy ? null : _showSettings,
        icon: const Icon(Icons.settings_outlined),
      );
    }
    return PopupMenuButton<String>(
      key: const ValueKey('identity-menu'),
      tooltip: 'Active user: $name',
      enabled: !busy,
      onSelected: (value) async {
        if (value == 'activity') {
          final history = store?.unified;
          if (history != null) {
            await showDialog<void>(
              context: context,
              builder: (_) => ActivityLogDialog(history: history),
            );
          }
        } else if (value == 'settings') {
          _showSettings();
        } else {
          final origin = store, previousUser = user;
          bool canSwitch() =>
              mounted &&
              !busy &&
              sharedSafetyError == null &&
              pendingCapture.isEmpty &&
              !(foodStore?.hasPreparedAppend ?? false) &&
              pendingFoodCommand == null &&
              identical(store, origin) &&
              user == previousUser;
          if (!canSwitch() ||
              !await _closeEditor() ||
              !await _closeFoodEditor() ||
              !canSwitch()) {
            return;
          }
          final tasksRevision = value == 'new' ? ++sectionRevision : null;
          if (tasksRevision != null) sectionNavigation?.manualNavigation();
          await _act(
            () => _selectUser(
              value == 'new' ? null : value,
              tasksRevision: tasksRevision,
            ),
          );
        }
      },
      itemBuilder: (_) => [
        for (final entry in users)
          CheckedPopupMenuItem(
            value: entry['id'] as String,
            checked: entry['id'] == user,
            child: Text(entry['name'] as String),
          ),
        const PopupMenuItem(value: 'new', child: Text('Manage users')),
        const PopupMenuDivider(),
        if (store?.unified != null)
          const PopupMenuItem(value: 'activity', child: Text('Activity log')),
        const PopupMenuItem(value: 'settings', child: Text('Settings')),
      ],
      child: child,
    );
  }

  String _taskCount(bool completed) => searching
      ? '${visibleEntries.length} matches'
      : '${(completed ? taskView?.completed : taskView?.open)?.length ?? 0} ${completed ? 'completed' : 'open'}';

  Widget _taskFilter(bool compact) {
    final tooltip = searching
        ? 'Filters paused while searching all tasks'
        : _filtersActive
        ? 'Filter tasks · active filters'
        : 'Filter tasks';
    final icon = toolbarFilterIcon(active: !searching && _filtersActive);
    return toolbarAction(
      key: const ValueKey('task-filter'),
      compact: compact,
      tooltip: tooltip,
      icon: icon,
      label: 'Filter',
      onPressed: searching ? null : _showFilters,
    );
  }

  Widget _formFailureNotice(String message) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight:
          ((MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom) *
                  .2)
              .clamp(40.0, 120.0),
    ),
    child: SingleChildScrollView(
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    ),
  );

  Widget _captureField() => Focus(
    onKeyEvent: (_, event) {
      final enter =
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      if (widget.folderActions.requiresPicker ||
          !enter ||
          (capture.value.composing.isValid &&
              !capture.value.composing.isCollapsed)) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          if (!busy && pendingCapture.isEmpty) {
            final value = capture.value;
            final selection = value.selection.isValid
                ? value.selection
                : TextSelection.collapsed(offset: value.text.length);
            // Use the editor's user-input path so it reveals the caret
            // after layout, including a newly inserted blank last line.
            final editor = captureFocus.context!
                .findAncestorStateOfType<EditableTextState>()!;
            editor.userUpdateTextEditingValue(
              TextEditingValue(
                text: value.text.replaceRange(
                  selection.start,
                  selection.end,
                  '\n',
                ),
                selection: TextSelection.collapsed(offset: selection.start + 1),
              ),
              SelectionChangedCause.keyboard,
            );
          }
        } else {
          unawaited(_capture());
        }
        return KeyEventResult.handled;
      }
      if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: LayoutBuilder(
      builder: (context, constraints) => captureValidation.field(
        'capture',
        TextField(
          controller: capture,
          focusNode: captureFocus,
          selectAllOnFocus: false,
          readOnly: pendingCapture.isNotEmpty,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 1,
          maxLines: 4,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: 'What needs doing?',
            hintText: 'One task per line',
            errorText: captureValidation.errorFor('capture'),
            errorMaxLines: 3,
            helperText: captureFailure && pendingCapture.isNotEmpty
                ? 'Retry to check these tasks before editing.'
                : widget.folderActions.requiresPicker
                ? null
                : 'Enter to add · Shift+Enter for another task',
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: capture,
              builder: (context, draft, _) => ValidationActionButton(
                buttonKey: const ValueKey('capture-add'),
                validation: captureValidation,
                embedded: true,
                compact:
                    constraints.maxWidth <
                    480 * (MediaQuery.textScalerOf(context).scale(14) / 14),
                tooltip: 'Add tasks',
                enabled:
                    (ModalRoute.isCurrentOf(context) ?? true) &&
                    (pendingCapture.isNotEmpty || draft.text.trim().isNotEmpty),
                label: 'Add',
                busyLabel: 'Adding…',
                busy: busy,
                retry: pendingCapture.isNotEmpty,
                retryLabel: 'Retry Add',
                onSubmit: _submitCaptureButton,
              ),
            ),
          ),
          onEditingComplete: () {
            if (pendingCapture.isEmpty && capture.text.trim().isEmpty) return;
            capture.clearComposing();
            captureFocus.unfocus();
          },
          onSubmitted: (_) => _capture(),
        ),
      ),
    ),
  );

  Widget _entryArea() => TaskEntryArea(
    key: const ValueKey('task-entry-area'),
    selecting: selecting,
    wideLayout: wideLayout,
    editorOpen: mobileEditorOpen,
    captureVisible: true,
    selectionCount: selectedTasks.length,
    maximumSelectionCount: visibleEntries.length,
    onClear: busy ? null : _clearTaskSelection,
    onEdit: busy ? null : _editSelected,
    capture: captureMode ? _captureField() : _searchField(),
  );

  Widget _tasks(List<TaskViewGroup> groups, List<Map<String, dynamic>> users) =>
      LayoutBuilder(
        builder: (context, constraints) =>
            _tasksAtWidth(groups, users, compact: constraints.maxWidth < 600),
      );

  Widget _tasksAtWidth(
    List<TaskViewGroup> groups,
    List<Map<String, dynamic>> users, {
    required bool compact,
  }) {
    final entries = groups.expand((group) => group.entries).toList();
    final visibleIds = entries.map((entry) => entry.task['id']).toSet();
    dropKeys.removeWhere((id, _) => !visibleIds.contains(id));
    final tasks = entries.map((entry) => entry.task).toList();
    final hasDeferredTasks =
        !showCompleted &&
        rows.any(
          (row) =>
              row['kind'] == 'task' &&
              row['completed'] != true &&
              (all || row['assignee'] == user) &&
              (selectedTags.isEmpty ||
                  selectedTags.any(
                    (tag) => (row['tags'] as List? ?? []).contains(tag),
                  )),
        );
    bool movable(Map<String, dynamic> task, bool up) {
      final index = entries.indexWhere(
        (entry) => entry.task['id'] == task['id'],
      );
      final neighbor = index + (up ? -1 : 1);
      return index >= 0 &&
          neighbor >= 0 &&
          neighbor < entries.length &&
          entries[index].sharesOrderBucket(entries[neighbor]);
    }

    String groupTitle(TaskViewGroup group) {
      if (group.inbox) return 'Inbox';
      final completed = group.entries.firstOrNull?.task['completed'] == true;
      if (completed && group.date == null) return 'Completion date unknown';
      if (!completed && group.today) return 'Today';
      const weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      return group.date == null
          ? 'Someday'
          : '${weekdays[group.weekday! - 1]} · ${group.date}';
    }

    String groupId(TaskViewGroup group) =>
        '${group.entries.firstOrNull?.task['completed'] == true}-${group.inbox ? 'inbox' : group.date}';
    final groupIds = groups
        .where((group) => group.entries.isNotEmpty)
        .map(groupId)
        .toSet();
    groupHeadingKeys.removeWhere((id, _) => !groupIds.contains(id));

    final list = Listener(
      onPointerUp: (_) {
        if (taskDrag != null) dragReleased = true;
      },
      onPointerCancel: (_) {
        dragReleased = false;
        _stopDragScroll();
        taskDrag = null;
      },
      child: CustomScrollView(
        key: taskViewport,
        controller: taskScroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverList.list(
              children: [
                if (tasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 56),
                    child: Column(
                      children: [
                        Icon(
                          Icons.done_all,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        SizedBox(height: 12),
                        Text(
                          searching
                              ? 'No tasks match your search'
                              : selectedTags.isNotEmpty
                              ? 'No tasks match the selected tags'
                              : showCompleted
                              ? 'No completed tasks'
                              : hasDeferredTasks
                              ? 'Nothing available yet'
                              : 'No open tasks',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          searching
                              ? 'Search titles and descriptions in this workspace.'
                              : selectedTags.isNotEmpty
                              ? 'Clear the tag filter to see other tasks.'
                              : showCompleted
                              ? 'Completed tasks will appear here.'
                              : hasDeferredTasks
                              ? 'Tasks with a future start will appear when they become available.'
                              : 'Add a task above.',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          for (final group in groups.where((group) => group.entries.isNotEmpty))
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 16),
              sliver: SliverMainAxisGroup(
                key: ValueKey('task-group-${groupId(group)}'),
                slivers: [
                  if (searching &&
                      (identical(group, taskView!.openGroups.firstOrNull) ||
                          identical(
                            group,
                            taskView!.completedGroups.firstOrNull,
                          )))
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 16 : 0,
                          16,
                          compact ? 16 : 0,
                          0,
                        ),
                        child: Semantics(
                          header: true,
                          child: Text(
                            group.entries.first.task['completed'] == true
                                ? 'Completed'
                                : 'Open',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                    ),
                  StickyTaskGroupHeading(
                    headingKey: groupHeadingKeys.putIfAbsent(
                      groupId(group),
                      GlobalKey.new,
                    ),
                    title: groupTitle(group),
                    inset: compact ? 16 : 0,
                  ),
                  SliverList.list(
                    children: [
                      for (final entry in group.entries) ...[
                        Builder(
                          key: ValueKey('task-row-${entry.task['id']}'),
                          builder: (context) {
                            final task = _displayTask(entry.task);
                            final origin = store!;
                            final id = task['id'] as String;
                            final showChecklist =
                                _checklistItems(task).isNotEmpty ||
                                expandedChecklists.contains(id);
                            final completed = searching
                                ? task['completed'] == true
                                : showCompleted;
                            final recurrence =
                                (task['schedule'] as Map)['recurrence']
                                    as String?;
                            final tile = Semantics(
                              label: recurrence == null
                                  ? null
                                  : 'Repeats $recurrence',
                              selected: selectedTasks.contains(task['id']),
                              customSemanticsActions: {
                                const CustomSemanticsAction(
                                  label: 'Select task',
                                ): () => _selectTask(
                                  task,
                                  gesture: SelectionGesture.longPress,
                                ),
                              },
                              child: Focus(
                                focusNode: rowFocus.putIfAbsent(
                                  task['id'] as String,
                                  () => FocusNode(debugLabel: task['title']),
                                ),
                                onFocusChange: (_) {
                                  if (mounted) setState(() {});
                                },
                                onKeyEvent: (_, event) {
                                  if (event is! KeyDownEvent) {
                                    return KeyEventResult.ignored;
                                  }
                                  if (event.logicalKey ==
                                          LogicalKeyboardKey.contextMenu ||
                                      (event.logicalKey ==
                                              LogicalKeyboardKey.f10 &&
                                          HardwareKeyboard
                                              .instance
                                              .isShiftPressed)) {
                                    _showTaskMenu(origin, task);
                                    return KeyEventResult.handled;
                                  }
                                  if (!rowFocus[task['id']]!.hasPrimaryFocus) {
                                    return KeyEventResult.ignored;
                                  }
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.space) {
                                    _selectTask(
                                      task,
                                      gesture: SelectionGesture.toggle,
                                    );
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey ==
                                          LogicalKeyboardKey.arrowUp ||
                                      event.logicalKey ==
                                          LogicalKeyboardKey.arrowDown) {
                                    _focusRelativeTask(
                                      task,
                                      event.logicalKey ==
                                              LogicalKeyboardKey.arrowUp
                                          ? -1
                                          : 1,
                                      HardwareKeyboard.instance.isShiftPressed,
                                    );
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: ListRowSurface(
                                  divider: false,
                                  interactive: !busy,
                                  focused: rowFocus[task['id']]!.hasFocus,
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    minVerticalPadding: 0,
                                    minTileHeight: 48,
                                    horizontalTitleGap: 8,
                                    leading: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!completed &&
                                            entry.completionUnavailableReason !=
                                                null)
                                          UnavailableCompletion(
                                            key: ValueKey(
                                              'completion-unavailable-${task['id']}',
                                            ),
                                            title: task['title'] as String,
                                            repeating: recurrence != null,
                                            reason: entry
                                                .completionUnavailableReason!,
                                            onExplain: () =>
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      entry
                                                          .completionUnavailableReason!,
                                                    ),
                                                  ),
                                                ),
                                          )
                                        else
                                          Tooltip(
                                            message:
                                                '${completed ? 'Reopen' : 'Complete'} ${task['title']}',
                                            child: TaskCompletionCheckbox(
                                              repeating: recurrence != null,
                                              value: completed,
                                              // Disabling a native checkbox
                                              // releases its keyboard focus.
                                              // Keep it focusable while a save
                                              // is pending; _act's busy guard
                                              // rejects overlapping commands.
                                              onChanged: (_) {
                                                if (busy) return;
                                                if (completed) {
                                                  _reopen(task);
                                                } else {
                                                  _complete(task);
                                                }
                                              },
                                            ),
                                          ),
                                      ],
                                    ),
                                    selected: selectedTasks.contains(
                                      task['id'],
                                    ),
                                    selectedTileColor: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    title: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListRowBodyInkWell(
                                          key: ValueKey(
                                            'task-body-${task['id']}',
                                          ),
                                          canRequestFocus: false,
                                          onSecondaryTapUp: busy
                                              ? null
                                              : (details) => _showTaskMenu(
                                                  origin,
                                                  task,
                                                  position:
                                                      details.globalPosition,
                                                ),
                                          overlayColor: listRowInkOverlay(
                                            Theme.of(context).colorScheme,
                                          ),
                                          splashFactory:
                                              InkRipple.splashFactory,
                                          onTap: busy
                                              ? null
                                              : () => _selectTask(
                                                  task,
                                                  gesture:
                                                      pointerSelectionGesture(),
                                                ),
                                          onLongPress: busy
                                              ? null
                                              : () => _selectTask(
                                                  task,
                                                  gesture: SelectionGesture
                                                      .longPress,
                                                ),
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              minHeight: 48,
                                            ),
                                            child: Padding(
                                              padding: EdgeInsets.only(
                                                top: 6,
                                                bottom: showChecklist ? 0 : 6,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment: showChecklist
                                                    ? MainAxisAlignment.end
                                                    : MainAxisAlignment.center,
                                                children: [
                                                  _taskTitle(
                                                    task,
                                                    users,
                                                    group.date,
                                                    entry,
                                                  ),

                                                  if ((task['description']
                                                          as String)
                                                      .trim()
                                                      .isNotEmpty)
                                                    Text(
                                                      (task['description']
                                                              as String)
                                                          .replaceAll(
                                                            RegExp(r'\s+'),
                                                            ' ',
                                                          )
                                                          .trim(),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            color: Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (showChecklist)
                                          _checklistDisclosure(origin, task),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        KeyedSubtree(
                                          key: taskMenuKeys.putIfAbsent(
                                            id,
                                            GlobalKey.new,
                                          ),
                                          child: IconButton(
                                            key: ValueKey('task-menu-$id'),
                                            constraints:
                                                const BoxConstraints.tightFor(
                                                  width: 48,
                                                  height: 48,
                                                ),
                                            visualDensity:
                                                VisualDensity.standard,
                                            tooltip:
                                                'Actions for ${task['title']}',
                                            onPressed: busy
                                                ? null
                                                : () => _showTaskMenu(
                                                    origin,
                                                    task,
                                                  ),
                                            icon: const Icon(Icons.more_vert),
                                          ),
                                        ),
                                        if (movable(task, true) ||
                                            movable(task, false))
                                          Draggable<String>(
                                            data: task['id'],
                                            maxSimultaneousDrags:
                                                completed ||
                                                    busy ||
                                                    (selecting &&
                                                        !selectedTasks.contains(
                                                          task['id'],
                                                        ))
                                                ? 0
                                                : 1,
                                            dragAnchorStrategy:
                                                pointerDragAnchorStrategy,
                                            onDragStarted: () {
                                              dragReleased = false;
                                              setState(
                                                () => taskDrag = (
                                                  id: task['id'] as String,
                                                  store: store,
                                                  revision: viewRevision,
                                                  snapshot: store!.taskSnapshot,
                                                  completed:
                                                      task['completed'] == true,
                                                  everyone: all,
                                                  upcoming: showUpcoming,
                                                  user: user,
                                                  tags: Set.of(selectedTags),
                                                  selected:
                                                      selecting &&
                                                          selectedTasks
                                                              .contains(
                                                                task['id'],
                                                              )
                                                      ? Set.of(selectedTasks)
                                                      : {task['id'] as String},
                                                  query: searchQuery,
                                                ),
                                              );
                                            },
                                            onDragUpdate: (details) =>
                                                _updateDragScroll(
                                                  details.globalPosition,
                                                ),
                                            onDragEnd: (details) {
                                              if (dragReleased &&
                                                  taskDrag != null) {
                                                _dropAtPointer(
                                                  task['id'] as String,
                                                  details.offset,
                                                );
                                              }
                                              _stopDragScroll();
                                              setState(() => taskDrag = null);
                                            },
                                            feedback: Material(
                                              elevation: 4,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                child: SizedBox(
                                                  width: 220,
                                                  child: Text(
                                                    task['title'],
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            child: Tooltip(
                                              triggerMode:
                                                  TooltipTriggerMode.manual,
                                              message:
                                                  'Drag to reorder within this group, date and time',
                                              child: Semantics(
                                                customSemanticsActions: {
                                                  if (!selecting &&
                                                      movable(task, true))
                                                    const CustomSemanticsAction(
                                                      label: 'Move up',
                                                    ): () => _keyboardMove(
                                                      task,
                                                      true,
                                                    ),
                                                  if (!selecting &&
                                                      movable(task, false))
                                                    const CustomSemanticsAction(
                                                      label: 'Move down',
                                                    ): () => _keyboardMove(
                                                      task,
                                                      false,
                                                    ),
                                                },
                                                label:
                                                    'Drag ${task['title']} to reorder. Drag within the same group, date and time.',
                                                child: const SizedBox(
                                                  width: 48,
                                                  height: 48,
                                                  child: Icon(
                                                    Icons.drag_indicator,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          )
                                        else if (showChecklist)
                                          // Keep the menu above child Delete when this
                                          // task has no reorder neighbor.
                                          const SizedBox(width: 48, height: 48),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                            return Column(
                              key: ValueKey('task-block-$id'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                KeyedSubtree(
                                  key: ValueKey('task-drop-$id'),
                                  child: _TaskDragLifetime(
                                    active: taskDrag?.id == id,
                                    child: _reorderableTask(
                                      task,
                                      GestureDetector(
                                        onSecondaryTapUp: busy
                                            ? null
                                            : (details) => _showTaskMenu(
                                                origin,
                                                task,
                                                position:
                                                    details.globalPosition,
                                              ),
                                        child: tile,
                                      ),
                                    ),
                                  ),
                                ),
                                if (expandedChecklists.contains(id))
                                  _inlineChecklist(origin, task),
                              ],
                            );
                          },
                        ),
                        const ListRowDivider(),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
      ),
    );
    return Column(
      children: [
        _entryArea(),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              list,
              IgnorePointer(
                child: ExcludeSemantics(
                  child: ClipRect(
                    child: CustomPaint(
                      key: const ValueKey('task-insertion-boundary'),
                      painter: TaskDropIndicatorPainter(
                        boundary: _taskInsertionRect,
                        color: Theme.of(context).colorScheme.primary,
                        repaint: Listenable.merge([dragScrollTick, taskScroll]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskDragLifetime extends StatefulWidget {
  const _TaskDragLifetime({required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<_TaskDragLifetime> createState() => _TaskDragLifetimeState();
}

class _TaskDragLifetimeState extends State<_TaskDragLifetime>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.active;
  @override
  void didUpdateWidget(_TaskDragLifetime oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Owns an edit buffer independently of incoming folder updates. Only fields
/// changed from the opening snapshot are submitted, retaining concurrent edits.

class _FilterDialogRoute extends DialogRoute<void> {
  _FilterDialogRoute({
    required super.context,
    required super.builder,
    required this.dropdownOpen,
  });
  final bool Function() dropdownOpen;
  @override
  bool get barrierDismissible => !dropdownOpen();
}
