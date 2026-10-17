import 'package:flutter/material.dart';
import '../application/task_text_session.dart';
import 'failure_message.dart';
import 'form_validation.dart';
import 'title_line_formatter.dart';
import 'unsaved_draft_dialog.dart';

class ChecklistItemEditor extends StatefulWidget {
  const ChecklistItemEditor({
    super.key,
    this.item,
    this.textSession,
    required this.save,
    this.hasPendingReceipt,
    this.onClose,
    this.onCloseReadinessChanged,
  });
  final Map<String, dynamic>? item;
  final TaskTextSession? textSession;
  final Future<void> Function(String title, String notes) save;
  final bool Function()? hasPendingReceipt;
  final VoidCallback? onClose, onCloseReadinessChanged;
  @override
  ChecklistItemEditorState createState() => ChecklistItemEditorState();
}

class ChecklistItemEditorState extends State<ChecklistItemEditor> {
  late final TextEditingController _title, _notes;
  final _titleFocus = FocusNode(), _notesFocus = FocusNode();
  final _titleField = GlobalKey(), _notesField = GlobalKey();
  final _notesScroll = ScrollController();
  late String _savedTitle, _savedNotes;
  bool _busy = false, _allowPop = false, _refreshing = false;
  String? _failure;
  late final FormValidation _formValidation;
  String? _attemptTitle, _attemptNotes;
  Future<bool>? _closeRequest;
  Object? _geometry;
  bool get _pending =>
      widget.hasPendingReceipt?.call() == true ||
      widget.textSession?.hasPendingReceipt == true;
  bool get _frozen => _busy || _pending || widget.textSession?.frozen == true;
  // Private preparation is discardable until immutable bytes have a receipt.
  bool get closeBusy => _busy;
  bool get _closeBlocked => _busy || _pending;
  bool get _dirty => _title.text != _savedTitle || _notes.text != _savedNotes;

  @override
  void initState() {
    super.initState();
    _savedTitle =
        widget.textSession?.text('title') ??
        widget.item?['title'] as String? ??
        '';
    _savedNotes =
        widget.textSession?.text('description') ??
        widget.item?['description'] as String? ??
        '';
    _title = TextEditingController(text: _savedTitle);
    _notes = TextEditingController(text: _savedNotes);
    _formValidation = FormValidation(
      validate: _issues,
      isComposing: (field) {
        final value = (field == 'title' ? _title : _notes).value;
        return value.composing.isValid && !value.composing.isCollapsed;
      },
    )..addListener(_validationChanged);
    _listen(_title, 'title');
    _listen(_notes, 'description');
  }

  void _listen(TextEditingController controller, String field) {
    var text = controller.text;
    var composing = controller.value.composing;
    controller.addListener(() {
      final value = controller.value;
      final changed = value.text != text || value.composing != composing;
      text = value.text;
      composing = value.composing;
      if (!changed || _refreshing) return;
      final session = widget.textSession;
      if (session != null && !session.frozen) {
        session.replace(
          field,
          value.text,
          composing: value.composing.isValid && !value.composing.isCollapsed,
        );
      }
      _formValidation.changed(field);
      if (mounted) setState(() {});
    });
  }

  void _validationChanged() {
    if (mounted) setState(() {});
  }

  List<FieldIssue> _issues() {
    final issues = <FieldIssue>[];
    for (final (field, controller) in [
      ('title', _title),
      ('description', _notes),
    ]) {
      final value = controller.value;
      if (value.composing.isValid && !value.composing.isCollapsed) {
        issues.add(FieldIssue(field, 'Finish entering text before saving.'));
      } else if (field == 'title') {
        if (value.text.trim().isEmpty) {
          issues.add(
            const FieldIssue('title', 'Enter a checklist item title.'),
          );
        } else if (value.text.trim().length > 500) {
          issues.add(
            const FieldIssue('title', 'Title must be 500 characters or fewer.'),
          );
        }
      } else if (value.text.length > 10000) {
        issues.add(
          const FieldIssue(
            'description',
            'Notes must be 10000 characters or fewer.',
          ),
        );
      }
    }
    return issues;
  }

  /// Resolves a private draft without closing the host route or owning a session.
  Future<bool> canClose() {
    if (_closeBlocked) return Future.value(false);
    if (!_dirty) return Future.value(true);
    return _closeRequest ??= _askClose().whenComplete(
      () => _closeRequest = null,
    );
  }

  Future<bool> _askClose() async {
    final choice = await askUnsavedDraft(context);
    if (!mounted || _closeBlocked) return false;
    if (choice == 'discard') return true;
    if (choice == 'save') return _commit(closeAfter: false);
    return false;
  }

  void _finish() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      setState(() => _allowPop = true);
      Navigator.pop(context);
    }
  }

  Future<void> _close() async {
    if (await canClose() && mounted) _finish();
  }

  Future<bool> _commit({required bool closeAfter}) async {
    if (!mounted || _busy) return false;
    // A prepared receipt retries the captured intent. Do not normalize again.
    if (!_pending && widget.textSession?.frozen != true) {
      if (!await _formValidation.reviewAndReveal()) return false;
      if (!mounted || _busy) return false;
      if (_title.text != _savedTitle) {
        _title.value = TitleLineFormatter().formatEditUpdate(
          TextEditingValue.empty,
          _title.value,
        );
      }
    }
    if (!_pending && widget.textSession?.frozen != true) {
      _attemptTitle = _title.text.trim();
      _attemptNotes = _notes.text;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.save(
        _attemptTitle ?? _title.text.trim(),
        _attemptNotes ?? _notes.text,
      );
      if (!mounted) return false;
      final session = widget.textSession;
      if (session != null && !session.frozen) {
        _refreshing = true;
        try {
          for (final entry in {
            'title': _title,
            'description': _notes,
          }.entries) {
            final text = session.text(entry.key);
            final controller = entry.value;
            if (controller.text == text) continue;
            controller.value = TextEditingValue(
              text: text,
              selection: TextSelection(
                baseOffset: controller.selection.baseOffset.clamp(
                  0,
                  text.length,
                ),
                extentOffset: controller.selection.extentOffset.clamp(
                  0,
                  text.length,
                ),
              ),
            );
          }
        } finally {
          _refreshing = false;
        }
      }
      _savedTitle = _title.text;
      _savedNotes = _notes.text;
      setState(() {
        _busy = false;
      });
      if (closeAfter) _finish();
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = failureMessage(error);
        });
      }
      return false;
    } finally {
      if (mounted) widget.onCloseReadinessChanged?.call();
    }
  }

  void _revealCaret() {
    final key = _titleFocus.hasFocus
        ? _titleField
        : _notesFocus.hasFocus
        ? _notesField
        : null;
    final controller = _titleFocus.hasFocus ? _title : _notes;
    if (key?.currentContext == null || !controller.selection.isValid) return;
    void visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        (element.state as EditableTextState).bringIntoView(
          controller.selection.extent,
        );
      } else {
        element.visitChildren(visit);
      }
    }

    (key!.currentContext! as Element).visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final geometry = (media.size, media.viewInsets, media.textScaler.scale(14));
    if (geometry != _geometry) {
      _geometry = geometry;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealCaret();
      });
    }
    final visibleHeight =
        (media.size.height -
                media.viewInsets.bottom -
                media.viewPadding.vertical -
                48)
            .clamp(120.0, 800.0);
    final notesHeight = (visibleHeight * .30).clamp(90.0, 280.0);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 480, maxHeight: visibleHeight),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.item == null
                              ? 'Add checklist item'
                              : 'Edit checklist item',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        _formValidation.field(
                          'title',
                          KeyedSubtree(
                            key: _titleField,
                            child: TextField(
                              key: const Key('checklist-item-title'),
                              controller: _title,
                              focusNode: _titleFocus,
                              enabled: !_frozen,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.next,
                              minLines: 1,
                              maxLines: 2,
                              inputFormatters: [TitleLineFormatter()],
                              decoration: InputDecoration(
                                errorText: _formValidation.errorFor('title'),
                                errorMaxLines: 3,
                                label: const Text(
                                  'Title',
                                  semanticsLabel: 'Checklist item title',
                                ),
                              ),
                              onSubmitted: (_) => _notesFocus.requestFocus(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _formValidation.field(
                          'description',
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: notesHeight),
                            child: KeyedSubtree(
                              key: _notesField,
                              child: TextField(
                                key: const Key('checklist-item-notes'),
                                controller: _notes,
                                focusNode: _notesFocus,
                                scrollController: _notesScroll,
                                enabled: !_frozen,
                                keyboardType: TextInputType.multiline,
                                minLines: 3,
                                maxLines: null,
                                decoration: InputDecoration(
                                  errorText: _formValidation.errorFor(
                                    'description',
                                  ),
                                  errorMaxLines: 3,
                                  label: const Text(
                                    'Notes (optional)',
                                    semanticsLabel:
                                        'Checklist item notes (optional)',
                                  ),
                                  alignLabelWithHint: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_failure != null || _pending)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (visibleHeight * .22).clamp(40.0, 120.0),
                      ),
                      child: SingleChildScrollView(
                        child: Semantics(
                          liveRegion: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_failure != null)
                                Text(
                                  _failure!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              if (_pending)
                                const Text(
                                  'Save is pending. Retry to finish saving this item.',
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                OverflowBar(
                  spacing: 8,
                  overflowSpacing: 8,
                  alignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('checklist-item-cancel'),
                      onPressed: _closeBlocked ? null : _close,
                      child: const Text('Cancel'),
                    ),
                    ValidationActionButton(
                      buttonKey: const Key('checklist-item-save'),
                      validation: _formValidation,
                      busy: _busy,
                      enabled: ModalRoute.isCurrentOf(context) ?? true,
                      retry: _pending || widget.textSession?.frozen == true,
                      label: 'Save item',
                      onSubmit: () async {
                        await _commit(closeAfter: true);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _formValidation.dispose();
    _title.dispose();
    _notes.dispose();
    _titleFocus.dispose();
    _notesFocus.dispose();
    _notesScroll.dispose();
    super.dispose();
  }
}
