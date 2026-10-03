import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'application/undo_history.dart';
import 'domain/event.dart' show LogEvent;
import 'presentation/unavailable_completion.dart';
import 'presentation/task_completion_checkbox.dart';
import 'presentation/task_entry_area.dart';
import 'presentation/task_toolbar.dart';
import 'presentation/sticky_task_group.dart';
import 'domain/task_view.dart';
import 'domain/timed_view.dart';
import 'presentation/view_clock.dart';
import 'presentation/task_metadata.dart';
import 'presentation/tag_filter_picker.dart';
import 'presentation/task_editor.dart';
import 'presentation/failure_message.dart';
import 'platform/view_time_source.dart';
import 'platform/log_folder.dart';
import 'platform/folder_actions.dart';
import 'platform/foreground_importer.dart';
import 'storage/local_settings.dart';
import 'storage/task_store.dart';

void main() {
  debugPrint('TANDEMLOG_MAIN');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TandemlogApp());
}

class TandemlogApp extends StatefulWidget {
  const TandemlogApp({
    super.key,
    this.profilePath,
    this.folderActions,
    this.timeSourceFactory,
  });
  final String? profilePath;
  final FolderActions? folderActions;
  final ViewTimeSource Function(void Function())? timeSourceFactory;
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

  ThemeData _theme(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff267461),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xfff6f7f2)
          : colors.surface,
      cardTheme: CardThemeData(color: colors.surfaceContainerLow),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        contentTextStyle: TextStyle(color: colors.onSurface),
        actionTextColor: colors.primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: colors.surfaceContainerLowest,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Appearance>(
    valueListenable: appearance,
    builder: (_, value, _) => MaterialApp(
      title: 'Tandemlog',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
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
  });
  final String? profilePath;
  final ValueNotifier<Appearance> appearance;
  final FolderActions folderActions;
  final ViewTimeSource Function(void Function())? timeSourceFactory;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> with WidgetsBindingObserver {
  TaskStore? store;
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
  final search = TextEditingController();
  final searchFocus = FocusNode();
  bool searchOpen = false;
  String get searchQuery => search.text.trim();
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
  bool busy = true, all = false, showCompleted = false, showUpcoming = false;
  String? privateRoot;
  LocalSettings? settings;
  bool settingsLoaded = false;
  final firstName = TextEditingController();
  final firstNameFocus = FocusNode();
  String? pendingUserId;
  List<Map<String, dynamic>> rows = [];
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
    if (!mounted || !foreground) return;
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

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focusChanged);
    WidgetsBinding.instance.addObserver(this);
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
            final visibleOrder = visibleEntries
                .map((entry) => entry.task['id'])
                .toList();
            if (selectionAnchor != null &&
                !visibleOrder.contains(selectionAnchor)) {
              selectionAnchor = null;
            }
            if (editingTask == null && editingBulk == null) {
              selectedTasks.retainAll(visibleOrder);
            }
            viewRevision++;
          });
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

  Future<void> _start() async {
    try {
      privateRoot =
          widget.profilePath ??
          Platform.environment['TANDEMLOG_PROFILE'] ??
          (await getApplicationSupportDirectory()).path;
      await Directory(privateRoot!).create(recursive: true);
      settings = LocalSettings(privateRoot!);
      await settings!.load();
      settingsLoaded = true;
      if (!mounted) return;
      widget.appearance.value = settings!.appearance;
      user = settings!.user;
      if (settings!.folder != null) await _open(settings!.folder!);
    } catch (e) {
      error = failureMessage(e);
    }
    if (!mounted) return;
    setState(() => busy = false);
    _configureImporter();
    _reportStartupAfterFrame();
  }

  Future<void> _open(String location) async {
    if (!await _closeEditor()) return;
    _clearSelection();
    final folder = Platform.isAndroid
        ? AndroidLogFolder(location)
        : LocalLogFolder(location);
    final cacheKey = sha256.convert(utf8.encode(location)).toString();
    final opened = await TaskStore.open(
      folder,
      '$privateRoot/spaces/$cacheKey',
      onTiming: (phase, ms) => debugPrint('TANDEMLOG_PHASE $phase=$ms'),
    );
    if (!mounted) {
      await opened.close();
      return;
    }
    undoHistory.clear();
    store = opened;
    rows = store!.rows;
    debugPrint('TANDEMLOG_ROWS ${jsonEncode(store!.lastReadTimings)}');
    if (!rows.any((r) => r['kind'] == 'user' && r['id'] == user)) user = null;
  }

  Future<void> _saveSettings() async {
    final preferences = settings!;
    preferences.folder = store?.folder.location ?? preferences.folder;
    preferences.user = user;
    await preferences.save();
  }

  Future<void> _selectUser(String? selected) async {
    if (!await _closeEditor()) return;
    _clearSelection();
    final previous = settings!.user;
    settings!.folder = store!.folder.location;
    settings!.user = selected;
    try {
      await settings!.save();
    } catch (_) {
      settings!.user = previous;
      rethrow;
    }
    if (!mounted) return;
    rows = store!.rows;
    user = selected;
  }

  Future<void> _startDefault() => _act(() async {
    if (!settingsLoaded || settings!.folder != null) return;
    final location = await settings!.desktopDefaultFolder();
    await Directory(location).create(recursive: true);
    await _open(location);
    if (!mounted) return;
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
    final location = store?.folder.location ?? settings?.folder;
    bool canOpen = false;
    if (location != null) {
      try {
        canOpen = await widget.folderActions.canOpen(location);
      } catch (_) {
        /* unavailable */
      }
    }
    if (!mounted) return;
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
                  enabled: settingsLoaded,
                  onTap: settingsLoaded
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
                        onPressed: canOpen
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
                      onPressed: settingsLoaded
                          ? () => Navigator.pop(ctx, 'choose')
                          : null,
                      child: Text(
                        location == null
                            ? 'Choose an existing folder'
                            : 'Use a different folder',
                      ),
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
    if (!mounted || action == null) return;
    if (action == 'choose') {
      await _chooseFolder();
    } else if (action == 'open') {
      await _act(() => widget.folderActions.open(location!));
    } else {
      await _setAppearance(Appearance.values.byName(action));
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await syncing;
      await action();
      if (mounted) {
        setState(() {
          error = null;
          errorFromRefresh = false;
          rows = store?.rows ?? [];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = failureMessage(e);
          errorFromRefresh = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        _configureImporter();
        importer?.request();
      }
    }
  }

  bool get _textHasFocus {
    final focus = FocusManager.instance.primaryFocus?.context;
    return focus?.widget is EditableText ||
        focus?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  Future<T> _recordAction<T>(
    TaskStore origin,
    String verb,
    Future<T> Function(void Function(OperationReceipt)) action, {
    Object? group,
    bool notice = false,
  }) async {
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
        undoHistory.record(verb, prepared, group: group);
        undoHistory.reconcile(origin.confirmedOperations);
        final latest = undoHistory.latest;
        final confirmed = origin.confirmedOperations(prepared);
        final confirmedLatest =
            latest != null && latest.operations.any(confirmed.contains);
        setState(() {
          rows = origin.rows;
        });
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
                  '${failed ? 'Confirmed ' : ''}${past[verb] ?? verb} $n ${n == 1 ? 'task' : 'tasks'}.${successor ? ' Next occurrence kept.' : ''}',
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
    if (busy || closingEditor || undoHistory.latest == null) return;
    final origin = store!, requested = undoHistory.latest;
    final preserveEditor = requested?.verb == 'moving';
    if (!preserveEditor && !await _closeEditor()) return;
    if (!mounted || !identical(store, origin)) return;
    await _act(() async {
      await origin.refresh();
      if (!mounted || !identical(store, origin)) return;
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
      final beforeUndo = origin.taskSnapshot;
      final rebaseBulk =
          preserveEditor &&
          !bulkConflict &&
          editingBulk != null &&
          bulkSnapshot == beforeUndo;
      final result = await origin.undoOperations(entry.operations.toList());
      undoHistory.acknowledge(entry, result.undone);
      if (!mounted || !identical(store, origin)) return;
      setState(() {
        if (!preserveEditor) _clearSelection();
        if (rebaseBulk && _sameTaskContent(beforeUndo, origin.taskSnapshot)) {
          bulkSnapshot = origin.taskSnapshot;
        }
        rows = origin.rows;
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
    _invalidateView();
    if (!identical(watchedStore, store)) {
      importer?.dispose();
      watchedStore = store;
      final origin = store;
      importer = origin == null
          ? null
          : ForegroundImporter(
              events: origin.folder is LocalLogFolder
                  ? () => Directory(origin.folder.location).watch()
                  : null,
              reconcile: _refresh,
            );
    }
    if (foreground) {
      importer?.start();
    } else {
      importer?.stop();
    }
  }

  Future<void> _refresh() async {
    if (!mounted || !foreground || store == null || busy || syncing != null) {
      return;
    }
    final origin = store!;
    syncing = () async {
      try {
        final previousClockWarning = origin.clockWarning;
        final changed = await origin.refresh();
        undoHistory.reconcile(origin.confirmedOperations);
        final clockWarningChanged = previousClockWarning != origin.clockWarning;
        final reconcileCapture = captureFailure && pendingCapture.isNotEmpty;
        if (mounted && identical(store, origin) && reconcileCapture) {
          final unsaved = pendingCapture
              .where((entry) => !origin.hasEntity(entry.id))
              .toList();
          capture.text = unsaved.map((entry) => entry.title).join('\n');
          pendingCapture.clear();
          captureFailure = false;
          if (unsaved.isEmpty) error = null;
        }
        if (mounted &&
            identical(store, origin) &&
            (changed ||
                clockWarningChanged ||
                errorFromRefresh ||
                reconcileCapture)) {
          setState(() {
            rows = origin.rows;
            if (errorFromRefresh) error = null;
            errorFromRefresh = false;
          });
          _invalidateView();
        }
      } catch (e) {
        if (mounted && identical(store, origin)) {
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    if (state == AppLifecycleState.resumed) importer?.request();
  }

  Future<void> _chooseFolder() async {
    if (!await _closeEditor()) return;
    await _act(() async {
      final selected = await widget.folderActions.pick();
      if (selected == null || !mounted) return;
      if (selected == store?.folder.location) return;
      final previousStore = store;
      final previousUser = user;
      final previousRows = rows;
      final previousFolder = settings!.folder;
      try {
        await _open(selected);
        if (!mounted) return;
        await _saveSettings();
      } catch (_) {
        if (!identical(store, previousStore)) await store?.close();
        store = previousStore;
        user = previousUser;
        rows = previousRows;
        settings!.folder = previousFolder;
        settings!.user = previousUser;
        rethrow;
      }
      await previousStore?.close();
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      pendingCapture.clear();
      showCompleted = false;
      capture.clear();
      firstName.clear();
      pendingUserId = null;
      pendingUserName = null;
    });
  }

  Future<void> _createFirstUser() async {
    final name = firstName.text.trim();
    if (busy || name.isEmpty) return;
    await _act(() async {
      pendingUserId ??= const Uuid().v4();
      pendingUserName ??= name;
      await store!.refresh();
      if (!store!.hasEntity(pendingUserId!)) {
        await store!.command(pendingUserId!, 'user.created', {
          'name': pendingUserName,
        });
      }
      await _selectUser(pendingUserId);
      pendingUserId = null;
      pendingUserName = null;
      firstName.clear();
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

  Future<String?> _textDialog(String title, {required String label}) async {
    final input = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(ctx, input.text.trim());
              }
            },
            child: const Text('Create user'),
          ),
        ],
      ),
    );
    // Controllers referenced by a closing dialog are disposed after its transition.
    Future<void>.delayed(const Duration(seconds: 1), input.dispose);
    return result;
  }

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
    final titles = capture.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (titles.isEmpty) return;
    if (titles.any((s) => s.length > 500)) {
      setState(() => error = 'Keep each task title under 500 characters.');
      return;
    }
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
          '${result.committedIds.length} tasks confirmed saved; '
          '${pendingCapture.length} remain. ${failureMessage(result.error!)}',
        );
      }
    });
    captureFailure = pendingCapture.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && user != null) captureFocus.requestFocus();
    });
  }

  Future<bool> _closeEditor() async {
    if (editingTask == null && editingBulk == null) return true;
    if (closingEditor) return false;
    closingEditor = true;
    try {
      final okay =
          await ((editingTask != null
                  ? editorKey.currentState?.canClose()
                  : bulkEditorKey.currentState?.canClose()) ??
              Future.value(true));
      if (okay && mounted) {
        setState(() {
          editingTask = null;
          editingBulk = null;
          editorStore = null;
        });
      }
      return okay;
    } finally {
      closingEditor = false;
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

  void _openSelectionSession() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    editorStore = store;
    final tasks = rows
        .where(
          (row) => row['kind'] == 'task' && selectedTasks.contains(row['id']),
        )
        .toList();
    if (tasks.length != selectedTasks.length) return;
    if (tasks.length == 1) {
      editorKey = GlobalKey<TaskEditorState>();
      editingTask = Map<String, dynamic>.from(tasks.single);
      editingBulk = null;
    } else if (tasks.isNotEmpty) {
      bulkSnapshot = store!.taskSnapshot;
      bulkConflict = false;
      bulkEditorKey = GlobalKey<BulkTaskEditorState>();
      editingBulk = tasks
          .map((task) => Map<String, dynamic>.from(task))
          .toList();
      editingTask = null;
      bulkPending = tasks.map((task) => task['id'] as String).toList();
    }
  }

  Future<bool> _selectTask(
    Map<String, dynamic> task, {
    bool explicit = false,
    bool range = false,
    bool longPress = false,
  }) async {
    final id = task['id'] as String;
    final before = Set<String>.of(selectedTasks);
    final next = Set<String>.of(before);
    var nextIntent = selecting;
    var anchor = selectionAnchor;
    if (range) {
      final ordered = visibleEntries
          .map((entry) => entry.task['id'] as String)
          .toList();
      final from = ordered.indexOf(anchor ?? id), to = ordered.indexOf(id);
      next.clear();
      if (from >= 0 && to >= 0) {
        next.addAll(
          ordered.sublist(from < to ? from : to, (from > to ? from : to) + 1),
        );
      } else {
        next.add(id);
        anchor = id;
      }
      nextIntent = true;
    } else if (longPress && !selecting) {
      next
        ..clear()
        ..add(id);
      nextIntent = true;
      anchor = id;
    } else if (explicit || selecting) {
      if (!next.add(id)) next.remove(id);
      nextIntent = true;
      anchor = id;
    } else {
      next
        ..clear()
        ..add(id);
      nextIntent = false;
      anchor = id;
    }
    if (wideLayout && before.length >= 2 && next.length == 1) {
      nextIntent = false;
    }
    if (next.isEmpty) nextIntent = false;
    final visible = visibleEntries.map((entry) => entry.task['id']).toSet();
    if (!next.every(visible.contains)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Some selected tasks are no longer visible. Clear the selection and review the list.',
          ),
        ),
      );
      return false;
    }
    final origin = store;
    final plannedOrder = visibleEntries
        .map((entry) => entry.task['id'])
        .toList();
    if (!await _closeEditor() || !mounted) return false;
    if (!identical(origin, store) || !timeSource.ready) return false;
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
      if (next.isNotEmpty) _openSelectionSession();
    });
    return true;
  }

  Future<void> _editSelected() async {
    if (selectedTasks.isEmpty || !await _closeEditor() || !mounted) return;
    final visible = visibleEntries.map((entry) => entry.task['id']).toSet();
    if (!selectedTasks.every(visible.contains)) return;
    setState(() {
      mobileEditorOpen = true;
      _openSelectionSession();
    });
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
    if (range && !await _selectTask(target, range: true)) return;
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
        setState(() => rows = origin.rows);
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
        setState(() => rows = origin.rows);
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
  bool _targetUnchanged(TaskStore origin, Map<String, dynamic> frozen) {
    final current = origin.rows
        .where((row) => row['id'] == frozen['id'] && row['kind'] == 'task')
        .firstOrNull;
    return identical(store, origin) &&
        current != null &&
        _targetBaseline(current) == _targetBaseline(frozen);
  }

  Widget _editorSurface(
    Widget list,
    List<Map<String, dynamic>> users,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      if (editingTask == null && editingBulk == null) {
        wideLayout = constraints.maxWidth >= 900;
        return list;
      }
      final panel = constraints.maxWidth >= 900;
      if (wideLayout &&
          !panel &&
          (editorKey.currentState != null ||
              bulkEditorKey.currentState != null)) {
        mobileEditorOpen = true;
      }
      wideLayout = panel;
      if (!panel && selecting && !mobileEditorOpen) return list;
      final task = editingTask;
      final editor = task != null
          ? TaskEditor(
              key: editorKey,
              task: task,
              users: users,
              panel: panel,
              selectionCount: selectedTasks.isEmpty
                  ? null
                  : selectedTasks.length,
              onClearSelection: _clearTaskSelection,
              onClose: () {
                setState(() {
                  editingTask = null;
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
                    expectedTaskSnapshot: origin.taskSnapshot,
                    canCommit: () => _targetUnchanged(origin, task),
                    onPrepared: prepared,
                  ),
                  notice: true,
                );
                await origin.refresh();
                if (mounted) {
                  setState(() => rows = origin.rows);
                  _invalidateView();
                }
              },
              save: (fields, addedTags, removedTags) async {
                final origin = editorStore!;
                await syncing;
                if (!identical(store, origin)) {
                  throw StateError('The data folder changed. Reopen the task.');
                }
                await origin.refresh();
                if (!_targetUnchanged(origin, task)) {
                  throw StateError(
                    'This task changed. Your draft is kept; close and reopen it to review before saving.',
                  );
                }
                final tags = Set<String>.from(task['tags'] as List? ?? [])
                  ..addAll(addedTags)
                  ..removeAll(removedTags);
                if (fields.isNotEmpty ||
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
                      expectedTaskSnapshot: origin.taskSnapshot,
                      canCommit: () => _targetUnchanged(origin, task),
                      onPrepared: prepared,
                    ),
                  );
                }
                if (mounted) {
                  setState(() => rows = origin.rows);
                  _invalidateView();
                }
              },
            )
          : BulkTaskEditor(
              key: bulkEditorKey,
              tasks: editingBulk!,
              users: users,
              panel: panel,
              selectionCount: selectedTasks.isEmpty
                  ? null
                  : selectedTasks.length,
              onClearSelection: _clearTaskSelection,
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
                  setState(() => rows = origin.rows);
                  _invalidateView();
                }
                if (!result.succeeded) {
                  throw StateError(
                    '${ids.length - bulkPending.length} confirmed deleted after refresh; ${bulkPending.length} remain. ${failureMessage(result.error!)}',
                  );
                }
              },
            );
      if (panel) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: list),
            const VerticalDivider(width: 1),
            SizedBox(width: 420, child: editor),
          ],
        );
      }
      return Stack(
        children: [
          list,
          ModalBarrier(color: Colors.black54, dismissible: false),
          // The surrounding Scaffold already resized this body above the IME.
          // An embedded Dialog must not subtract the keyboard inset again.
          MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: Center(child: editor),
          ),
        ],
      );
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
            entries[index].effectiveDate != entries[neighbor].effectiveDate ||
            entries[index].task['completed'] !=
                entries[neighbor].task['completed']) {
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

  bool Function() _moveCommitGuard(String source, String target) {
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
        final current = projectTaskView(
          origin.rows,
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
            from.effectiveDate == expected.effectiveDate &&
            to.effectiveDate == expected.effectiveDate;
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
          return from != null &&
              from.task['completed'] == to.task['completed'] &&
              from.effectiveDate == to.effectiveDate;
        });
  }

  void _cancelDrag() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _dragIsCurrent()
              ? 'Reorder canceled. Drop beside a task with the same date and time.'
              : 'The task list changed. Try dragging again.',
        ),
      ),
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
      final global = rows
          .where(
            (row) =>
                row['kind'] == 'task' && !drag.selected.contains(row['id']),
          )
          .toList();
      final index = global.indexWhere((row) => row['id'] == target);
      if (index < 0) return;
      final before = !after
          ? target
          : index + 1 < global.length
          ? global[index + 1]['id'] as String
          : null;
      if (drag.selected.length == 1) {
        await _moveBeforeGuarded(
          source,
          before,
          drag.snapshot,
          _moveCommitGuard(source, target),
        );
      } else {
        final ids = drag.selected.toList();
        final contextGuard = _bulkGuard(ids);
        final expected = visibleEntries
            .where((entry) => entry.task['id'] == source)
            .first;
        bool canCommit() {
          if (!contextGuard()) return false;
          final view = projectTaskView(
            store!.rows,
            timeSource.readTime(),
            assignee: all ? null : user,
            includeUpcoming: showUpcoming,
            tags: Set.of(selectedTags),
            searchQuery: searchQuery,
          ).value;
          final entries = searching
              ? [...view.open, ...view.completed]
              : (showCompleted ? view.completed : view.open);
          return [...ids, target].every((id) {
            final entry = entries
                .where((entry) => entry.task['id'] == id)
                .firstOrNull;
            return entry != null &&
                entry.effectiveDate == expected.effectiveDate &&
                entry.task['completed'] == expected.task['completed'];
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
        rows = store!.rows;
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
    dragPointer = null;
  }

  void _updateDragScroll(Offset pointer) {
    dragPointer = pointer;
    dragScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_dragIsCurrent() || !taskScroll.hasClients) {
        _stopDragScroll();
        return;
      }
      final box = taskViewport.currentContext?.findRenderObject() as RenderBox?;
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
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null &&
          box.attached &&
          box.hasSize &&
          (Offset.zero & box.size).contains(box.globalToLocal(pointer))) {
        return true;
      }
    }
    return false;
  }

  void _dropAtPointer(String source, Offset pointer) {
    final viewport =
        taskViewport.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null ||
        _pointerOverGroupHeading(pointer) ||
        !(Offset.zero & viewport.size).contains(
          viewport.globalToLocal(pointer),
        )) {
      _cancelDrag();
      return;
    }
    for (final entry in dropKeys.entries) {
      if (entry.key == source) continue;
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final local = box.globalToLocal(pointer);
      if ((Offset.zero & box.size).contains(local)) {
        _dropTask(source, entry.key, local.dy >= box.size.height / 2);
        return;
      }
    }
    _cancelDrag();
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
            final box = context.findRenderObject() as RenderBox;
            final next =
                box.globalToLocal(details.offset).dy >= box.size.height / 2;
            if (next != after) updateHover(() => after = next);
          },
          // Draggable resolves the release geometry below: cached targets can
          // scroll away while the pointer remains stationary at an edge.
          onAcceptWithDetails: (_) {},
          builder: (context, candidates, rejected) {
            final box = context.findRenderObject() as RenderBox?;
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
                    ? 'Cannot reorder here: different date or time, or the list changed.'
                    : null,
                child: DecoratedBox(
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
                        : !(dragPointer != null
                              ? hovering
                              : candidates.isNotEmpty)
                        ? null
                        : Border(
                            top: after
                                ? BorderSide.none
                                : BorderSide(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 2,
                                  ),
                            bottom: after
                                ? BorderSide(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 2,
                                  )
                                : BorderSide.none,
                          ),
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
      if (scheduleMetadata(
            schedule,
            groupDate: groupDate,
            localZoneId: taskViewZoneId!,
            viewInstant: taskViewInstant!,
            unavailableStart: !entry.available && task['completed'] != true
                ? entry.availabilityStart
                : null,
          )
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 620 * scale) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, details],
          );
        }
        final painter = TextPainter(
          text: TextSpan(text: metadata, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = painter.width.clamp(0.0, constraints.maxWidth * .42);
        painter.dispose();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: title),
            const SizedBox(width: 12),
            SizedBox(width: width, child: details),
          ],
        );
      },
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
    final time = timeSource.readTime();
    await _act(
      () => _recordAction(
        origin,
        'completing',
        (prepared) => origin.complete(
          task['id'],
          completionInstant: time.instant,
          localZoneId: time.localZoneId,
          onPrepared: prepared,
        ),
        notice: true,
      ),
    );
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    _stopDragScroll();
    taskScroll.dispose();
    dragScrollTick.dispose();
    importer?.dispose();
    viewClock.dispose();
    timeSource.dispose();
    WidgetsBinding.instance.removeObserver(this);
    for (final node in rowFocus.values) {
      node.dispose();
    }
    search.dispose();
    searchFocus.dispose();
    capture.dispose();
    captureFocus.dispose();
    firstName.dispose();
    firstNameFocus.dispose();
    unawaited(store?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = rows.where((r) => r['kind'] == 'user').toList();
    return PopScope(
      canPop:
          editingTask == null && editingBulk == null && selectedTasks.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_clearTaskSelection());
      },
      child: CallbackShortcuts(
        bindings: {
          if (!_textHasFocus) ...{
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                _undoShortcut,
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                _undoShortcut,
          },
          const SingleActivator(LogicalKeyboardKey.escape): _clearTaskSelection,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openSearch,
        },
        child: FocusScope(
          child: Scaffold(
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1450),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                        child: TaskToolbar(
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
                          undo: IconButton(
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
                          search: store != null && user != null
                              ? _openSearch
                              : null,
                          searchField: searchOpen
                              ? TextField(
                                  key: const ValueKey('task-search'),
                                  controller: search,
                                  focusNode: searchFocus,
                                  maxLines: 1,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  textAlignVertical: TextAlignVertical.center,
                                  decoration: InputDecoration(
                                    hintText: 'Search all tasks',
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    border: InputBorder.none,
                                    suffixIcon: IconButton(
                                      tooltip: 'Clear search',
                                      onPressed: () async {
                                        if (!await _closeEditor()) return;
                                        search.clear();
                                        _clearSelection();
                                        setState(() => searchOpen = false);
                                        _invalidateView();
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                                  ),
                                  onChanged: _changeSearch,
                                )
                              : null,
                        ),
                      ),
                      SizedBox(
                        height: 2,
                        child: busy
                            ? const LinearProgressIndicator(minHeight: 2)
                            : null,
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
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
                                  Expanded(child: Text(error!)),
                                  if (errorFromRefresh && store != null)
                                    TextButton(
                                      onPressed: busy ? null : _refresh,
                                      child: const Text('Retry'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (store?.clockWarning != null)
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
                        child: store == null
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
                            ? const Center(child: CircularProgressIndicator())
                            : _editorSurface(
                                _tasks(
                                  searching
                                      ? [
                                          ...taskView!.openGroups,
                                          ...taskView!.completedGroups,
                                        ]
                                      : showCompleted
                                      ? taskView!.completedGroups
                                      : taskView!.openGroups,
                                  users,
                                ),
                                users,
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
                onPressed: busy || !settingsLoaded
                    ? null
                    : settings!.folder != null
                    ? () => _act(() => _open(settings!.folder!))
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
                  onPressed: busy || !settingsLoaded ? null : _chooseFolder,
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
      ? Center(
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
                      helperText: pendingUserName == null
                          ? null
                          : 'Continue to finish saving this name.',
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _createFirstUser(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy || firstName.text.trim().isEmpty
                        ? null
                        : _createFirstUser,
                    child: const Text('Continue'),
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
                      : () => _act(() async {
                          user = u['id'];
                          await _saveSettings();
                        }),
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

  Future<void> _openSearch() async {
    if (!await _closeEditor()) return;
    if (store == null || user == null) return;
    setState(() => searchOpen = true);
    searchFocus.requestFocus();
  }

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

  Future<void> _showFilters() async {
    if (!await _closeEditor()) return;
    if (!mounted) return;
    final tags = rows
        .where((row) => row['kind'] == 'task')
        .expand((row) => (row['tags'] as List? ?? []).cast<String>())
        .toSet();
    if (selectedTags.isNotEmpty) tags.addAll(selectedTags);
    final sortedTags = tags.toList()
      ..sort((a, b) {
        final order = a.toLowerCase().compareTo(b.toLowerCase());
        return order == 0 ? a.compareTo(b) : order;
      });
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
      onSelected: (value) {
        if (value == 'settings') {
          _showSettings();
        } else {
          _act(() => _selectUser(value == 'new' ? null : value));
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
    final icon = Badge(
      isLabelVisible: !searching && _filtersActive,
      child: const Icon(Icons.filter_list, size: 20),
    );
    return compact
        ? IconButton(
            key: const ValueKey('task-filter'),
            tooltip: tooltip,
            onPressed: searching ? null : _showFilters,
            icon: icon,
          )
        : Tooltip(
            message: tooltip,
            child: OutlinedButton.icon(
              key: const ValueKey('task-filter'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: searching ? null : _showFilters,
              icon: icon,
              label: const Text('Filter'),
            ),
          );
  }

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
      builder: (context, constraints) => TextField(
        controller: capture,
        focusNode: captureFocus,
        readOnly: pendingCapture.isNotEmpty,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        minLines: 1,
        maxLines: 4,
        enabled: !busy,
        decoration: InputDecoration(
          labelText: 'What needs doing?',
          hintText: 'One task per line',
          helperText: captureFailure && pendingCapture.isNotEmpty
              ? 'Retry to check these tasks before editing.'
              : widget.folderActions.requiresPicker
              ? null
              : 'Enter to add · Shift+Enter for another task',
          suffixIcon:
              constraints.maxWidth <
                  480 * (MediaQuery.textScalerOf(context).scale(14) / 14)
              ? IconButton(
                  key: const ValueKey('capture-add'),
                  tooltip: 'Add tasks',
                  onPressed: busy ? null : _submitCaptureButton,
                  icon: const Icon(Icons.add),
                )
              : Tooltip(
                  message: 'Add tasks',
                  child: TextButton.icon(
                    key: const ValueKey('capture-add'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(72, 48),
                      visualDensity: VisualDensity.standard,
                    ),
                    onPressed: busy ? null : _submitCaptureButton,
                    icon: const Icon(Icons.add),
                    label: Semantics(
                      label: 'Add tasks',
                      child: const ExcludeSemantics(child: Text('Add')),
                    ),
                  ),
                ),
        ),
        onSubmitted: (_) => _capture(),
      ),
    ),
  );

  Widget _entryArea() => TaskEntryArea(
    key: const ValueKey('task-entry-area'),
    selecting: selecting && !wideLayout && !mobileEditorOpen,
    captureVisible: !showCompleted || searching,
    selectionCount: selectedTasks.length,
    maximumSelectionCount: visibleEntries.length,
    onClear: busy ? null : _clearTaskSelection,
    onEdit: busy ? null : _editSelected,
    capture: _captureField(),
  );

  Widget _tasks(List<TaskViewGroup> groups, List<Map<String, dynamic>> users) {
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
          entries[index].effectiveDate == entries[neighbor].effectiveDate &&
          entries[index].task['completed'] ==
              entries[neighbor].task['completed'];
    }

    String groupTitle(TaskViewGroup group) {
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
        '${group.entries.firstOrNull?.task['completed'] == true}-${group.date}';
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
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        padding: const EdgeInsets.only(top: 16),
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
                  ),
                  SliverList.list(
                    children: [
                      for (final entry in group.entries) ...[
                        Builder(
                          key: ValueKey('task-row-${entry.task['id']}'),
                          builder: (context) {
                            final task = entry.task;
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
                                  explicit: true,
                                  longPress: true,
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
                                  if (!rowFocus[task['id']]!.hasPrimaryFocus ||
                                      event is! KeyDownEvent) {
                                    return KeyEventResult.ignored;
                                  }
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.space) {
                                    _selectTask(
                                      task,
                                      explicit: true,
                                      longPress: true,
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
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color:
                                          rowFocus[task['id']]!.hasPrimaryFocus
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.outline
                                          : Colors.transparent,
                                    ),
                                  ),
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
                                    title: GestureDetector(
                                      key: ValueKey('task-body-${task['id']}'),
                                      behavior: HitTestBehavior.opaque,
                                      onTap: busy
                                          ? null
                                          : () => _selectTask(
                                              task,
                                              explicit:
                                                  HardwareKeyboard
                                                      .instance
                                                      .isControlPressed ||
                                                  HardwareKeyboard
                                                      .instance
                                                      .isMetaPressed,
                                              range: HardwareKeyboard
                                                  .instance
                                                  .isShiftPressed,
                                            ),
                                      onLongPress: busy
                                          ? null
                                          : () => _selectTask(
                                              task,
                                              explicit: true,
                                              longPress: true,
                                            ),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minHeight: 48,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
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
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (movable(task, true) ||
                                            movable(task, false))
                                          Draggable<String>(
                                            data: task['id'],
                                            maxSimultaneousDrags:
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
                                                  'Drag to reorder within this date and time',
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
                                                    'Drag ${task['title']} to reorder. Drag within the same date and time.',
                                                child: const SizedBox(
                                                  width: 48,
                                                  height: 48,
                                                  child: Icon(
                                                    Icons.drag_indicator,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                            return KeyedSubtree(
                              key: ValueKey('task-drop-${task['id']}'),
                              child: _TaskDragLifetime(
                                active: taskDrag?.id == task['id'],
                                child: _reorderableTask(task, tile),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
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
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          _entryArea(),
          Expanded(child: list),
        ],
      ),
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
