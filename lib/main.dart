import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
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
  const TandemlogApp({super.key, this.profilePath, this.folderActions});
  final String? profilePath;
  final FolderActions? folderActions;
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
  });
  final String? profilePath;
  final ValueNotifier<Appearance> appearance;
  final FolderActions folderActions;
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
                const Text('Appearance'),
                const SizedBox(height: 12),
                SegmentedButton<Appearance>(
                  direction:
                      MediaQuery.sizeOf(ctx).width < 480 ||
                          MediaQuery.textScalerOf(ctx).scale(14) > 20
                      ? Axis.vertical
                      : Axis.horizontal,
                  segments: const [
                    ButtonSegment(
                      value: Appearance.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: Appearance.light,
                      label: Text('Light'),
                    ),
                    ButtonSegment(value: Appearance.dark, label: Text('Dark')),
                  ],
                  selected: {widget.appearance.value},
                  onSelectionChanged: settingsLoaded
                      ? (values) => Navigator.pop(ctx, values.first.name)
                      : null,
                ),
                const SizedBox(height: 24),
                const Text('Data folder'),
                const SizedBox(height: 8),
                if (location != null) ...[
                  if (!widget.folderActions.requiresPicker)
                    SelectableText(location),
                  const Text(
                    'Sync this folder with your preferred sync app. Other devices receive changes when that app syncs.',
                  ),
                  if (!widget.folderActions.requiresPicker) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: canOpen
                          ? () => Navigator.pop(ctx, 'open')
                          : null,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open data folder'),
                    ),
                    if (!canOpen)
                      const Text(
                        'No file manager is available to open this folder.',
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'Back up or sync this folder before removing Tandemlog’s app data.',
                    ),
                  ],
                  if (widget.folderActions.requiresPicker)
                    const Text(
                      'Manage this folder in Android’s Files or your sync app.',
                    ),
                ] else
                  const Text('A data folder will be set up when you start.'),
                TextButton(
                  onPressed: settingsLoaded
                      ? () => Navigator.pop(ctx, 'choose')
                      : null,
                  child: Text(
                    location == null
                        ? 'Choose an existing folder'
                        : 'Use a different folder',
                  ),
                ),
                if (location != null)
                  const Text(
                    'Switching folders does not move or delete your tasks.',
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
        final changed = await origin.refresh();
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
            (changed || errorFromRefresh || reconcileCapture)) {
          setState(() {
            rows = origin.rows;
            if (errorFromRefresh) error = null;
            errorFromRefresh = false;
          });
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
    final title = TextEditingController(text: task['title']);
    final description = TextEditingController(text: task['description']);
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit task'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: description,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 10000,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isNotEmpty) {
                Navigator.pop(ctx, {
                  'title': title.text.trim(),
                  'description': description.text,
                });
              }
            },
            child: const Text('Save changes'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      title.dispose();
      description.dispose();
    });
    if (values == null) return;
    // Emit only changed fields so independent edits can merge.
    final changed = Map<String, dynamic>.from(values)
      ..removeWhere((k, v) => task[k] == v);
    if (changed.isEmpty) return;
    await _act(() => store!.command(task['id'], 'task.edited', changed));
  }

  Future<void> _reopen(Map<String, dynamic> task) async {
    final origin = store!;
    final observed = origin.activeCompletionIds(task['id']);
    await _act(() => origin.reopen(task['id'], observed));
  }

  Future<void> _complete(Map<String, dynamic> task) async {
    await _act(() async {
      final origin = store!;
      final event = await origin.command(task['id'], 'task.completed', {});
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
    final tasks = rows
        .where(
          (r) =>
              r['kind'] == 'task' &&
              (r['completed'] == true) == showCompleted &&
              (all || r['assignee'] == user),
        )
        .toList();
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
                Expanded(
                  child: store == null
                      ? _welcome()
                      : user == null
                      ? _users(users)
                      : _tasks(tasks, users),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome() => Center(
    child: Padding(
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
          FilledButton(
            onPressed: busy || !settingsLoaded
                ? null
                : settings!.folder != null
                ? () => _act(() => _open(settings!.folder!))
                : widget.folderActions.requiresPicker
                ? _chooseFolder
                : _startDefault,
            child: Text(settings?.folder != null ? 'Try again' : 'Start'),
          ),
          if (!widget.folderActions.requiresPicker && settings?.folder == null)
            TextButton(
              onPressed: busy || !settingsLoaded ? null : _chooseFolder,
              child: const Text('Choose an existing folder'),
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
  Widget _tasks(
    List<Map<String, dynamic>> tasks,
    List<Map<String, dynamic>> users,
  ) => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: all ? 'All tasks' : 'Your tasks',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text:
                      ' · ${tasks.length} ${showCompleted ? 'completed' : 'open'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Wrap(
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
                  const PopupMenuItem(
                    value: 'new',
                    child: Text('Manage users'),
                  ),
                ],
                child: Chip(
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      users.firstWhere((u) => u['id'] == user)['name'],
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              FilterChip(
                label: const Text('Everyone'),
                selected: all,
                onSelected: (value) => setState(() => all = value),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Open')),
          ButtonSegment(value: true, label: Text('Completed')),
        ],
        selected: {showCompleted},
        onSelectionChanged: (values) =>
            setState(() => showCompleted = values.first),
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
                  capture.value = TextEditingValue(
                    text: value.text.replaceRange(
                      selection.start,
                      selection.end,
                      '\n',
                    ),
                    selection: TextSelection.collapsed(
                      offset: selection.start + 1,
                    ),
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
                showCompleted ? 'No completed tasks' : 'No open tasks',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                showCompleted
                    ? 'Completed tasks will appear here.'
                    : 'Add a task above.',
              ),
            ],
          ),
        ),
      for (final task in tasks) ...[
        ListTile(
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
                  : (_) => showCompleted ? _reopen(task) : _complete(task),
            ),
          ),
          title: Text(
            task['title'],
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: !all && (task['description'] as String).isEmpty
              ? null
              : Text(
                  [
                    if (all)
                      users
                              .where((u) => u['id'] == task['assignee'])
                              .map((u) => u['name'])
                              .firstOrNull ??
                          'Unknown user',
                    if ((task['description'] as String).isNotEmpty)
                      task['description'],
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: busy ? null : () => _edit(task),
        ),
        const Divider(height: 1),
      ],
    ],
  );
}
