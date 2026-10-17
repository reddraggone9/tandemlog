import 'dart:async';

import 'package:flutter/material.dart';

/// A form issue names inputs directly; navigation never parses an error string.
class FieldIssue {
  const FieldIssue(this.field, this.message, {this.relatedFields = const []});
  final String field, message;
  final List<String> relatedFields;
  bool concerns(String name) => field == name || relatedFields.contains(name);
}

/// Presentation state only. Commands retain their own final validation gates.
class FormValidation extends ChangeNotifier {
  FormValidation({
    required this.validate,
    this.isComposing,
    this.beforeReveal,
    this.beforeBlur,
    this.beforeReview,
  });
  final List<FieldIssue> Function() validate;
  final bool Function(String field)? isComposing;
  final void Function(FieldIssue issue)? beforeReveal;
  final void Function(String field)? beforeBlur;
  final VoidCallback? beforeReview;
  int _submissionRevision = 0;
  int get submissionRevision => _submissionRevision;

  /// A dependent draft change must be presented before an in-flight Save writes.
  void draftDependenciesChanged() {
    _submissionRevision++;
  }

  final _revealed = <String>{};
  final _anchors = <String, GlobalKey>{};
  List<FieldIssue> _issues = const [];
  bool _reviewRequired = false, _reviewedAll = false, _disposed = false;

  bool get reviewRequired => _reviewRequired;

  FocusNode? _lastInputFocus;

  /// Mouse activation can focus Help before its callback. Remember only an
  /// attached input still owned by one of this form's current field anchors.
  FocusNode? get lastInputFocus {
    final focus = _lastInputFocus;
    if (focus?.context?.mounted != true || !focus!.canRequestFocus) return null;
    return _anchors.values.any(
          (anchor) => identical(
            _editableAt(anchor.currentContext)?.widget.focusNode,
            focus,
          ),
        )
        ? focus
        : null;
  }

  EditableTextState? _editableAt(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    EditableTextState? editable;
    void findInput(Element element) {
      if (editable != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        editable = element.state as EditableTextState;
      } else {
        element.visitChildElements(findInput);
      }
    }

    context.visitChildElements(findInput);
    return editable;
  }

  String? errorFor(String field) {
    if (!_revealed.contains(field)) return null;
    for (final issue in _issues) {
      if (issue.field == field) return issue.message;
    }
    return null;
  }

  /// Once shown, an error can clear as it is corrected. The action's intent
  /// settles on blur/review, rather than flickering during partial input/IME.
  void changed(String field) {
    if ((!_revealed.contains(field) &&
            !_issues.any(
              (issue) =>
                  issue.concerns(field) && _revealed.contains(issue.field),
            )) ||
        isComposing?.call(field) == true) {
      return;
    }
    _issues = validate();
    if (_reviewedAll) {
      for (final issue in _issues) {
        _revealed.addAll([issue.field, ...issue.relatedFields]);
      }
    }
    notifyListeners();
  }

  void blur(String field) {
    if (isComposing?.call(field) == true) return;
    beforeBlur?.call(field);
    _revealed.add(field);
    _issues = validate();
    for (final issue in _issues) {
      if (issue.concerns(field)) _revealed.add(issue.field);
    }
    if (_reviewedAll) {
      for (final issue in _issues) {
        _revealed.addAll([issue.field, ...issue.relatedFields]);
      }
    }
    _reviewRequired = _issues.any((issue) => _revealed.any(issue.concerns));
    notifyListeners();
  }

  Widget field(String name, Widget child) => KeyedSubtree(
    key: _anchors.putIfAbsent(name, GlobalKey.new),
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused) {
          final input = _editableAt(_anchors[name]?.currentContext);
          if (input?.widget.focusNode.hasFocus == true) {
            _lastInputFocus = input!.widget.focusNode;
          }
        }
        // Focus notifications can arrive while the form is building/disposed.
        if (!focused) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_disposed && _anchors[name]?.currentContext != null) {
              blur(name);
            }
          });
        }
      },
      child: child,
    ),
  );

  /// Returns true only for valid input. Review callers never submit even when
  /// this returns true: a review gesture cannot become a save under the pointer.
  Future<bool> reviewAndReveal() async {
    if (_disposed) return false;
    beforeReview?.call();
    _reviewedAll = true;
    _issues = validate();
    for (final issue in _issues) {
      _revealed.addAll([issue.field, ...issue.relatedFields]);
    }
    _reviewRequired = _issues.isNotEmpty;
    if (_issues.isNotEmpty) beforeReveal?.call(_issues.first);
    notifyListeners();
    if (_issues.isEmpty) return true;
    final first = _issues.first;
    await WidgetsBinding.instance.endOfFrame;
    if (_disposed) return false;
    final context = _anchors[first.field]?.currentContext;
    if (context == null || !context.mounted) return false;
    _editableAt(context)?.widget.focusNode.requestFocus();
    await WidgetsBinding.instance.endOfFrame;
    if (_disposed || !context.mounted) return false;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 180),
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    return false;
  }

  void reset() {
    _revealed.clear();
    _issues = const [];
    _reviewRequired = false;
    _reviewedAll = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lastInputFocus = null;
    super.dispose();
  }
}

enum FormActionIntent { submit, review, retry }

/// One stable button keeps pointer/keyboard focus through validation changes.
class ValidationActionButton extends StatefulWidget {
  const ValidationActionButton({
    super.key,
    required this.validation,
    required this.label,
    required this.onSubmit,
    this.buttonKey,
    this.busy = false,
    this.retry = false,
    this.enabled = true,
    this.busyLabel = 'Saving…',
    this.retryLabel = 'Retry Save',
  });
  final Key? buttonKey;
  final FormValidation validation;
  final String label, busyLabel, retryLabel;
  final FutureOr<void> Function() onSubmit;
  final bool busy, retry, enabled;
  @override
  State<ValidationActionButton> createState() => _ValidationActionButtonState();
}

class _ValidationActionButtonState extends State<ValidationActionButton> {
  FormActionIntent? _pressedIntent;
  int? _pressedRevision;
  bool _activating = false;
  FormActionIntent get _intent => widget.retry
      ? FormActionIntent.retry
      : widget.validation.reviewRequired
      ? FormActionIntent.review
      : FormActionIntent.submit;

  Future<void> _activate() async {
    if (!mounted || _activating || widget.busy || !widget.enabled) return;
    _activating = true;
    final intent = _pressedIntent ?? _intent;
    final revision = _pressedRevision ?? widget.validation.submissionRevision;
    _pressedIntent = null;
    _pressedRevision = null;
    try {
      if (intent == FormActionIntent.retry) {
        await widget.onSubmit();
        return;
      }
      final valid = await widget.validation.reviewAndReveal();
      if (!mounted ||
          widget.busy ||
          !widget.enabled ||
          revision != widget.validation.submissionRevision ||
          intent == FormActionIntent.review ||
          !valid) {
        return;
      }
      await widget.onSubmit();
    } finally {
      _activating = false;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.validation,
    builder: (context, _) => Listener(
      onPointerDown: (event) {
        if (event.buttons == 1) {
          _pressedIntent = _intent;
          _pressedRevision = widget.validation.submissionRevision;
        }
      },
      onPointerUp: (_) => WidgetsBinding.instance.addPostFrameCallback((_) {
        _pressedIntent = null;
        _pressedRevision = null;
      }),
      onPointerCancel: (_) {
        _pressedIntent = null;
        _pressedRevision = null;
      },
      child: FilledButton(
        key: widget.buttonKey,
        onPressed: widget.busy || !widget.enabled ? null : _activate,
        child: Builder(
          builder: (context) => Stack(
            alignment: Alignment.center,
            children: [
              for (final label in {
                widget.label,
                'Review errors',
                widget.retryLabel,
                widget.busyLabel,
              })
                ExcludeSemantics(
                  child: Opacity(
                    opacity: 0,
                    child: RichText(
                      text: TextSpan(
                        text: label,
                        style: DefaultTextStyle.of(context).style,
                      ),
                      textScaler: MediaQuery.textScalerOf(context),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              Text(
                widget.busy
                    ? widget.busyLabel
                    : switch (_intent) {
                        FormActionIntent.retry => widget.retryLabel,
                        FormActionIntent.review => 'Review errors',
                        FormActionIntent.submit => widget.label,
                      },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
