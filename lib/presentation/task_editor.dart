import 'dart:convert';
import 'package:flutter/material.dart';
import '../domain/schedule.dart';
import '../domain/event.dart' show validateTags;
import '../domain/bulk_task_edit.dart';
import 'failure_message.dart';
import '../application/task_text_session.dart';
import 'title_line_formatter.dart';

// Experimental preview injection only; not connected to the application host.
typedef TagEntryTrialBuilder =
    Widget Function(
      String field,
      String label,
      TextEditingController controller,
      bool enabled,
    );

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
    this.tagEntryTrialBuilder,
    this.textSession,
    this.textStatus,
    this.disableTextFields = false,
    this.checklistBuilder,
  });
  final Widget Function(bool enabled)? checklistBuilder;
  final TaskTextSession? textSession;
  final String? textStatus;
  final bool disableTextFields;
  final Map<String, dynamic> task;
  final Future<void> Function(Map<String, dynamic>, List<String>, List<String>)
  save;
  final Future<void> Function()? onDelete;
  final VoidCallback? onClose;
  final int? selectionCount;
  final Future<void> Function()? onClearSelection;
  final List<Map<String, dynamic>> users;
  final bool panel;
  final TagEntryTrialBuilder? tagEntryTrialBuilder;
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
    tagEntryTrialBuilder: widget.tagEntryTrialBuilder,
    onClose: widget.onClose,
    selectionCount: widget.selectionCount,
    onClearSelection: widget.onClearSelection,
    onDelete: widget.onDelete,
    saveSingle: widget.save,
    textSession: widget.textSession,
    textStatus: widget.textStatus,
    disableTextFields: widget.disableTextFields,
    checklistBuilder: widget.checklistBuilder,
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
    this.tagEntryTrialBuilder,
  });
  final List<Map<String, dynamic>> tasks;
  final Future<void> Function(BulkTaskEdit) onSave;
  final Future<void> Function()? onDelete;
  final VoidCallback? onClose;
  final int? selectionCount;
  final Future<void> Function()? onClearSelection;
  final List<Map<String, dynamic>> users;
  final bool panel;
  final TagEntryTrialBuilder? tagEntryTrialBuilder;
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
    tagEntryTrialBuilder: widget.tagEntryTrialBuilder,
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
    this.tagEntryTrialBuilder,
    this.onClose,
    this.selectionCount,
    this.onClearSelection,
    this.onDelete,
    this.saveSingle,
    this.saveBulk,
    this.textSession,
    this.textStatus,
    this.disableTextFields = false,
    this.checklistBuilder,
  });
  final Widget Function(bool enabled)? checklistBuilder;
  final TaskTextSession? textSession;
  final String? textStatus;
  final bool disableTextFields;
  final List<Map<String, dynamic>> tasks, users;
  final bool panel;
  final TagEntryTrialBuilder? tagEntryTrialBuilder;
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
  double notesMaxHeight = 360, scheduleWidth = 480;
  final textFocus = {
    'title': FocusNode(),
    'description': FocusNode(),
    'startTime': FocusNode(),
    'dueTime': FocusNode(),
  };
  (BoxConstraints, Size, EdgeInsets, double, bool)? textViewport;

  void revealFocusedCaret() {
    if (!mounted) return;
    for (final entry in textFocus.entries) {
      final focus = entry.value;
      final selection = controllers[entry.key]!.selection;
      if (!focus.hasFocus || !selection.isValid || focus.context == null) {
        continue;
      }
      final editable = focus.context!
          .findAncestorStateOfType<EditableTextState>();
      editable?.bringIntoView(selection.extent);
    }
  }

  bool get editingFrozen =>
      busy || widget.textSession?.hasPendingReceipt == true;
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
      if (widget.textSession != null &&
          {'title', 'description'}.contains(key)) {
        controllers[key]!.text = widget.textSession!.text(key);
      }
      final controller = controllers[key]!;
      var previousText = controller.text;
      var previousComposing = controller.value.composing;
      controller.addListener(() {
        // Focus/caret changes notify too. They must not apply a blank mixed
        // schedule field or mark an otherwise untouched draft as dirty.
        if (widget.textSession != null &&
            !widget.textSession!.frozen &&
            {'title', 'description'}.contains(key) &&
            (controller.text != previousText ||
                previousComposing != controller.value.composing)) {
          final composing = controller.value.composing;
          widget.textSession!.replace(
            key,
            controller.text,
            composing: composing.isValid && !composing.isCollapsed,
          );
        }
        final compositionChanged =
            previousComposing != controller.value.composing;
        previousComposing = controller.value.composing;
        if (controller.text == previousText) {
          if (key == 'title' && compositionChanged && mounted) setState(() {});
          return;
        }
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
    for (final focus in textFocus.values) {
      focus.dispose();
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
      if (!bulk &&
          controllers['title']!.text != originals.first['title'] &&
          controllers['title']!.value.composing.isValid &&
          !controllers['title']!.value.composing.isCollapsed) {
        return 'Finish entering the title before saving.';
      }
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
    if (editingFrozen) return Future.value(false);
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
    if (!bulk && controllers['title']!.text != originals.first['title']) {
      // Focus loss can finalize composition through the controller without
      // running input formatters. Normalize only this changed, committed title.
      final title = controllers['title']!;
      title.value = TitleLineFormatter().formatEditUpdate(
        TextEditingValue.empty,
        title.value,
      );
    }
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
            if (widget.textSession == null &&
                !widget.disableTextFields &&
                controllers['title']!.text != first['title'])
              'title': controllers['title']!.text.trim(),
            if (widget.textSession == null &&
                !widget.disableTextFields &&
                controllers['description']!.text != first['description'])
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
      if (widget.textSession != null && !widget.textSession!.frozen) {
        for (final field in ['title', 'description']) {
          final controller = controllers[field]!;
          final text = widget.textSession!.text(field);
          if (controller.text != text) {
            final selection = controller.selection;
            controller.value = TextEditingValue(
              text: text,
              selection: TextSelection(
                baseOffset: selection.baseOffset.clamp(0, text.length),
                extentOffset: selection.extentOffset.clamp(0, text.length),
              ),
            );
          }
        }
      }
      if (widget.textSession != null && !widget.textSession!.frozen) {
        final saved = originals.first;
        saved['title'] = controllers['title']!.text;
        saved['description'] = controllers['description']!.text;
        saved['assignee'] = assignee;
        saved['tags'] = tags('tags');
        saved['schedule'] = TaskSchedule.fromJson(patch).toJson();
        touched.clear();
      }
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
    if (editingFrozen) return;
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

  Widget field(
    String key,
    String label, {
    String? hint,
    String? clearLabel,
    int lines = 1,
    bool withApplyControl = true,
  }) {
    final dateTimeField = const {
      'startDate',
      'startTime',
      'dueDate',
      'dueTime',
    }.contains(key);
    if (widget.tagEntryTrialBuilder != null &&
        const {'tags', 'addTags', 'removeTags'}.contains(key)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: widget.tagEntryTrialBuilder!(
          key,
          label,
          controllers[key]!,
          !editingFrozen,
        ),
      );
    }
    final input = TextField(
      key: ValueKey(key),
      controller: controllers[key],
      focusNode: textFocus[key],
      enabled:
          !editingFrozen &&
          !(widget.disableTextFields &&
              {'title', 'description'}.contains(key)) &&
          !(widget.textSession?.frozen == true &&
              {'title', 'description'}.contains(key)),
      minLines: key == 'description' ? 3 : 1,
      maxLines: key == 'description' ? null : lines,
      inputFormatters: key == 'title' ? [TitleLineFormatter()] : null,
      keyboardType: key == 'title' ? TextInputType.text : null,
      textInputAction: key == 'title' ? TextInputAction.next : null,
      decoration: InputDecoration(
        labelText: label,
        border: dateTimeField ? const OutlineInputBorder(gapPadding: 2) : null,
        suffixIconConstraints: dateTimeField
            ? const BoxConstraints(minWidth: 48, minHeight: 48)
            : null,
        contentPadding: dateTimeField
            ? const EdgeInsets.fromLTRB(4, 16, 0, 16)
            : null,
        suffixIcon: key.endsWith('Date')
            ? IconButton(
                tooltip: 'Choose $label',
                visualDensity: dateTimeField ? VisualDensity.standard : null,
                padding: dateTimeField ? EdgeInsets.zero : null,
                constraints: dateTimeField
                    ? const BoxConstraints(minWidth: 48, minHeight: 48)
                    : null,
                icon: const Icon(Icons.calendar_today_outlined),
                onPressed: editingFrozen
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
            : (key == 'startTime' || key == 'dueTime') &&
                  controllers[key]!.text.isNotEmpty
            ? IconButton(
                tooltip: 'Clear ${clearLabel ?? label}',
                visualDensity: VisualDensity.standard,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.close),
                onPressed: editingFrozen
                    ? null
                    : () {
                        textFocus[key]?.unfocus();
                        controllers[key]!.clear();
                      },
              )
            : key == 'recurrence'
            ? PopupMenuButton<String>(
                tooltip: 'Repeat examples',
                enabled: !editingFrozen,
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
      child: bulk && withApplyControl && TaskSchedule.keys.contains(key)
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                scheduleApply(key, fullTarget: dateTimeField),
                Expanded(child: input),
              ],
            )
          : key == 'description'
          ? ConstrainedBox(
              constraints: BoxConstraints(maxHeight: notesMaxHeight),
              child: input,
            )
          : input,
    );
  }

  Widget scheduleApply(String key, {bool fullTarget = false}) => Checkbox(
    visualDensity: fullTarget ? VisualDensity.standard : null,
    materialTapTargetSize: fullTarget ? MaterialTapTargetSize.padded : null,
    key: ValueKey('${key}Apply'),
    value: applied.contains(key),
    onChanged: editingFrozen
        ? null
        : (value) => setState(() {
            if (value!) {
              applied.add(key);
            } else {
              applied.remove(key);
            }
          }),
  );

  Widget dateTimeRow(String prefix, String label) {
    // Use the editor's outer constraints: AlertDialog asks its content for
    // intrinsic dimensions, which an inner LayoutBuilder cannot provide.
    // Measure supported ISO date / 24-hour time content. Fixed icon targets and
    // padding do not grow with text scale; multiplying the whole row width made
    // enlarged-text rows stack substantially before their contents required it.
    final style = Theme.of(context).textTheme.bodyLarge!;
    double textWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    // 4px leading padding + 2px outline gap + 48px suffix target
    // + 4px Material text-to-suffix gap + 2px caret clearance.
    // A blank Time hint has no clear button, so it uses only padding.
    final dateValueWidth = textWidth('2026-10-04');
    final dateHintWidth = textWidth('YYYY-MM-DD');
    final dateWidth =
        (dateValueWidth > dateHintWidth ? dateValueWidth : dateHintWidth) + 60;
    final populatedTimeWidth = textWidth('23:59') + 60;
    final blankTimeWidth = textWidth('HH:mm') + 10;
    final timeWidth = populatedTimeWidth > blankTimeWidth
        ? populatedTimeWidth
        : blankTimeWidth;
    // Allocate the 5:3 ratio to the inputs themselves. Fixed apply checkboxes
    // sit beside each input instead of consuming the narrower time flex cell.
    final applyWidth = bulk ? 96.0 : 0.0;
    final dateRowWidth = dateWidth * 8 / 5;
    final timeRowWidth = timeWidth * 8 / 3;
    final minimumWidth =
        12 +
        applyWidth +
        (dateRowWidth > timeRowWidth ? dateRowWidth : timeRowWidth);
    final stacked = scheduleWidth < minimumWidth.ceilToDouble();
    final dateKey = '${prefix}Date';
    final timeKey = '${prefix}Time';
    final date = field(
      dateKey,
      '$label date',
      hint: 'YYYY-MM-DD',
      withApplyControl: stacked,
    );
    final time = Semantics(
      label: label,
      child: field(
        timeKey,
        'Time',
        hint: 'HH:mm',
        clearLabel: '$label time',
        withApplyControl: stacked,
      ),
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [date, time],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bulk) scheduleApply(dateKey, fullTarget: true),
        Expanded(flex: 5, child: date),
        const SizedBox(width: 12),
        if (bulk) scheduleApply(timeKey, fullTarget: true),
        Expanded(flex: 3, child: time),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      scheduleWidth = widget.panel
          ? (constraints.maxWidth - 40).clamp(0.0, double.infinity)
          : (media.size.width - 64).clamp(0.0, 480.0);
      final viewport = (
        constraints,
        media.size,
        media.viewInsets,
        media.textScaler.scale(14),
        widget.panel,
      );
      // Only geometry changes need a reveal. Ordinary validation, incoming
      // task data and theme rebuilds must preserve the user's scroll position.
      if (textViewport != null && textViewport != viewport) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => revealFocusedCaret(),
        );
      }
      textViewport = viewport;
      final visibleHeight = media.size.height - media.viewInsets.bottom;
      final availableHeight = constraints.maxHeight < visibleHeight
          ? constraints.maxHeight
          : visibleHeight;
      notesMaxHeight = (availableHeight * .4).clamp(100.0, 360.0);
      return buildEditor(context);
    },
  );

  Widget buildEditor(BuildContext context) {
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
            if (widget.checklistBuilder != null)
              widget.checklistBuilder!(!editingFrozen),
            if (widget.disableTextFields && widget.textStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.textStatus!,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          dateTimeRow('start', 'Start'),
          dateTimeRow('due', 'Due'),
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
                  onPressed: editingFrozen
                      ? null
                      : () => setState(() => showOverride = !showOverride),
                  child: const Text('Edit existing override'),
                ),
                TextButton(
                  onPressed: editingFrozen
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
          if (!bulk)
            field('tags', 'Tags', hint: 'Separate tags with spaces')
          else ...[
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
                    onChanged: editingFrozen
                        ? null
                        : (v) => setState(() => applyAssignee = v!),
                  ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    itemHeight: null,
                    selectedItemBuilder: (_) => [
                      for (final user in widget.users)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            user['name'] as String? ?? user['id'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
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
                    onChanged: editingFrozen
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
        ],
      ),
    );
    final actions = Row(
      children: [
        if (widget.onDelete != null)
          TextButton(
            onPressed: editingFrozen ? null : delete,
            child: const Text('Delete'),
          ),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: editingFrozen ? null : close,
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy || error != null ? null : submit,
                child: Text(
                  busy
                      ? 'Saving…'
                      : widget.textSession?.hasPendingReceipt == true
                      ? 'Retry Save'
                      : 'Save changes',
                ),
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
                onPressed: editingFrozen ? null : widget.onClearSelection,
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
