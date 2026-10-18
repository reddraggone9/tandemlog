import 'package:flutter/material.dart';
import 'form_validation.dart';

class DeviceNameChange {
  const DeviceNameChange(this.name);
  final String? name;
}

/// Optional human label, never an installation identity.
class DeviceNameDialog extends StatefulWidget {
  const DeviceNameDialog({super.key, required this.name});
  final String? name;
  @override
  State<DeviceNameDialog> createState() => _DeviceNameDialogState();
}

class _DeviceNameDialogState extends State<DeviceNameDialog> {
  late final controller = TextEditingController(text: widget.name ?? '');
  late final validation = FormValidation(
    validate: () {
      final value = controller.text.trim();
      return [
        if (value.runes.length > 80 ||
            value.runes.any((r) => r < 32 || r == 127))
          const FieldIssue(
            'name',
            'Use up to 80 characters without control characters.',
          ),
      ];
    },
    isComposing: (_) => composing,
  );
  bool answered = false;
  bool get composing =>
      controller.value.composing.isValid &&
      !controller.value.composing.isCollapsed;
  bool get canAnswer =>
      mounted && !answered && (ModalRoute.isCurrentOf(context) ?? false);
  @override
  void initState() {
    super.initState();
    controller.addListener(() => validation.changed('name'));
  }

  Future<void> save() async {
    if (!canAnswer || composing) return;
    if (!await validation.reviewAndReveal() || !mounted || !canAnswer) return;
    final value = controller.text.trim();
    answered = true;
    Navigator.of(context).pop(DeviceNameChange(value.isEmpty ? null : value));
  }

  void cancel() {
    if (!canAnswer) return;
    answered = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    validation.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: validation,
    builder: (context, _) => AlertDialog(
      alignment: Alignment.bottomCenter,
      scrollable: true,
      title: const Text('Device name'),
      content: SizedBox(
        width: 400,
        child: validation.field(
          'name',
          TextField(
            key: const ValueKey('device-name-field'),
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Device name (optional)',
              errorText: validation.errorFor('name'),
              errorMaxLines: 6,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => save(),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: cancel, child: const Text('Cancel')),
        ValidationActionButton(
          buttonKey: const ValueKey('device-name-save'),
          validation: validation,
          label: 'Save',
          enabled: canAnswer,
          onSubmit: save,
        ),
      ],
    ),
  );
}
