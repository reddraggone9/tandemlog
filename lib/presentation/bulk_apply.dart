import 'package:flutter/material.dart';

/// Hint for a bulk field whose selected items disagree.
const bulkMixedHint = 'Mixed — unchanged unless applied';

/// Shared Tasks/Food bulk-editor Apply control. Only applied fields are
/// written; editing a field applies it, and an applied blank field clears it.
class BulkApplyCheckbox extends StatelessWidget {
  const BulkApplyCheckbox({
    super.key,
    this.checkboxKey,
    required this.label,
    required this.value,
    required this.onChanged,
    this.fullTarget = false,
  });

  /// Placed on the inner [Checkbox] so callers and tests can address it.
  final Key? checkboxKey;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Keeps a 48 px target beside compact date/time inputs.
  final bool fullTarget;

  @override
  Widget build(BuildContext context) => Checkbox(
    key: checkboxKey,
    semanticLabel: 'Apply $label',
    visualDensity: fullTarget ? VisualDensity.standard : null,
    materialTapTargetSize: fullTarget ? MaterialTapTargetSize.padded : null,
    value: value,
    onChanged: onChanged == null ? null : (next) => onChanged!(next ?? false),
  );
}
