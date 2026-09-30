import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'platform/log_folder.dart';
import 'storage/task_store.dart';

void main() {
  debugPrint('TANDEMLOG_MAIN');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TandemlogApp());
}

class TandemlogApp extends StatelessWidget {
  const TandemlogApp({super.key, this.profilePath});
  final String? profilePath;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tandemlog',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff267461)),
      scaffoldBackgroundColor: const Color(0xfff6f7f2),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    ),
    home: TasksPage(profilePath: profilePath),
  );
}

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.profilePath});
  final String? profilePath;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> with WidgetsBindingObserver {
  TaskStore? store;
  String? user, error;
  bool busy = true, all = false;
  String? privateRoot;
  List<Map<String, dynamic>> rows = [];
  final capture = TextEditingController();
  List<({String id, String title})> pendingCapture = [];
  Timer? timer;
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
      final settings = File('$privateRoot/settings.json');
      if (await settings.exists()) {
        final s = jsonDecode(await settings.readAsString());
        user = s['user'];
        await _open(s['folder'] as String);
      }
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
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
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
    final file = File('$privateRoot/settings.json');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({'folder': store!.folder.location, 'user': user}),
      flush: true,
    );
    await temp.rename(file.path);
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
          rows = store?.rows ?? [];
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _refresh() async {
    if (store == null || busy || syncing != null) return;
    syncing = () async {
      try {
        final changed = await store!.refresh();
        if (mounted && (changed || error != null)) {
          setState(() {
            rows = store!.rows;
            error = null;
          });
        }
      } catch (e) {
        if (mounted && error != '$e') setState(() => error = '$e');
      }
    }();
    await syncing;
    syncing = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _chooseFolder() async {
    await _act(() async {
      final selected = Platform.isAndroid
          ? await AndroidLogFolder.pick()
          : await getDirectoryPath(confirmButtonText: 'Use this folder');
      if (selected == null || !mounted) return;
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
      pendingCapture.clear();
      capture.clear();
      await store?.close();
      store = null;
      user = null;
      rows = [];
      await _open(selected);
      await _saveSettings();
    });
  }

  Future<void> _addUser() async {
    final name = await _textDialog('Who is using Tandemlog?', label: 'Name');
    if (name == null) return;
    await _act(() async {
      final id = const Uuid().v4();
      await store!.command(id, 'user.created', {'name': name});
      user = id;
      await _saveSettings();
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
    if (pendingCapture.map((entry) => entry.title).join('\n') !=
        titles.join('\n')) {
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
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    capture.dispose();
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
              r['completed'] != true &&
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
                  padding: const EdgeInsets.fromLTRB(24, 24, 16, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 32,
                        color: Color(0xff267461),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Tandemlog',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (store != null)
                        IconButton(
                          tooltip: 'Refresh folder',
                          onPressed: busy ? null : _refresh,
                          icon: const Icon(Icons.refresh),
                        ),
                      IconButton(
                        tooltip: 'Choose data folder',
                        onPressed: busy ? null : _chooseFolder,
                        icon: const Icon(Icons.folder_open),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Row(
                    children: [
                      Icon(
                        error == null
                            ? Icons.offline_bolt_outlined
                            : Icons.warning_amber,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          store == null
                              ? 'Your data, in your folder'
                              : error != null
                              ? 'Needs attention · writes will validate history first'
                              : 'Saved on this device · folder sync handled separately',
                          style: Theme.of(context).textTheme.bodySmall,
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
          const Text(
            'Keep household tasks together, even offline.\nChoose a dedicated folder for your shared task history.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: busy ? null : _chooseFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose data folder'),
          ),
          const SizedBox(height: 16),
          const Text(
            'To share across devices, sync that folder with your preferred folder-sync app.',
          ),
        ],
      ),
    ),
  );
  Widget _users(List<Map<String, dynamic>> users) => ListView(
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
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Room for what matters.',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Switch user',
            onSelected: (v) => _act(() async {
              user = v == 'new' ? null : v;
              await _saveSettings();
            }),
            itemBuilder: (_) => [
              for (final u in users)
                PopupMenuItem(value: u['id'], child: Text(u['name'])),
              const PopupMenuItem(value: 'new', child: Text('Manage users')),
            ],
            child: Chip(
              avatar: const Icon(Icons.person_outline, size: 18),
              label: Text(users.firstWhere((u) => u['id'] == user)['name']),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '${tasks.length} open ${tasks.length == 1 ? 'task' : 'tasks'} · take them one at a time',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 24),
      TextField(
        controller: capture,
        minLines: 1,
        maxLines: 4,
        enabled: !busy,
        decoration: InputDecoration(
          labelText: 'What needs doing?',
          hintText: 'One task per line',
          suffixIcon: IconButton(
            tooltip: 'Add tasks',
            onPressed: busy ? null : _capture,
            icon: const Icon(Icons.arrow_upward),
          ),
        ),
        onSubmitted: (_) => _capture(),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          const Text(
            'YOUR TASKS',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.4),
          ),
          const Spacer(),
          FilterChip(
            label: const Text('Everyone'),
            selected: all,
            onSelected: (v) => setState(() => all = v),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (tasks.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 56),
          child: Column(
            children: [
              Icon(Icons.done_all, size: 48, color: Color(0xff267461)),
              SizedBox(height: 12),
              Text(
                'A clear slate.',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text('Capture something above when it comes to mind.'),
            ],
          ),
        ),
      for (final task in tasks)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            margin: EdgeInsets.zero,
            color: Colors.white,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              leading: IconButton(
                tooltip: 'Complete ${task['title']}',
                onPressed: busy ? null : () => _complete(task),
                icon: const Icon(Icons.radio_button_unchecked),
              ),
              title: Text(
                task['title'],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    if (task['inbox'] == true) 'Inbox',
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
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : () => _edit(task),
            ),
          ),
        ),
    ],
  );
}
