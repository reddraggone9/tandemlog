import 'package:flutter/material.dart';
import 'form_validation.dart';
import 'focused_dialog_viewport.dart';

class NameEntryDialog extends StatefulWidget {
  const NameEntryDialog({super.key, required this.title, required this.label});
  final String title, label;
  @override
  State<NameEntryDialog> createState() => _NameEntryDialogState();
}

class _NameEntryDialogState extends State<NameEntryDialog> {
  final input = TextEditingController();
  final _focus = FocusNode();
  final _field = GlobalKey();
  late final validation = FormValidation(
    validate: () {
      final name = input.text.trim();
      return [
        if (input.value.composing.isValid && !input.value.composing.isCollapsed)
          const FieldIssue(
            'name',
            'Finish entering your name before creating this user.',
          )
        else if (name.length > 100)
          const FieldIssue('name', 'Name must be 100 characters or fewer.'),
      ];
    },
    isComposing: (_) =>
        input.value.composing.isValid && !input.value.composing.isCollapsed,
  );
  bool closing = false;
  @override
  void initState() {
    super.initState();
    input.addListener(() {
      if (input.text.trim().isEmpty) {
        validation.reset();
      } else {
        validation.changed('name');
      }
    });
  }

  Future<void> submit() async {
    if (closing) return;
    final name = input.text.trim();
    if (name.isEmpty ||
        !await validation.reviewAndReveal() ||
        !mounted ||
        closing ||
        ModalRoute.of(context)?.isCurrent != true ||
        input.text.trim() != name ||
        (input.value.composing.isValid && !input.value.composing.isCollapsed)) {
      return;
    }
    closing = true;
    Navigator.pop(context, name);
  }

  void cancel() {
    if (closing || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    closing = true;
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _focus.dispose();
    validation.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusedDialogViewport(
    focusNode: _focus,
    fieldKey: _field,
    builder: (context, insetPadding) => ListenableBuilder(
      listenable: validation,
      builder: (context, _) => AlertDialog(
        insetPadding: insetPadding,
        alignment: Alignment.bottomCenter,
        title: Text(widget.title),
        scrollable: true,
        content: SizedBox(
          width: 400,
          child: validation.field(
            'name',
            KeyedSubtree(
              key: _field,
              child: TextField(
                focusNode: _focus,
                controller: input,
                autofocus: true,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: widget.label,
                  errorText: validation.errorFor('name'),
                  errorMaxLines: 6,
                  counterText: validation.errorFor('name') == null ? null : '',
                ),
                textInputAction: TextInputAction.done,
                onEditingComplete: () {
                  if (input.text.trim().isEmpty) return;
                  input.clearComposing();
                  _focus.unfocus();
                },
                onSubmitted: (_) => submit(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: cancel, child: const Text('Cancel')),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: input,
            builder: (context, draft, _) => ValidationActionButton(
              validation: validation,
              enabled:
                  !closing &&
                  (ModalRoute.isCurrentOf(context) ?? true) &&
                  draft.text.trim().isNotEmpty,
              label: 'Create user',
              onSubmit: submit,
            ),
          ),
        ],
      ),
    ),
  );
}
