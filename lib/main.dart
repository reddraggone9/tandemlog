import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'domain/schedule.dart';
import 'domain/task_view.dart';
import 'domain/timed_view.dart';
import 'presentation/view_clock.dart';
import 'platform/view_time_source.dart';
import 'domain/wall_time.dart';
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
  String? user, error;
  bool busy = true, all = false, showCompleted = false;
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
  String? viewError;

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
          return projectTaskView(rows, time, assignee: all ? null : user);
        } catch (failure) {
          viewError = 'Cannot update the task view: $failure';
          return TimedView(taskView ?? TaskView([], []));
        }
      },
      onView: (view) {
        if (mounted) setState(() => taskView = view.value);
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
      error = '$e';
    }
    if (!mounted) return;
    setState(() => busy = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
        'TANDEMLOG_READY_MS=${startup.elapsedMilliseconds} FILES_READ=${store?.readFiles ?? 0}',
      );
    });
    _configureImporter();
  }

  Future<void> _open(String location) async {
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
    final location = '$privateRoot/data';
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
          error = '$e';
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
            error = '$e';
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
      timeSource.stop();
      viewClock.stop();
    }
    _configureImporter();
    if (state == AppLifecycleState.resumed) importer?.request();
  }

  Future<void> _chooseFolder() async {
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
      while (pendingCapture.isNotEmpty) {
        final entry = pendingCapture.first;
        await store!.refresh();
        // A prior append may have committed even when its cache update failed.
        // Reuse this capture's entity identity instead of creating a duplicate.
        if (!store!.hasEntity(entry.id)) {
          await store!.command(entry.id, 'task.created', {
            'title': entry.title,
            'description': '',
            'assignee': user,
          });
        }
        pendingCapture.removeAt(0);
        capture.text = pendingCapture.map((entry) => entry.title).join('\n');
      }
    });
    captureFailure = pendingCapture.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && user != null) captureFocus.requestFocus();
    });
  }

  Future<void> _edit(Map<String, dynamic> task) async {
    final origin = store!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TaskEditor(
        task: task,
        save: (fields, addedTags, removedTags) async {
          await syncing;
          if (!identical(store, origin)) {
            throw StateError('The data folder changed. Reopen the task.');
          }
          final tags = Set<String>.from(task['tags'] as List? ?? [])
            ..addAll(addedTags)
            ..removeAll(removedTags);
          if (fields.isEmpty && addedTags.isEmpty && removedTags.isEmpty) {
            return;
          }
          await origin.edit(
            task['id'],
            fields,
            tags: tags.toList(),
            observedTagRefs: Map<String, String>.from(
              task['tagRefs'] as Map? ?? {},
            ),
          );
          if (mounted) {
            setState(() => rows = origin.rows);
            _invalidateView();
          }
        },
      ),
    );
  }

  Future<void> _moveTask(Map<String, dynamic> task, bool up) => _act(() async {
    final entries =
        (showCompleted ? taskView?.completed : taskView?.open) ?? [];
    final visible = entries.map((entry) => entry.task).toList();
    final index = visible.indexWhere((row) => row['id'] == task['id']);
    final neighbor = index + (up ? -1 : 1);
    if (index < 0 || neighbor < 0 || neighbor >= visible.length) return;
    if (entries[index].effectiveDate != entries[neighbor].effectiveDate) return;
    final global = rows.where((row) => row['kind'] == 'task').toList();
    final globalNeighbor = global.indexWhere(
      (row) => row['id'] == visible[neighbor]['id'],
    );
    final before = up
        ? visible[neighbor]['id']
        : globalNeighbor + 1 < global.length
        ? global[globalNeighbor + 1]['id']
        : null;
    await store!.moveBefore(task['id'], before);
  });

  String _taskPreview(
    Map<String, dynamic> task,
    List<Map<String, dynamic>> users,
  ) {
    final schedule = task['schedule'] as Map<String, dynamic>? ?? {};
    return [
      if (all)
        users
                .where((u) => u['id'] == task['assignee'])
                .map((u) => u['name'])
                .firstOrNull ??
            'Unknown user',
      if (schedule['dueDate'] != null)
        'Due ${[schedule['dueDate'], schedule['dueTime'], if (schedule['dueTime'] != null) schedule['timeZone']].whereType<String>().join(' ')}',
      if (schedule['scheduledDate'] != null)
        'Scheduled ${[schedule['scheduledDate'], schedule['scheduledTime'], if (schedule['scheduledTime'] != null) schedule['timeZone']].whereType<String>().join(' ')}',
      if (schedule['startDate'] != null || schedule['startTime'] != null)
        'Start ${[schedule['startDate'], schedule['startTime'], if (schedule['startTime'] != null) schedule['timeZone']].whereType<String>().join(' ')}',
      if (schedule['recurrence'] != null) '↻ ${schedule['recurrence']}',
      for (final tag in task['tags'] as List? ?? []) '#$tag',
      if ((task['description'] as String).trim().isNotEmpty)
        (task['description'] as String).replaceAll(RegExp(r'\s+'), ' ').trim(),
    ].join(' · ');
  }

  Future<void> _reopen(Map<String, dynamic> task) async {
    final origin = store!;
    final observed = origin.activeCompletionIds(task['id']);
    await _act(() async {
      await origin.reopen(task['id'], observed);
      if (mounted && identical(store, origin)) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (origin.hasEntity(const Uuid().v5(task['id'], 'successor'))) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Task reopened; next occurrence kept.'),
            ),
          );
        }
      }
    });
  }

  Future<void> _complete(Map<String, dynamic> task) async {
    await _act(() async {
      final origin = store!;
      final event = await origin.complete(
        task['id'],
        completionInstant: DateTime.now(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Completed “${task['title']}”'),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (!identical(store, origin)) return;
              _act(() async {
                if (!identical(store, origin)) return;
                await origin.command(task['id'], 'task.completionUndone', {
                  'completion': event.id,
                });
              });
            },
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    importer?.dispose();
    viewClock.dispose();
    timeSource.dispose();
    WidgetsBinding.instance.removeObserver(this);
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 24,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Tandemlog',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: busy ? null : _showSettings,
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
                ),
                if (busy) const LinearProgressIndicator(minHeight: 2),
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
                        color: Theme.of(context).colorScheme.tertiaryContainer,
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
                      : _tasks(
                          showCompleted
                              ? taskView!.completedGroups
                              : taskView!.openGroups,
                          users,
                        ),
                ),
              ],
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
  Widget _taskHeader(List<Map<String, dynamic>> users) {
    final openCount = taskView?.open.length ?? 0;
    final completedCount = taskView?.completed.length ?? 0;
    Widget heading(bool completed, int count) => Visibility(
      visible: showCompleted == completed,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: all ? 'All tasks' : 'Your tasks',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: ' · $count ${completed ? 'completed' : 'open'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
    // Both labels participate in layout; only the selected one is visible or
    // exposed to accessibility. Tab changes cannot move the controls below.
    final title = Stack(
      children: [heading(false, openCount), heading(true, completedCount)],
    );
    final controls = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<String>(
          tooltip: 'Switch user',
          onSelected: (v) => _act(() async {
            await _selectUser(v == 'new' ? null : v);
          }),
          itemBuilder: (_) => [
            for (final u in users)
              PopupMenuItem(value: u['id'], child: Text(u['name'])),
            const PopupMenuItem(value: 'new', child: Text('Manage users')),
          ],
          child: Chip(
            avatarBoxConstraints: const BoxConstraints.tightFor(
              width: 18,
              height: 18,
            ),
            avatar: const Icon(Icons.person_outline, size: 18),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Builder(
                builder: (context) => DefaultTextStyle(
                  // Chip defaults force one line. Keep the full name readable.
                  style: DefaultTextStyle.of(context).style,
                  child: Text(users.firstWhere((u) => u['id'] == user)['name']),
                ),
              ),
            ),
          ),
        ),
        FilterChip(
          label: const Text('Everyone'),
          selected: all,
          onSelected: (value) {
            setState(() => all = value);
            _invalidateView();
          },
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth >= 720 * labelScale) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              Flexible(child: controls),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 8), controls],
        );
      },
    );
  }

  Widget _tasks(List<TaskViewGroup> groups, List<Map<String, dynamic>> users) {
    final entries = groups.expand((group) => group.entries).toList();
    final tasks = entries.map((entry) => entry.task).toList();
    final hasDeferredTasks =
        !showCompleted &&
        rows.any(
          (row) =>
              row['kind'] == 'task' &&
              row['completed'] != true &&
              (all || row['assignee'] == user),
        );
    bool movable(Map<String, dynamic> task, bool up) {
      final index = entries.indexWhere(
        (entry) => entry.task['id'] == task['id'],
      );
      final neighbor = index + (up ? -1 : 1);
      return index >= 0 &&
          neighbor >= 0 &&
          neighbor < entries.length &&
          entries[index].effectiveDate == entries[neighbor].effectiveDate;
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

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _taskHeader(users),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const labels = ['Open', 'Completed'];
            const horizontalPadding = 12.0;
            final labelStyle = Theme.of(context).textTheme.labelLarge;
            var longestLabel = 0.0;
            for (final label in labels) {
              final painter = TextPainter(
                text: TextSpan(text: label, style: labelStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              if (painter.width > longestLabel) longestLabel = painter.width;
              painter.dispose();
            }
            // Select the layout from measured text, never selection state. The
            // checkmark would otherwise steal width only from the selected label.
            final horizontalFits =
                constraints.maxWidth >=
                2 * (longestLabel.ceilToDouble() + 2 * horizontalPadding);
            return SegmentedButton<bool>(
              direction: horizontalFits ? Axis.horizontal : Axis.vertical,
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 8,
                ),
              ),
              segments: const [
                ButtonSegment(value: false, label: Text('Open')),
                ButtonSegment(value: true, label: Text('Completed')),
              ],
              selected: {showCompleted},
              onSelectionChanged: (values) =>
                  setState(() => showCompleted = values.first),
            );
          },
        ),
        const SizedBox(height: 16),
        if (!showCompleted)
          Focus(
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
                        selection: TextSelection.collapsed(
                          offset: selection.start + 1,
                        ),
                      ),
                      SelectionChangedCause.keyboard,
                    );
                  }
                } else {
                  unawaited(_capture());
                }
                return KeyEventResult.handled;
              }
              if (event is KeyRepeatEvent) return KeyEventResult.handled;
              return KeyEventResult.ignored;
            },
            child: TextField(
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
                suffixIcon: IconButton(
                  tooltip: 'Add tasks',
                  onPressed: busy ? null : _capture,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ),
              onSubmitted: (_) => _capture(),
            ),
          ),
        const SizedBox(height: 12),
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
                  showCompleted
                      ? 'No completed tasks'
                      : hasDeferredTasks
                      ? 'Nothing available yet'
                      : 'No open tasks',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text(
                  showCompleted
                      ? 'Completed tasks will appear here.'
                      : hasDeferredTasks
                      ? 'Tasks with a future start will appear when they become available.'
                      : 'Add a task above.',
                ),
              ],
            ),
          ),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Semantics(
              header: true,
              child: Text(
                groupTitle(group),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          for (final entry in group.entries) ...[
            Builder(
              builder: (context) {
                final task = entry.task;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  minVerticalPadding: 6,
                  horizontalTitleGap: 8,
                  leading: Tooltip(
                    message:
                        '${showCompleted ? 'Reopen' : 'Complete'} ${task['title']}',
                    child: Checkbox(
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      value: showCompleted,
                      onChanged: busy
                          ? null
                          : (_) =>
                                showCompleted ? _reopen(task) : _complete(task),
                    ),
                  ),
                  title: Text(
                    task['title'],
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: _taskPreview(task, users).isEmpty
                      ? null
                      : Text(
                          _taskPreview(task, users),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Task actions',
                    enabled: !busy,
                    onSelected: (action) {
                      if (action == 'edit') {
                        _edit(task);
                      } else {
                        _moveTask(task, action == 'up');
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit task'),
                      ),
                      PopupMenuItem(
                        value: 'up',
                        enabled: movable(task, true),
                        child: const Text('Move up'),
                      ),
                      PopupMenuItem(
                        value: 'down',
                        enabled: movable(task, false),
                        child: const Text('Move down'),
                      ),
                    ],
                  ),
                  onTap: busy ? null : () => _edit(task),
                );
              },
            ),
            const Divider(height: 1),
          ],
        ],
      ],
    );
  }
}

/// Owns an edit buffer independently of incoming folder updates. Only fields
/// changed from the opening snapshot are submitted, retaining concurrent edits.
class _TaskEditor extends StatefulWidget {
  const _TaskEditor({required this.task, required this.save});
  final Map<String, dynamic> task;
  final Future<void> Function(
    Map<String, dynamic> fields,
    List<String> addedTags,
    List<String> removedTags,
  )
  save;

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, notes, tags;
  late final Map<String, TextEditingController> schedule;
  late final Map<String, dynamic> originalSchedule;
  late final Set<String> originalTags;
  bool saving = false;
  late String zoneMode;
  String? failure;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.task['title']);
    notes = TextEditingController(text: widget.task['description']);
    originalTags = Set<String>.from(widget.task['tags'] as List? ?? []);
    tags = TextEditingController(text: originalTags.join(' '));
    originalSchedule = Map<String, dynamic>.from(
      widget.task['schedule'] as Map? ?? {},
    );
    final originalZone = originalSchedule['timeZone'];
    zoneMode = originalZone == null
        ? 'local'
        : originalZone == 'UTC'
        ? 'UTC'
        : 'named';
    schedule = {
      for (final key in [
        'startDate',
        'scheduledDate',
        'dueDate',
        'startTime',
        'scheduledTime',
        'dueTime',
        'timeZone',
        'recurrence',
        'dueMinDays',
        'dueMaxDays',
      ])
        key: TextEditingController(
          text: originalSchedule[key]?.toString() ?? '',
        ),
    };
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    tags.dispose();
    for (final controller in schedule.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      failure = null;
    });
    try {
      final parsed = TaskSchedule.fromJson({
        for (final entry in schedule.entries)
          entry.key: entry.value.text.trim().isEmpty
              ? null
              : {'dueMinDays', 'dueMaxDays'}.contains(entry.key)
              ? int.tryParse(entry.value.text.trim()) ??
                    (throw const FormatException(
                      'Sort-date bounds must be whole numbers of days.',
                    ))
              : entry.value.text.trim(),
      }).toJson();
      if (parsed['timeZone'] != null) {
        try {
          timeZoneLocation(parsed['timeZone'] as String);
        } catch (_) {
          throw const FormatException(
            'Choose a valid time zone, such as America/Chicago.',
          );
        }
      }
      final desiredTags = tags.text
          .split(RegExp(r'\s+'))
          .where((tag) => tag.isNotEmpty)
          .map((tag) => tag.startsWith('#') ? tag.substring(1) : tag)
          .toSet();
      if (desiredTags.contains('')) {
        throw const FormatException('Enter a name after #, or remove it.');
      }
      final fields = <String, dynamic>{
        if (title.text.trim() != widget.task['title'])
          'title': title.text.trim(),
        if (notes.text != widget.task['description']) 'description': notes.text,
        if (parsed.entries.any((e) => originalSchedule[e.key] != e.value))
          'schedule': parsed,
      };
      await widget.save(
        fields,
        desiredTags.difference(originalTags).toList(),
        originalTags.difference(desiredTags).toList(),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          failure = error is FormatException ? error.message : '$error';
          saving = false;
        });
      }
    }
  }

  String? get zonedPreview {
    final zone = schedule['timeZone']!.text.trim();
    if (zone.isEmpty) return null;
    final previews = <String>[];
    for (final kind in ['start', 'scheduled', 'due']) {
      try {
        final resolved = resolveZonedWallTime(
          schedule['${kind}Date']!.text.trim(),
          schedule['${kind}Time']!.text.trim(),
          zone,
        );
        final local = resolved.instant.toLocal();
        final note = resolved.gapShift > Duration.zero
            ? ' (clock change: shifted forward ${resolved.gapShift.inMinutes} minutes)'
            : resolved.ambiguous
            ? ' (earlier occurrence of repeated time)'
            : '';
        final label = '${kind[0].toUpperCase()}${kind.substring(1)}';
        previews.add(
          '$label: ${formatCivilDate(local)} '
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}$note',
        );
      } catch (_) {
        // The save validator explains incomplete or invalid fields.
      }
    }
    return previews.isEmpty ? null : 'On this device:\n${previews.join('\n')}';
  }

  Widget timeField(String kind, String label) => TextFormField(
    controller: schedule['${kind}Time'],
    onChanged: (_) => setState(() {}),
    enabled: !saving,
    decoration: InputDecoration(
      labelText: '$label time',
      hintText: 'HH:mm',
      helperText:
          'Optional; uses the ${kind == 'scheduled' ? 'scheduled' : kind} date.',
      helperMaxLines: 3,
    ),
  );

  Widget dateField(String key, String label) => TextFormField(
    controller: schedule[key],
    onChanged: (_) => setState(() {}),
    enabled: !saving,
    decoration: InputDecoration(
      labelText: label,
      hintText: 'YYYY-MM-DD',
      suffixIcon: IconButton(
        tooltip: 'Choose $label',
        onPressed: saving
            ? null
            : () async {
                final parsedDate = DateTime.tryParse(schedule[key]!.text);
                final current =
                    parsedDate != null &&
                        parsedDate.year >= 1900 &&
                        parsedDate.year <= 9999
                    ? parsedDate
                    : null;
                final chosen = await showDatePicker(
                  context: context,
                  initialDate: current ?? DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime(9999),
                );
                if (chosen != null && mounted) {
                  schedule[key]!.text =
                      '${chosen.year.toString().padLeft(4, '0')}-'
                      '${chosen.month.toString().padLeft(2, '0')}-'
                      '${chosen.day.toString().padLeft(2, '0')}';
                  setState(() {});
                }
              },
        icon: const Icon(Icons.calendar_today_outlined),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Edit task'),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  failure!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: title,
                  autofocus: true,
                  enabled: !saving,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 4,
                  validator: (value) =>
                      value!.trim().isEmpty ? 'Enter a task title.' : null,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notes,
                  enabled: !saving,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 10000,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: tags,
                  enabled: !saving,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    helperText: 'Separate tags with spaces.',
                  ),
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 8),
                  title: const Text('Dates and repeat'),
                  initiallyExpanded: originalSchedule.values.any(
                    (v) => v != null,
                  ),
                  children: [
                    dateField('startDate', 'Start date'),
                    const SizedBox(height: 12),
                    timeField('start', 'Start'),
                    const SizedBox(height: 12),
                    dateField('scheduledDate', 'Scheduled date'),
                    const SizedBox(height: 12),
                    timeField('scheduled', 'Scheduled'),
                    const SizedBox(height: 12),
                    dateField('dueDate', 'Due date'),
                    const SizedBox(height: 12),
                    timeField('due', 'Due'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: zoneMode,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Time zone',
                        helperText: zoneMode == 'local'
                            ? 'All three dates follow this device’s time zone.'
                            : 'Applies to all three dates.',
                        helperMaxLines: 3,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'local', child: Text('Local')),
                        DropdownMenuItem(value: 'UTC', child: Text('UTC')),
                        DropdownMenuItem(
                          value: 'named',
                          child: Text('Named zone'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setState(() {
                              zoneMode = value!;
                              schedule['timeZone']!.text = value == 'UTC'
                                  ? 'UTC'
                                  : '';
                            }),
                    ),
                    if (zoneMode == 'named') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: schedule['timeZone'],
                        onChanged: (_) => setState(() {}),
                        enabled: !saving,
                        validator: (value) => value!.trim().isEmpty
                            ? 'Enter a time zone or choose Local.'
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Named time zone',
                          hintText: 'America/Chicago',
                        ),
                      ),
                    ],
                    if (zonedPreview != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        zonedPreview!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: schedule['recurrence'],
                      enabled: !saving,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        suffixIcon: PopupMenuButton<String>(
                          tooltip: 'Repeat examples',
                          enabled: !saving,
                          icon: const Icon(Icons.expand_more),
                          onSelected: (rule) =>
                              schedule['recurrence']!.text = rule,
                          itemBuilder: (_) => [
                            for (final rule in observedRecurrences)
                              PopupMenuItem(value: rule, child: Text(rule)),
                          ],
                        ),
                        labelText: 'Repeat',
                        hintText: 'every week when done',
                        helperText:
                            'Add “when done” to repeat from completion.\nLeave blank for no repeat.',
                        helperMaxLines: 8,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Sort-date bounds'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Optional days from today. These change where a task is listed, not its deadline.',
                    ),
                    const SizedBox(height: 12),
                    for (final bound in [
                      ('dueMinDays', 'Minimum days'),
                      ('dueMaxDays', 'Maximum days'),
                    ]) ...[
                      TextFormField(
                        controller: schedule[bound.$1],
                        enabled: !saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                        ),
                        decoration: InputDecoration(
                          labelText: bound.$2,
                          hintText: 'No bound',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : submit,
          child: Text(saving ? 'Saving…' : 'Save changes'),
        ),
      ],
    ),
  );
}
