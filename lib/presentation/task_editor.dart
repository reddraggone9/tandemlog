import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;

import 'tag_input.dart';
import 'civil_date_input.dart';
import '../domain/schedule.dart';
import '../domain/occurrence_due_migration.dart';
import '../domain/event.dart' show validateTags;
import '../domain/bulk_task_edit.dart';
import 'failure_message.dart';
import '../application/task_text_session.dart';
import 'title_line_formatter.dart';
import 'unsaved_draft_dialog.dart';
import 'form_validation.dart';
import 'task_field_help.dart';

class TaskEditor extends StatefulWidget {
  const TaskEditor({
    super.key,
    required this.task,
    required this.save,
    this.onDelete,
    this.onClose,
    this.onCloseReadinessChanged,
    this.contextNotice,
    this.selectionCount,
    this.onClearSelection,
    this.users = const [],
    this.tagInventory = const [],
    this.panel = false,
    this.textSession,
    this.textStatus,
    this.disableTextFields = false,
  });
  final TaskTextSession? textSession;
  final String? textStatus;
  final bool disableTextFields;
  final Map<String, dynamic> task;
  final Future<void> Function(Map<String, dynamic>, List<String>, List<String>)
  save;
  final Future<void> Function()? onDelete;
  final VoidCallback? onClose, onCloseReadinessChanged;
  final Widget? contextNotice;
  final int? selectionCount;
  final Future<void> Function()? onClearSelection;
  final List<Map<String, dynamic>> users;
  final bool panel;
  final List<String> tagInventory;
  @override
  TaskEditorState createState() => TaskEditorState();
}

class TaskEditorState extends State<TaskEditor> {
  final GlobalKey<_EditorBodyState> _body = GlobalKey();
  bool get closeBusy => _body.currentState?.closeBusy ?? true;
  Future<bool> canClose() async => await _body.currentState?.canClose() ?? true;
  Future<bool> confirmDiscard() => canClose();
  @override
  Widget build(BuildContext context) => _EditorBody(
    key: _body,
    tasks: [widget.task],
    users: widget.users,
    tagInventory: widget.tagInventory,
    panel: widget.panel,
    onClose: widget.onClose,
    onCloseReadinessChanged: widget.onCloseReadinessChanged,
    contextNotice: widget.contextNotice,
    selectionCount: widget.selectionCount,
    onClearSelection: widget.onClearSelection,
    onDelete: widget.onDelete,
    saveSingle: widget.save,
    textSession: widget.textSession,
    textStatus: widget.textStatus,
    disableTextFields: widget.disableTextFields,
  );
}

class BulkTaskEditor extends StatefulWidget {
  const BulkTaskEditor({
    super.key,
    required this.tasks,
    required this.onSave,
    this.onDelete,
    this.onClose,
    this.onCloseReadinessChanged,
    this.contextNotice,
    this.selectionCount,
    this.onClearSelection,
    this.users = const [],
    this.tagInventory = const [],
    this.panel = false,
  });
  final List<Map<String, dynamic>> tasks;
  final Future<void> Function(BulkTaskEdit) onSave;
  final Future<void> Function()? onDelete;
  final VoidCallback? onClose, onCloseReadinessChanged;
  final Widget? contextNotice;
  final int? selectionCount;
  final Future<void> Function()? onClearSelection;
  final List<Map<String, dynamic>> users;
  final bool panel;
  final List<String> tagInventory;
  @override
  BulkTaskEditorState createState() => BulkTaskEditorState();
}

class BulkTaskEditorState extends State<BulkTaskEditor> {
  final GlobalKey<_EditorBodyState> _body = GlobalKey();
  bool get closeBusy => _body.currentState?.closeBusy ?? true;
  Future<bool> canClose() async => await _body.currentState?.canClose() ?? true;
  Future<bool> confirmDiscard() => canClose();
  @override
  Widget build(BuildContext context) => _EditorBody(
    key: _body,
    tasks: widget.tasks,
    users: widget.users,
    tagInventory: widget.tagInventory,
    panel: widget.panel,
    onClose: widget.onClose,
    onCloseReadinessChanged: widget.onCloseReadinessChanged,
    contextNotice: widget.contextNotice,
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
    required this.tagInventory,
    required this.panel,
    this.onClose,
    this.onCloseReadinessChanged,
    this.contextNotice,
    this.selectionCount,
    this.onClearSelection,
    this.onDelete,
    this.saveSingle,
    this.saveBulk,
    this.textSession,
    this.textStatus,
    this.disableTextFields = false,
  });
  final TaskTextSession? textSession;
  final String? textStatus;
  final bool disableTextFields;
  final List<Map<String, dynamic>> tasks, users;
  final bool panel;
  final List<String> tagInventory;
  final VoidCallback? onClose, onCloseReadinessChanged;
  final Widget? contextNotice;
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
  final tagQueries = <String, TextEditingController>{};
  final tagSelections = <String, Set<String>>{};
  final touched = <String>{}, applied = <String>{}, mixed = <String>{};
  final scroll = ScrollController();
  bool busy = false, attempted = false, showOverride = false, allowPop = false;
  String? failure, assignee;
  bool applyAssignee = false, modalActionsInContent = false;
  double? modalViewportHeight;
  Future<bool>? closeRequest;
  bool helpOpen = false;
  bool get closeBusy => busy || helpOpen;

  Future<void> openHelp() async {
    if (!mounted ||
        busy ||
        helpOpen ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      return;
    }
    setState(() => helpOpen = true);
    widget.onCloseReadinessChanged?.call();
    try {
      await showTaskFieldHelp(context);
    } finally {
      if (mounted) {
        setState(() => helpOpen = false);
        widget.onCloseReadinessChanged?.call();
      }
    }
  }

  double notesMaxHeight = 360,
      scheduleWidth = 480,
      failureMaxHeight = 144,
      modalActionsMaxHeight = 312;
  final textFocus = {
    for (final field in [...TaskSchedule.keys, 'title', 'description'])
      field: FocusNode(),
  };
  late final FormValidation formValidation;
  String? lastEditedField;
  final settledPrerequisites = <String, String>{};
  final removedPrerequisites = <String>{};
  Map<String, TextEditingValue>? occurrenceBeforeRemoval;
  Set<String>? occurrenceApplyBeforeRemoval;
  bool changingDependentOccurrence = false, dependentEditedAfterRemoval = false;
  String? occurrencePrerequisiteNotice;

  bool prerequisiteValid(String key, String text) {
    if (text.isEmpty) return false;
    try {
      if (key == 'dueDate') {
        TaskSchedule(dueDate: text);
      } else {
        TaskSchedule(dueDate: '2000-01-01', recurrence: text);
      }
      return true;
    } on FormatException {
      return false;
    }
  }

  bool get occurrenceEditingAllowed =>
      occurrenceBeforeRemoval == null &&
      originals.every((task) {
        if (planOccurrenceDueMigration(task)?.conflict != null) return true;
        final before = scheduleOf(task);
        return ['dueDate', 'recurrence'].every(
          (key) => prerequisiteValid(
            key,
            !bulk || applied.contains(key)
                ? controllers[key]!.text.trim()
                : (before[key] as String? ?? ''),
          ),
        );
      });

  void clearOccurrenceOverride() {
    if (!mounted || editingFrozen) return;
    changingDependentOccurrence = true;
    try {
      for (final key in ['scheduledDate', 'scheduledTime']) {
        controllers[key]!.clear();
        touched.add(key);
        if (bulk) applied.add(key);
      }
      if (occurrenceBeforeRemoval != null) dependentEditedAfterRemoval = true;
    } finally {
      changingDependentOccurrence = false;
    }
    formValidation.blur('scheduledDate');
    setState(() {});
  }

  void settleOccurrencePrerequisites([String? field]) {
    if (!mounted || editingFrozen || changingDependentOccurrence) return;
    if (field != null && !const {'dueDate', 'recurrence'}.contains(field)) {
      return;
    }
    for (final key in ['dueDate', 'recurrence']) {
      if (field != null && key != field) continue;
      final value = controllers[key]!.value;
      if (value.composing.isValid && !value.composing.isCollapsed) continue;
      final text = value.text.trim();
      if (bulk && !applied.contains(key)) {
        removedPrerequisites.remove(key);
      } else if (text.isEmpty &&
          (bulk || settledPrerequisites[key]?.isNotEmpty == true)) {
        removedPrerequisites.add(key);
      } else if (prerequisiteValid(key, text)) {
        removedPrerequisites.remove(key);
      }
      settledPrerequisites[key] = text;
    }
    const keys = ['scheduledDate', 'scheduledTime'];
    if (keys.any((key) {
      final range = controllers[key]!.value.composing;
      return range.isValid && !range.isCollapsed;
    })) {
      return;
    }
    if (removedPrerequisites.isNotEmpty && occurrenceBeforeRemoval == null) {
      final hasOccurrence = keys.any(
        (key) =>
            controllers[key]!.text.trim().isNotEmpty ||
            (bulk &&
                !applied.contains(key) &&
                originals.any((task) => scheduleOf(task)[key] != null)),
      );
      if (!hasOccurrence) return;
      dependentEditedAfterRemoval = false;
      occurrenceBeforeRemoval = {
        for (final key in keys) key: controllers[key]!.value,
      };
      occurrenceApplyBeforeRemoval = applied.intersection(keys.toSet());
      changingDependentOccurrence = true;
      try {
        for (final key in keys) {
          controllers[key]!.clear();
          if (bulk) applied.add(key);
        }
      } finally {
        changingDependentOccurrence = false;
      }
      occurrencePrerequisiteNotice =
          'This occurrence cleared for this draft because Due or Repeat was removed. Save to apply; Cancel keeps the saved values.';
      formValidation.draftDependenciesChanged();
      setState(() {});
    } else if (removedPrerequisites.isEmpty &&
        occurrenceBeforeRemoval != null) {
      final preserveChangedDraft = dependentEditedAfterRemoval;
      changingDependentOccurrence = true;
      try {
        if (!preserveChangedDraft) {
          for (final entry in occurrenceBeforeRemoval!.entries) {
            controllers[entry.key]!.value = entry.value;
          }
          if (bulk) {
            applied.removeAll(keys);
            applied.addAll(occurrenceApplyBeforeRemoval!);
          }
        }
      } finally {
        changingDependentOccurrence = false;
      }
      dependentEditedAfterRemoval = false;
      occurrenceBeforeRemoval = null;
      occurrenceApplyBeforeRemoval = null;
      occurrencePrerequisiteNotice = preserveChangedDraft
          ? 'Removal cancelled; your changed This occurrence draft was kept.'
          : 'Removal cancelled; This occurrence restored for this draft.';
      formValidation.draftDependenciesChanged();
      setState(() {});
    }
  }

  ({
    Map<String, dynamic> fields,
    List<String> add,
    List<String> remove,
    Map<String, dynamic> schedule,
    String? assignee,
    Set<String> tags,
  })?
  singleAttempt;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCloseReadinessChanged?.call();
    });
    originals = (jsonDecode(jsonEncode(widget.tasks)) as List)
        .cast<Map<String, dynamic>>();
    final first = originals.first;
    for (final key in ['tags', 'addTags', 'removeTags']) {
      tagSelections[key] = key == 'tags'
          ? Set<String>.from(first['tags'] as List? ?? [])
          : <String>{};
      final query = tagQueries[key] = TextEditingController();
      query.addListener(() {
        if (mounted) {
          lastEditedField = key;
          formValidation.changed(key);
          setState(() => touched.add(key));
        }
      });
    }
    for (final key in [...TaskSchedule.keys, 'title', 'description']) {
      dynamic value = TaskSchedule.keys.contains(key)
          ? scheduleOf(first)[key]
          : first[key];
      if (bulk &&
          TaskSchedule.keys.contains(key) &&
          originals.any((task) => scheduleOf(task)[key] != value)) {
        mixed.add(key);
        value = null;
      }
      controllers[key] = TextEditingController(text: value?.toString() ?? '');
      if (widget.textSession != null &&
          {'title', 'description'}.contains(key)) {
        controllers[key]!.text = widget.textSession!.text(key);
      }
      final controller = controllers[key]!;
      var previousText = controller.text;
      var previousComposing = controller.value.composing;
      controller.addListener(() {
        if (changingDependentOccurrence) {
          previousText = controller.text;
          previousComposing = controller.value.composing;
          return;
        }
        if (key.startsWith('scheduled') &&
            occurrenceBeforeRemoval != null &&
            (controller.text != previousText ||
                controller.value.composing != previousComposing)) {
          dependentEditedAfterRemoval = true;
        }
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
        if (compositionChanged) formValidation.changed(key);
        if (controller.text == previousText) {
          if (key == 'title' && compositionChanged && mounted) setState(() {});
          return;
        }
        previousText = controller.text;
        if (mounted) {
          lastEditedField = key;
          setState(() {
            touched.add(key);
            if (bulk && TaskSchedule.keys.contains(key)) applied.add(key);
          });
          formValidation.changed(key);
        }
      });
    }
    assignee = first['assignee'] as String?;
    if (bulk && originals.any((task) => task['assignee'] != assignee)) {
      assignee = null;
      mixed.add('assignee');
    }
    for (final key in ['dueDate', 'recurrence']) {
      settledPrerequisites[key] = controllers[key]!.text.trim();
    }
    formValidation =
        FormValidation(
          validate: () => validationIssues,
          beforeBlur: settleOccurrencePrerequisites,
          beforeReview: settleOccurrencePrerequisites,
          isComposing: (field) {
            final value = (controllers[field] ?? tagQueries[field])?.value;
            return value != null &&
                value.composing.isValid &&
                !value.composing.isCollapsed;
          },
          beforeReveal: (issue) {
            if (issue.field.startsWith('scheduled')) showOverride = true;
          },
        )..addListener(() {
          if (mounted) setState(() {});
        });
  }

  @override
  void dispose() {
    formValidation.dispose();
    for (final c in tagQueries.values) {
      c.dispose();
    }
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

  List<String> get availableTags {
    final tags = {
      ...widget.tagInventory,
      for (final task in originals)
        ...List<String>.from(task['tags'] as List? ?? []),
    }.toList();
    tags.sort((a, b) {
      final compared = a.toLowerCase().compareTo(b.toLowerCase());
      return compared == 0 ? a.compareTo(b) : compared;
    });
    return tags;
  }

  String tagLabel(String key) => switch (key) {
    'addTags' => 'Add tags',
    'removeTags' => 'Remove tags',
    _ => 'Tags',
  };

  List<String> pendingTags(String key) {
    final query = tagQueries[key]!;
    final composing = query.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      throw FormatException('Finish entering ${tagLabel(key)} before saving.');
    }
    final text = query.text.trim();
    if (availableTags.contains(text)) return [text];
    if (text.startsWith('#') && availableTags.contains(text.substring(1))) {
      return [text.substring(1)];
    }
    final tokens = query.text
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .map((token) => token.startsWith('#') ? token.substring(1) : token)
        .toSet()
        .toList();
    if (key == 'removeTags' &&
        tokens.any((token) => !availableTags.contains(token))) {
      throw const FormatException(
        'Choose existing tags to remove, or clear the query.',
      );
    }
    return tokens;
  }

  List<String> tags(String key) {
    // Existing tag identities stay opaque: only newly typed query is tokenized.
    final result = {...tagSelections[key]!, ...pendingTags(key)}.toList();
    validateTags(result);
    return result;
  }

  String? tagError(String key) {
    try {
      tags(key);
      return null;
    } catch (error) {
      return error is FormatException ? error.message : error.toString();
    }
  }

  void setTags(String key, Set<String> selected) {
    if (editingFrozen) return;
    setState(() {
      tagSelections[key] = Set<String>.of(selected);
      touched.add(key);
    });
  }

  bool submitTagQuery(String key) {
    if (editingFrozen || tagError(key) != null) {
      if (mounted) {
        formValidation.blur(key);
        setState(() => touched.add(key));
      }
      return false;
    }
    final selected = tags(key).toSet();
    setTags(key, selected);
    tagQueries[key]!.clear();
    return true;
  }

  Map<String, dynamic> get patch => {
    for (final key in TaskSchedule.keys)
      if (!bulk || applied.contains(key)) key: value(key),
  };
  List<FieldIssue> get validationIssues {
    final issues = <FieldIssue>[];
    if (!bulk) {
      final title = controllers['title']!;
      if (title.text != originals.first['title'] &&
          title.value.composing.isValid &&
          !title.value.composing.isCollapsed) {
        issues.add(
          const FieldIssue('title', 'Finish entering the title before saving.'),
        );
      } else if (title.text.trim().isEmpty) {
        issues.add(const FieldIssue('title', 'Enter a task title.'));
      } else if (title.text.trim().length > 500) {
        issues.add(
          const FieldIssue('title', 'Title must be 500 characters or fewer.'),
        );
      }
      final notes = controllers['description']!;
      if (notes.value.composing.isValid && !notes.value.composing.isCollapsed) {
        issues.add(
          const FieldIssue(
            'description',
            'Finish entering Notes before saving.',
          ),
        );
      } else if (notes.text.length > 10000) {
        issues.add(
          const FieldIssue(
            'description',
            'Notes must be 10000 characters or fewer.',
          ),
        );
      }
    }
    final parsed = <String, dynamic>{};
    var parseFailed = false;
    for (final key in TaskSchedule.keys) {
      if (bulk && !applied.contains(key)) continue;
      final composing = controllers[key]!.value.composing;
      if (composing.isValid && !composing.isCollapsed) {
        issues.add(
          FieldIssue(key, 'Finish entering this field before saving.'),
        );
        parseFailed = true;
        continue;
      }
      try {
        parsed[key] = value(key);
      } on FormatException catch (error) {
        issues.add(FieldIssue(key, error.message));
        parseFailed = true;
      }
    }
    if (!parseFailed) {
      for (final task in bulk ? originals : [originals.first]) {
        try {
          TaskSchedule.fromJson(
            bulk ? {...scheduleOf(task), ...parsed} : parsed,
          );
        } on ScheduleValidationException catch (error) {
          final fields = error.fields;
          final primary = fields.contains(lastEditedField)
              ? lastEditedField!
              : fields.first;
          issues.add(
            FieldIssue(
              primary,
              error.message,
              relatedFields: fields.where((key) => key != primary).toList(),
            ),
          );
          break;
        }
      }
    }
    if (!occurrenceEditingAllowed &&
        ['scheduledDate', 'scheduledTime'].any(
          (key) =>
              (!bulk || applied.contains(key)) &&
              controllers[key]!.text.trim().isNotEmpty &&
              originals.any(
                (task) =>
                    scheduleOf(task)[key] != controllers[key]!.text.trim(),
              ),
        )) {
      issues.add(
        const FieldIssue(
          'scheduledDate',
          'Set Due and Repeat to edit This occurrence.',
        ),
      );
    }
    for (final key in bulk ? ['addTags', 'removeTags'] : ['tags']) {
      final error = tagError(key);
      if (error != null) issues.add(FieldIssue(key, error));
    }
    return issues;
  }

  BulkTaskEdit get draft => BulkTaskEdit(
    schedulePatch: patch,
    assignee: applyAssignee ? assignee : null,
    addTags: tags('addTags'),
    removeTags: tags('removeTags'),
  );
  bool get dirty {
    if ((bulk ? ['addTags', 'removeTags'] : ['tags']).any(
      (key) => tagQueries[key]!.text.isNotEmpty,
    )) {
      return true;
    }
    if (bulk) {
      return applied.isNotEmpty ||
          applyAssignee ||
          tagSelections['addTags']!.isNotEmpty ||
          tagSelections['removeTags']!.isNotEmpty;
    }
    final first = originals.first;
    return controllers['title']!.text != (first['title'] ?? '') ||
        controllers['description']!.text != (first['description'] ?? '') ||
        !setEquals(
          tagSelections['tags'],
          Set<String>.from(first['tags'] as List? ?? []),
        ) ||
        assignee != first['assignee'] ||
        TaskSchedule.keys.any(
          (key) =>
              controllers[key]!.text !=
              (scheduleOf(first)[key]?.toString() ?? ''),
        );
  }

  Future<bool> canClose() {
    if (helpOpen) return Future.value(false);
    final activeTagComposition = (bulk ? ['addTags', 'removeTags'] : ['tags'])
        .any((key) {
          final composing = tagQueries[key]!.value.composing;
          return composing.isValid && !composing.isCollapsed;
        });
    if (activeTagComposition) {
      setState(() => attempted = true);
      return Future.value(false);
    }
    if (editingFrozen) return Future.value(false);
    if (!dirty) return Future.value(true);
    return closeRequest ??= askClose().whenComplete(() => closeRequest = null);
  }

  Future<bool> askClose() async {
    final choice = await askUnsavedDraft(context);
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
    if (!mounted || busy) return false;
    final retry = widget.textSession?.hasPendingReceipt == true;
    setState(() => attempted = true);
    final submissionRevision = formValidation.submissionRevision;
    if (!retry && !await formValidation.reviewAndReveal()) return false;
    if (!retry && submissionRevision != formValidation.submissionRevision) {
      return false;
    }
    if (!mounted || busy) return false;
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      final committedTags = retry
          ? <String, Set<String>>{'tags': singleAttempt!.tags}
          : {
              for (final key in bulk ? ['addTags', 'removeTags'] : ['tags'])
                key: tags(key).toSet(),
            };
      if (bulk) {
        await widget.saveBulk!(draft);
      } else {
        if (!retry) {
          final first = originals.first;
          if (controllers['title']!.text != first['title']) {
            final title = controllers['title']!;
            title.value = TitleLineFormatter().formatEditUpdate(
              TextEditingValue.empty,
              title.value,
            );
          }
          final parsed = TaskSchedule.fromJson(patch).toJson();
          final originalTags = Set<String>.from(first['tags'] as List? ?? []);
          final desired = committedTags['tags']!;
          final fields = <String, dynamic>{
            if (widget.textSession == null &&
                !widget.disableTextFields &&
                controllers['title']!.text != first['title'])
              'title': controllers['title']!.text.trim(),
            if (widget.textSession == null &&
                !widget.disableTextFields &&
                controllers['description']!.text != first['description'])
              'description': controllers['description']!.text,
            if (assignee != first['assignee']) 'assignee': assignee,
            if (parsed.entries.any(
              (entry) => scheduleOf(first)[entry.key] != entry.value,
            ))
              'schedule': parsed,
          };
          singleAttempt = (
            fields: Map<String, dynamic>.unmodifiable({
              ...fields,
              if (fields.containsKey('schedule'))
                'schedule': Map<String, dynamic>.unmodifiable(parsed),
            }),
            add: List.unmodifiable(desired.difference(originalTags)),
            remove: List.unmodifiable(originalTags.difference(desired)),
            schedule: Map.unmodifiable(parsed),
            assignee: assignee,
            tags: Set.unmodifiable(desired),
          );
        }
        final attempt = singleAttempt!;
        await widget.saveSingle!(attempt.fields, attempt.add, attempt.remove);
      }
      if (!mounted) return false;
      if (widget.textSession?.hasPendingReceipt != true) {
        for (final entry in committedTags.entries) {
          tagSelections[entry.key] = entry.value;
          tagQueries[entry.key]!.clear();
        }
      }
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
        final attempt = singleAttempt!, saved = originals.first;
        saved['title'] = controllers['title']!.text;
        saved['description'] = controllers['description']!.text;
        saved['assignee'] = attempt.assignee;
        saved['tags'] = attempt.tags.toList();
        saved['schedule'] = attempt.schedule;
        assignee = attempt.assignee;
        for (final entry in attempt.schedule.entries) {
          controllers[entry.key]!.text = entry.value?.toString() ?? '';
        }
        touched.clear();
      }
      singleAttempt = null;
      if (widget.textSession?.hasPendingReceipt != true) {
        occurrenceBeforeRemoval = null;
        dependentEditedAfterRemoval = false;
        occurrenceApplyBeforeRemoval = null;
        removedPrerequisites.clear();
        occurrencePrerequisiteNotice = null;
        for (final key in ['dueDate', 'recurrence']) {
          settledPrerequisites[key] = controllers[key]!.text.trim();
        }
      }
      formValidation.reset();
      if (closeAfter) {
        finish();
      } else {
        setState(() => busy = false);
      }
      return true;
    } catch (error) {
      if (widget.textSession?.hasPendingReceipt != true) singleAttempt = null;
      if (mounted) {
        setState(() {
          failure = failureMessage(error);
          busy = false;
        });
      }
      return false;
    } finally {
      if (mounted) widget.onCloseReadinessChanged?.call();
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
    } finally {
      if (mounted) widget.onCloseReadinessChanged?.call();
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
    if (const {'tags', 'addTags', 'removeTags'}.contains(key)) {
      return formValidation.field(
        key,
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TagInput(
            tags: availableTags,
            selected: tagSelections[key]!,
            queryController: tagQueries[key]!,
            queryKey: ValueKey(key),
            label: label,
            queryLabel: label,
            chipContext: label,
            clearLabel: 'Clear $label',
            expandLabel: 'Expand $label options',
            collapseLabel: 'Collapse $label options',
            hint: key == 'removeTags'
                ? 'Find existing tags'
                : 'Find or add tags',
            allowCreate: key != 'removeTags',
            clearQueryOnSelection: true,
            enabled: !editingFrozen,
            queryErrorText: formValidation.errorFor(key),
            onSubmitQuery: () => submitTagQuery(key),
            onChanged: (value) => setTags(key, value),
            onDropdownChanged: (_) {},
          ),
        ),
      );
    }
    final occurrenceLocked =
        key.startsWith('scheduled') && !occurrenceEditingAllowed;
    final dateTimeField = const {
      'startDate',
      'startTime',
      'dueDate',
      'dueTime',
      'scheduledDate',
      'scheduledTime',
    }.contains(key);
    final input = key.endsWith('Date')
        ? CivilDateInput(
            isOwnerMounted: () => mounted,
            fieldKey: ValueKey(key),
            controller: controllers[key]!,
            focusNode: textFocus[key],
            label: label,
            enabled: !editingFrozen && !occurrenceLocked,
            compactDecoration: dateTimeField,
            errorText: formValidation.errorFor(key),
            hint: mixed.contains(key)
                ? 'Mixed — unchanged unless applied'
                : hint,
          )
        : TextField(
            key: ValueKey(key),
            controller: controllers[key],
            focusNode: textFocus[key],
            enabled:
                !editingFrozen &&
                !occurrenceLocked &&
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
              errorText: formValidation.errorFor(key),
              errorMaxLines: 8,
              border: dateTimeField
                  ? const OutlineInputBorder(gapPadding: 2)
                  : null,
              suffixIconConstraints: dateTimeField
                  ? const BoxConstraints(minWidth: 48, minHeight: 48)
                  : null,
              contentPadding: dateTimeField
                  ? const EdgeInsets.fromLTRB(4, 16, 0, 16)
                  : null,
              suffixIcon:
                  const {
                        'startTime',
                        'dueTime',
                        'scheduledTime',
                      }.contains(key) &&
                      controllers[key]!.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear ${clearLabel ?? label}',
                      visualDensity: VisualDensity.standard,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      icon: const Icon(Icons.close),
                      onPressed: editingFrozen || occurrenceLocked
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
    return formValidation.field(
      key,
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: bulk && withApplyControl && TaskSchedule.keys.contains(key)
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  scheduleApply(
                    key,
                    clearLabel ?? label,
                    fullTarget: dateTimeField,
                  ),
                  Expanded(child: input),
                ],
              )
            : key == 'description'
            ? ConstrainedBox(
                constraints: BoxConstraints(maxHeight: notesMaxHeight),
                child: input,
              )
            : input,
      ),
    );
  }

  Widget scheduleApply(String key, String label, {bool fullTarget = false}) =>
      Checkbox(
        semanticLabel: 'Apply $label',
        visualDensity: fullTarget ? VisualDensity.standard : null,
        materialTapTargetSize: fullTarget ? MaterialTapTargetSize.padded : null,
        key: ValueKey('${key}Apply'),
        value: applied.contains(key),
        onChanged:
            editingFrozen ||
                (key.startsWith('scheduled') && occurrenceBeforeRemoval != null)
            ? null
            : (value) => setState(() {
                if (value!) {
                  applied.add(key);
                } else {
                  applied.remove(key);
                }
                formValidation.blur(key);
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

    // 12px leading padding + 4px outline gap + 48px suffix target
    // + 4px Material text-to-suffix gap + 2px caret clearance.
    // A blank Time hint has no clear button, so it uses only padding.
    final dateValueWidth = textWidth('2026-10-04');
    final dateHintWidth = textWidth('YYYY-MM-DD');
    final dateWidth =
        (dateValueWidth > dateHintWidth ? dateValueWidth : dateHintWidth) + 70;
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
        if (bulk) scheduleApply(dateKey, '$label date', fullTarget: true),
        Expanded(flex: 5, child: date),
        const SizedBox(width: 12),
        if (bulk) scheduleApply(timeKey, '$label time', fullTarget: true),
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
      double lineHeight(TextStyle? style) {
        final painter = TextPainter(
          text: TextSpan(text: 'Ag', style: style),
          textDirection: Directionality.of(context),
          textScaler: media.textScaler,
        )..layout();
        final height = painter.height;
        painter.dispose();
        return height;
      }

      // A two-line title, potentially stacked action labels and dialog/input
      // padding need real scaled space. Scroll the full actions with the form
      // below that budget instead of allowing a fixed footer to consume it.
      final styles = Theme.of(context).textTheme;
      modalActionsInContent =
          !widget.panel &&
          availableHeight <
              2 * lineHeight(styles.bodyLarge) +
                  3 * lineHeight(styles.labelLarge) +
                  96;
      notesMaxHeight = (availableHeight * .4).clamp(100.0, 360.0);
      failureMaxHeight = availableHeight * .4;
      // Match the dialog's vertical insets and action padding. Flexible notice
      // space below also accommodates buttons that wrap with enlarged text.
      final failureBodyReserve = modalActionsInContent
          ? lineHeight(styles.bodyLarge) + 8
          : 0.0;
      modalActionsMaxHeight =
          (availableHeight - 48 - media.padding.vertical - failureBodyReserve)
              .clamp(0.0, double.infinity);
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
    final migrationConflicts = [
      for (final task in originals)
        if (planOccurrenceDueMigration(task)?.conflict != null) task,
    ];
    final content = Form(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!bulk) ...[
            field('title', 'Title', lines: 2),
            field('description', 'Notes', lines: 3),
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
          if (migrationConflicts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'This occurrence could not be moved to Due without making the schedule invalid. '
                'Review Start, Due and This occurrence below. All existing values are preserved.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),

          if (!occurrenceEditingAllowed &&
              overrides &&
              migrationConflicts.isEmpty)
            const Text(
              'Set Due and Repeat to edit This occurrence. Existing values are preserved.',
            ),
          if (overrides) ...[
            if (!repeating)
              const Text('Existing occurrence override is preserved.'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (!repeating)
                  TextButton(
                    onPressed: editingFrozen || !occurrenceEditingAllowed
                        ? null
                        : () => setState(() => showOverride = !showOverride),
                    child: const Text('Edit existing override'),
                  ),
                TextButton(
                  onPressed: editingFrozen ? null : clearOccurrenceOverride,
                  child: const Text('Clear override'),
                ),
              ],
            ),
          ],
          if (occurrenceEditingAllowed ||
              overrides ||
              occurrenceBeforeRemoval != null ||
              showOverride ||
              migrationConflicts.isNotEmpty) ...[
            dateTimeRow('scheduled', 'This occurrence'),
          ],
          field(
            'timeZone',
            'Time zone',
            hint: 'Blank: Local; UTC; America/Chicago',
          ),
          const Text('Sort-date bounds'),
          const SizedBox(height: 12),
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
                    semanticLabel: 'Apply Assignee',
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
    final deleteAction = widget.onDelete == null
        ? null
        : TextButton(
            onPressed: editingFrozen ? null : delete,
            child: const Text('Delete'),
          );
    final cancelAction = TextButton(
      onPressed: editingFrozen ? null : close,
      child: const Text('Cancel'),
    );
    final saveAction = ValidationActionButton(
      key: const ValueKey('task-save-action'),
      validation: formValidation,
      enabled: ModalRoute.isCurrentOf(context) ?? true,
      label: 'Save changes',
      busy: busy,
      retry: widget.textSession?.hasPendingReceipt == true,
      onSubmit: submit,
    );
    final actionButtons = bulk && failure != null && modalActionsInContent
        // Give failed bulk actions the full footer width. A fixed Delete
        // column otherwise wraps Save into an extra line and squeezes the
        // readable notice at enlarged phone text.
        ? Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [?deleteAction, cancelAction, saveAction],
          )
        : Row(
            children: [
              ?deleteAction,
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 4,
                  children: [cancelAction, saveAction],
                ),
              ),
            ],
          );
    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (occurrencePrerequisiteNotice != null)
          ConstrainedBox(
            key: const ValueKey('occurrence-prerequisite-notice'),
            constraints: BoxConstraints(maxHeight: failureMaxHeight * .5),
            child: SingleChildScrollView(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  occurrencePrerequisiteNotice!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        actionButtons,
      ],
    );
    final pinBulkFailure = bulk && !widget.panel;
    // A rejected bulk Save must keep its feedback beside the retry/close
    // actions, even when the clean editor uses scrolling actions for space.
    final actionsInContent =
        modalActionsInContent && !(pinBulkFailure && failure != null);
    Widget failureNotice(String message) => Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
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
            IconButton(
              tooltip: 'Task field help',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.help_outline),
              onPressed: busy || helpOpen ? null : openHelp,
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
        if (widget.contextNotice != null) widget.contextNotice!,
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
                  if (failure != null) failureNotice(failure!),
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
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  content,
                  if (actionsInContent) ...[
                    if (failure != null) failureNotice(failure!),
                    actions,
                  ],
                ],
              ),
            ),
            actions: actionsInContent
                ? const []
                : [
                    if (pinBulkFailure && failure != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: modalActionsMaxHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ConstrainedBox(
                                  key: const ValueKey('bulk-save-failure'),
                                  // Long provider errors and enlarged text must leave
                                  // the actions reachable above a small keyboard viewport.
                                  constraints: BoxConstraints(
                                    maxHeight: failureMaxHeight,
                                  ),
                                  child: SingleChildScrollView(
                                    child: failureNotice(failure!),
                                  ),
                                ),
                              ),
                            ),
                            actions,
                          ],
                        ),
                      )
                    else
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (failure != null) failureNotice(failure!),
                          actions,
                        ],
                      ),
                  ],
          );
    final boundedEditor = widget.panel
        ? editor
        : NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              if (notification.depth == 0 &&
                  notification.metrics.axis == Axis.vertical &&
                  modalViewportHeight !=
                      notification.metrics.viewportDimension) {
                modalViewportHeight = notification.metrics.viewportDimension;
                // The Dialog inset animation can resize after the first metrics
                // callback. Reveal the existing caret again at the final bounds.
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => revealFocusedCaret(),
                );
              }
              return false;
            },
            child: editor,
          );
    if (widget.onClose != null) return boundedEditor;
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) close();
      },
      child: boundedEditor,
    );
  }
}
