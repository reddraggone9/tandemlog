import 'package:flutter/material.dart';
import 'form_validation.dart';

class NameEntryDialog extends StatefulWidget {
  const NameEntryDialog({super.key, required this.title, required this.label});
  final String title, label;
  @override
  State<NameEntryDialog> createState() => _NameEntryDialogState();
}

class _NameEntryDialogState extends State<NameEntryDialog> {
  final input = TextEditingController();
  late final validation = FormValidation(
    validate: () {
      final name = input.text.trim();
      return [
        if (input.value.composing.isValid && !input.value.composing.isCollapsed)
          const FieldIssue(
            'name',
            'Finish entering your name before creating this user.',
          )
        else if (name.isEmpty)
          const FieldIssue('name', 'Enter a name.')
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
    input.addListener(() => validation.changed('name'));
  }

  Future<void> submit() async {
    if (closing ||
        !await validation.reviewAndReveal() ||
        !mounted ||
        closing ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    closing = true;
    Navigator.pop(context, input.text.trim());
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
    validation.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: validation,
    builder: (context, _) => AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: validation.field(
        'name',
        TextField(
          controller: input,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: validation.errorFor('name'),
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => submit(),
        ),
      ),
      actions: [
        TextButton(onPressed: cancel, child: const Text('Cancel')),
        ValidationActionButton(
          validation: validation,
          enabled: !closing && (ModalRoute.isCurrentOf(context) ?? true),
          label: 'Create user',
          onSubmit: submit,
        ),
      ],
    ),
  );
}
