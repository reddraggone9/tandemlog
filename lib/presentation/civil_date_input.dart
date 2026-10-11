import 'package:flutter/material.dart';
import '../domain/schedule.dart' show formatCivilDate;

/// A manually editable civil date with the app's calendar picker.
/// Requiredness and validation belong to the containing form.
class CivilDateInput extends StatelessWidget {
  const CivilDateInput({
    super.key,
    required this.controller,
    required this.label,
    this.fieldKey,
    this.focusNode,
    this.enabled = true,
    this.hint = 'YYYY-MM-DD',
    this.errorText,
    this.compactDecoration = true,
  });

  final TextEditingController controller;
  final String label;
  final Key? fieldKey;
  final FocusNode? focusNode;
  final bool enabled;
  final String? hint;
  final String? errorText;
  final bool compactDecoration;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    focusNode: focusNode,
    enabled: enabled,
    decoration: InputDecoration(
      labelText: label,
      border: compactDecoration
          ? const OutlineInputBorder(gapPadding: 2)
          : null,
      suffixIconConstraints: compactDecoration
          ? const BoxConstraints(minWidth: 48, minHeight: 48)
          : null,
      contentPadding: compactDecoration
          ? const EdgeInsets.fromLTRB(4, 16, 0, 16)
          : null,
      suffixIcon: IconButton(
        tooltip: 'Choose $label',
        visualDensity: compactDecoration ? VisualDensity.standard : null,
        padding: compactDecoration ? EdgeInsets.zero : null,
        constraints: compactDecoration
            ? const BoxConstraints(minWidth: 48, minHeight: 48)
            : null,
        icon: const Icon(Icons.calendar_today_outlined),
        onPressed: !enabled
            ? null
            : () async {
                final parsed = DateTime.tryParse(controller.text);
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
                if (chosen != null && context.mounted) {
                  controller.text = formatCivilDate(chosen);
                }
              },
      ),
      hintText: hint,
      errorText: errorText,
    ),
  );
}
