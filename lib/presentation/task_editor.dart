import 'dart:convert';
import 'package:flutter/material.dart';
import '../domain/schedule.dart';
import '../domain/event.dart' show validateTags;
import '../domain/bulk_task_edit.dart';
import 'failure_message.dart';

class TaskEditor extends StatefulWidget {
  const TaskEditor({
    super.key,
    required this.task,
    required this.save,
    this.onDelete,
    this.onClose,
    this.selectionCount,
    this.onClearSelection,
    this.users = const [],
    this.panel = false,
  });
  final Map<String, dynamic> task;
  final Future<void> Function(Map<String, dynamic>, List<String>, List<String>)
  save;
  final Future<void> Function()? onDelete;
  final VoidCallback? onClose;
  final int? selectionCount;
  final Future<void> Function()? onClearSelection;
  final List<Map<String, dynamic>> users;
  final bool panel;
  @override
  TaskEditorState createState() => TaskEditorState();
}

class TaskEditorState extends State<TaskEditor> {
  final GlobalKey<_EditorBodyState> _body = GlobalKey();
  Future<bool> canClose() async => await _body.currentState?.canClose() ?? true;
  Future<bool> confirmDiscard() => canClose();
  @override
  Widget build(BuildContext context) => _EditorBody(
    key: _body,
    tasks: [widget.task],
    users: widget.users,
    panel: widget.panel,
    onClose: widget.onClose,
    selectionCount: widget.selectionCount,
    onClearSelection: widget.onClearSelection,
    onDelete: widget.onDelete,
    saveSingle: widget.save,
  );
}

class BulkTaskEditor extends StatefulWidget {
  const BulkTaskEditor({
    super.key,
    required this.tasks,
    required this.onSave,
    this.onDelete,
    this.onClose,
    this.selectionCount,
    this.onClearSelection,
    this.users = const [],
    this.panel = false,
  });
  final List<Map<String, dynamic>> tasks;
  final Future<void> Function(BulkTaskEdit) onSave;
  final Future<void> Function()? onDelete;
  final VoidCallback? onClose;
  final int? selectionCount;
  final Future<void> Function()? onClearSelection;
  final List<Map<String, dynamic>> users;
  final bool panel;
  @override
  BulkTaskEditorState createState() => BulkTaskEditorState();
}

class BulkTaskEditorState extends State<BulkTaskEditor> {
  final GlobalKey<_EditorBodyState> _body = GlobalKey();
  Future<bool> canClose() async => await _body.currentState?.canClose() ?? true;
  Future<bool> confirmDiscard() => canClose();
  @override
  Widget build(BuildContext context) => _EditorBody(
    key: _body,
    tasks: widget.tasks,
    users: widget.users,
    panel: widget.panel,
    onClose: widget.onClose,
    selectionCount: widget.selectionCount,
    onClearSelection: widget.onClearSelection,
    onDelete: widget.onDelete,
    saveBulk: widget.onSave,
  );
}

class _EditorBody extends StatefulWidget {
  const _EditorBody({
    super.key,
    required this.tasks,
    required this.users,
    required this.panel,
    this.onClose,
    this.selectionCount,
    this.onClearSelection,
    this.onDelete,
    this.saveSingle,
    this.saveBulk,
  });
  final List<Map<String, dynamic>> tasks, users;
  final bool panel;
  final VoidCallback? onClose;
  final int? selectionCount;
  final Future<void> Function()? onClearSelection;
  final Future<void> Function()? onDelete;
  final Future<void> Function(Map<String, dynamic>, List<String>, List<String>)?
  saveSingle;
  final Future<void> Function(BulkTaskEdit)? saveBulk;
  @override
  State<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends State<_EditorBody> {
  late final List<Map<String, dynamic>> originals;
  final controllers = <String, TextEditingController>{};
  final touched = <String>{}, applied = <String>{}, mixed = <String>{};
  final scroll = ScrollController();
  bool busy = false, attempted = false, showOverride = false, allowPop = false;
  String? failure, assignee;
  bool applyAssignee = false;
  Future<bool>? closeRequest;
  bool get bulk => widget.saveBulk != null;
  Map<String, dynamic> scheduleOf(Map<String, dynamic> task) =>
      Map<String, dynamic>.from(task['schedule'] as Map? ?? {});
  @override
  void initState() {
    super.initState();
    originals = (jsonDecode(jsonEncode(widget.tasks)) as List)
        .cast<Map<String, dynamic>>();
    final first = originals.first;
    for (final key in [
      ...TaskSchedule.keys,
      'title',
      'description',
      'tags',
      'addTags',
      'removeTags',
    ]) {
      dynamic value = TaskSchedule.keys.contains(key)
          ? scheduleOf(first)[key]
          : first[key];
      if (bulk &&
          TaskSchedule.keys.contains(key) &&
          originals.any((task) => scheduleOf(task)[key] != value)) {
        mixed.add(key);
        value = null;
      }
      controllers[key] = TextEditingController(
        text: key == 'tags'
            ? (first['tags'] as List? ?? []).join(' ')
            : {'addTags', 'removeTags'}.contains(key)
            ? ''
            : value?.toString() ?? '',
      );
      final controller = controllers[key]!;
      var previousText = controller.text;
      controller.addListener(() {
        // Focus/caret changes notify too. They must not apply a blank mixed
        // schedule field or mark an otherwise untouched draft as dirty.
        if (controller.text == previousText) return;
        previousText = controller.text;
        if (mounted) {
          setState(() {
            touched.add(key);
            if (bulk && TaskSchedule.keys.contains(key)) applied.add(key);
          });
        }
      });
    }
    assignee = first['assignee'] as String?;
    if (bulk && originals.any((task) => task['assignee'] != assignee)) {
      assignee = null;
      mixed.add('assignee');
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  dynamic value(String key) {
    final text = controllers[key]!.text.trim();
    if (text.isEmpty) return null;
    if (key == 'dueMinDays' || key == 'dueMaxDays') {
      return int.tryParse(text) ??
          (throw const FormatException(
            'Sort-date bounds must be whole numbers of days.',
          ));
    }
    return text;
  }

  List<String> tags(String key) {
    final result = controllers[key]!.text
        .split(RegExp(r'\s+'))
        .where((v) => v.isNotEmpty)
        .map((v) => v.startsWith('#') ? v.substring(1) : v)
        .toSet()
        .toList();
    validateTags(result);
    return result;
  }

  Map<String, dynamic> get patch => {
    for (final key in TaskSchedule.keys)
      if (!bulk || applied.contains(key)) key: value(key),
  };
  String? get validation {
    try {
      if (!bulk && controllers['title']!.text.trim().isEmpty) {
        return 'Enter a task title.';
      }
      if (!bulk && controllers['title']!.text.trim().length > 500) {
        return 'Title must be 500 characters or fewer.';
      }
      if (!bulk && controllers['description']!.text.length > 10000) {
        return 'Notes must be 10000 characters or fewer.';
      }
      if (bulk) {
        final edit = draft;
        for (final task in originals) {
          TaskSchedule.fromJson({...scheduleOf(task), ...edit.schedulePatch});
          edit.fieldsFor({...task, 'tagRefs': task['tagRefs'] ?? {}});
        }
      } else {
        TaskSchedule.fromJson(patch);
        tags('tags');
      }
      return null;
    } catch (e) {
      return e is FormatException ? e.message.toString() : e.toString();
    }
  }

  BulkTaskEdit get draft => BulkTaskEdit(
    schedulePatch: patch,
    assignee: applyAssignee ? assignee : null,
    addTags: tags('addTags'),
    removeTags: tags('removeTags'),
  );
  bool get dirty {
    if (bulk) {
      return applied.isNotEmpty ||
          applyAssignee ||
          controllers['addTags']!.text.isNotEmpty ||
          controllers['removeTags']!.text.isNotEmpty;
    }
    final first = originals.first;
    return controllers['title']!.text != (first['title'] ?? '') ||
        controllers['description']!.text != (first['description'] ?? '') ||
        controllers['tags']!.text != (first['tags'] as List? ?? []).join(' ') ||
        assignee != first['assignee'] ||
        TaskSchedule.keys.any(
          (key) =>
              controllers[key]!.text !=
              (scheduleOf(first)[key]?.toString() ?? ''),
        );
  }

  Future<bool> canClose() {
    if (busy) return Future.value(false);
    if (!dirty) return Future.value(true);
    return closeRequest ??= askClose().whenComplete(() => closeRequest = null);
  }

  Future<bool> askClose() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save your draft before continuing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    if (choice == 'discard') return true;
    if (choice == 'save') return commit(closeAfter: false);
    return false;
  }

  void finish() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      setState(() => allowPop = true);
      Navigator.pop(context);
    }
  }

  Future<void> close() async {
    if (await canClose() && mounted) finish();
  }

  Future<void> submit() async {
    await commit(closeAfter: true);
  }

  Future<bool> commit({required bool closeAfter}) async {
    if (busy) return false;
    setState(() => attempted = true);
    if (validation != null) return false;
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      if (bulk) {
        await widget.saveBulk!(draft);
      } else {
        final first = originals.first,
            parsed = TaskSchedule.fromJson(patch).toJson();
        final originalTags = Set<String>.from(first['tags'] as List? ?? []),
            desired = tags('tags').toSet();
        await widget.saveSingle!(
          {
            if (controllers['title']!.text.trim() != first['title'])
              'title': controllers['title']!.text.trim(),
            if (controllers['description']!.text != first['description'])
              'description': controllers['description']!.text,
            if (assignee != first['assignee']) 'assignee': assignee,
            if (parsed.entries.any((e) => scheduleOf(first)[e.key] != e.value))
              'schedule': parsed,
          },
          desired.difference(originalTags).toList(),
          originalTags.difference(desired).toList(),
        );
      }
      if (!mounted) return false;
      if (closeAfter) {
        finish();
      } else {
        setState(() => busy = false);
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          failure = failureMessage(e);
          busy = false;
        });
      }
      return false;
    }
  }

  Future<void> delete() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          bulk ? 'Delete ${originals.length} tasks?' : 'Delete task?',
        ),
        content: const Text(
          'This deletes the selected task entries. Future repeating tasks are separate entries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      await widget.onDelete!();
      if (mounted) finish();
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          failure = failureMessage(e);
        });
      }
    }
  }

  Widget field(String key, String label, {String? hint, int lines = 1}) {
    final input = TextField(
      key: ValueKey(key),
      controller: controllers[key],
      enabled: !busy,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: key.endsWith('Date')
            ? IconButton(
                tooltip: 'Choose $label',
                icon: const Icon(Icons.calendar_today_outlined),
                onPressed: busy
                    ? null
                    : () async {
                        final parsed = DateTime.tryParse(
                          controllers[key]!.text,
                        );
                        final chosen = await showDatePicker(
                          context: context,
                          initialDate:
                              parsed != null &&
                                  parsed.year >= 1900 &&
                                  parsed.year <= 9999
                              ? parsed
                              : DateTime.now(),
                          firstDate: DateTime(1900),
                          lastDate: DateTime(9999),
                        );
                        if (chosen != null && mounted) {
                          controllers[key]!.text = formatCivilDate(chosen);
                        }
                      },
              )
            : key == 'recurrence'
            ? PopupMenuButton<String>(
                tooltip: 'Repeat examples',
                enabled: !busy,
                icon: const Icon(Icons.expand_more),
                onSelected: (rule) => controllers[key]!.text = rule,
                itemBuilder: (_) => [
                  for (final rule in observedRecurrences)
                    PopupMenuItem(value: rule, child: Text(rule)),
                ],
              )
            : null,
        hintText: mixed.contains(key)
            ? 'Mixed — unchanged unless applied'
            : hint,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: bulk && TaskSchedule.keys.contains(key)
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: applied.contains(key),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          if (v!) {
                            applied.add(key);
                          } else {
                            applied.remove(key);
                          }
                        }),
                ),
                Expanded(child: input),
              ],
            )
          : input,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repeating =
        controllers['recurrence']!.text.trim().isNotEmpty ||
        (bulk &&
            !applied.contains('recurrence') &&
            originals.any((t) => scheduleOf(t)['recurrence'] != null));
    final overrides = ['scheduledDate', 'scheduledTime'].any(
      (key) =>
          controllers[key]!.text.trim().isNotEmpty ||
          (bulk &&
              !applied.contains(key) &&
              originals.any((task) => scheduleOf(task)[key] != null)),
    );
    final error = (attempted || touched.isNotEmpty || applied.isNotEmpty)
        ? validation
        : null;
    final content = Form(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!bulk) ...[
            field('title', 'Title', lines: 2),
            field('description', 'Notes', lines: 3),
            field('tags', 'Tags', hint: 'Separate tags with spaces'),
          ] else ...[
            field('addTags', 'Add tags', hint: 'Separate tags with spaces'),
            field(
              'removeTags',
              'Remove tags',
              hint: 'Separate tags with spaces',
            ),
          ],
          if (widget.users.isNotEmpty)
            Row(
              children: [
                if (bulk)
                  Checkbox(
                    value: applyAssignee,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => applyAssignee = v!),
                  ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: widget.users.any((u) => u['id'] == assignee)
                        ? assignee
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Assignee',
                      hintText: mixed.contains('assignee') ? 'Mixed' : null,
                    ),
                    items: [
                      for (final user in widget.users)
                        DropdownMenuItem(
                          value: user['id'] as String,
                          child: Text(
                            user['name'] as String? ?? user['id'] as String,
                          ),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            assignee = v;
                            if (bulk) applyAssignee = true;
                          }),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          field('startDate', 'Start date', hint: 'YYYY-MM-DD'),
          field('startTime', 'Start time', hint: 'HH:mm'),
          field('dueDate', 'Due date', hint: 'YYYY-MM-DD'),
          field('dueTime', 'Due time', hint: 'HH:mm'),
          field('recurrence', 'Repeat', hint: 'every week when done'),
          if (repeating)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'This occurrence changes the planned date; the base due date and repeat cadence remain.',
              ),
            ),
          if (!repeating && overrides) ...[
            const Text('Existing occurrence override is preserved.'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => showOverride = !showOverride),
                  child: const Text('Edit existing override'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          controllers['scheduledDate']!.clear();
                          controllers['scheduledTime']!.clear();
                        },
                  child: const Text('Clear override'),
                ),
              ],
            ),
          ],
          if (repeating || showOverride) ...[
            field('scheduledDate', 'This occurrence date', hint: 'YYYY-MM-DD'),
            field('scheduledTime', 'This occurrence time', hint: 'HH:mm'),
          ],
          field(
            'timeZone',
            'Time zone',
            hint: 'Blank: Local; UTC; America/Chicago',
          ),
          const Text('Sort-date bounds'),
          const Text(
            'Days from today; affects listing order, not the deadline.',
          ),
          field('dueMinDays', 'Minimum days', hint: 'No bound'),
          field('dueMaxDays', 'Maximum days', hint: 'No bound'),
        ],
      ),
    );
    final actions = Row(
      children: [
        if (widget.onDelete != null)
          TextButton(
            onPressed: busy ? null : delete,
            child: const Text('Delete'),
          ),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: busy ? null : close,
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy || error != null ? null : submit,
                child: Text(busy ? 'Saving…' : 'Save changes'),
              ),
            ],
          ),
        ),
      ],
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              bulk ? 'Edit ${originals.length} tasks' : 'Edit task',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (!bulk && widget.selectionCount != null)
              Text(
                '${widget.selectionCount} selected',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (widget.onClearSelection != null)
              TextButton(
                onPressed: busy ? null : widget.onClearSelection,
                child: const Text('Clear Selection'),
              ),
          ],
        ),
        for (final message in [error, failure])
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
      ],
    );
    final editor = widget.panel
        ? Material(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scroll,
                      padding: const EdgeInsets.only(top: 6),
                      child: content,
                    ),
                  ),
                  actions,
                ],
              ),
            ),
          )
        : AlertDialog(
            // Title and form share the bounded scroll area, keeping fields
            // reachable above the keyboard even with enlarged phone text.
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: heading,
            content: SizedBox(width: 480, child: content),
            actions: [actions],
          );
    if (widget.onClose != null) return editor;
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) close();
      },
      child: editor,
    );
  }
}
