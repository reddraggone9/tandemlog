import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../domain/schedule.dart' show formatCivilDate;
import 'calendar_date_picker_fork.dart';

export 'calendar_date_picker_fork.dart' show CivilCalendarDatePicker;
export 'civil_month_year_grids.dart' show CivilMonthGrid, CivilYearGrid;

/// A manually editable civil date with the app's calendar picker.
/// Requiredness and validation belong to the containing form.
class CivilDateInput extends StatelessWidget {
  const CivilDateInput({
    super.key,
    required this.controller,
    required this.label,
    this.fieldKey,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.hint = 'YYYY-MM-DD',
    this.errorText,
    this.compactDecoration = true,
    this.isOwnerMounted,
    this.onPickerChanged,
  });

  final TextEditingController controller;
  final String label;
  final Key? fieldKey;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final String? hint;
  final String? errorText;
  final bool compactDecoration;

  /// Controller-owner lifetime when responsive layout can replace this field.
  /// The owner must retain the controller until it is no longer mounted.
  final bool Function()? isOwnerMounted;

  /// Lets a draft defer navigation until its calendar has finished.
  final ValueChanged<bool>? onPickerChanged;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    focusNode: focusNode,
    autofocus: autofocus,
    enabled: enabled,
    decoration: InputDecoration(
      labelText: label,
      border: compactDecoration ? const OutlineInputBorder() : null,
      suffixIconConstraints: compactDecoration
          ? const BoxConstraints(minWidth: 48, minHeight: 48)
          : null,
      contentPadding: compactDecoration
          ? const EdgeInsetsDirectional.fromSTEB(12, 16, 0, 16)
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
                onPickerChanged?.call(true);
                try {
                  final chosen = await _showFastDatePicker(
                    context: context,
                    initialDate:
                        parsed != null &&
                            parsed.year >= 1900 &&
                            parsed.year <= 9999
                        ? parsed
                        : DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(9999, 12, 31),
                  );
                  if (chosen != null &&
                      (isOwnerMounted?.call() ?? context.mounted)) {
                    controller.text = formatCivilDate(chosen);
                  }
                } finally {
                  onPickerChanged?.call(false);
                }
              },
      ),
      hintText: hint,
      errorText: errorText,
      errorMaxLines: 3,
    ),
  );
}

Future<DateTime?> _showFastDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) => showDialog<DateTime>(
  context: context,
  builder: (_) => CivilDatePickerDialog(
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
  ),
);

class CivilDatePickerDialog extends StatefulWidget {
  CivilDatePickerDialog({
    super.key,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) : initialDate = DateUtils.dateOnly(initialDate),
       firstDate = DateUtils.dateOnly(firstDate),
       lastDate = DateUtils.dateOnly(lastDate);
  final DateTime initialDate, firstDate, lastDate;
  @override
  State<CivilDatePickerDialog> createState() => _CivilDatePickerDialogState();
}

class _CivilDatePickerDialogState extends State<CivilDatePickerDialog> {
  late DateTime date = widget.initialDate;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final scale =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 3).scale(14) /
        14;
    return _readableCalendarDays(
      context,
      Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 360 * scale,
          // Size to the calendar and actions; short screens shrink the grid.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: CivilCalendarDatePicker(
                  initialDate: date,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  onDateChanged: (value) => setState(() => date = value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(localizations.cancelButtonLabel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, date),
                      child: Text(localizations.okButtonLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      verticalInsets: 32,
    );
  }
}

// The pinned Material3 portrait grid has 12px outer padding and 4px padding
// inside each of seven day cells; the app dialog retains 16px side insets.
// Fit localized day numbers to that width without changing the route's scaler,
// header, date semantics, keyboard behavior or full-cell tap targets.
Widget _readableCalendarDays(
  BuildContext context,
  Widget? child, {
  double verticalInsets = 48,
}) => LayoutBuilder(
  builder: (context, constraints) {
    if (child == null) return const SizedBox.shrink();
    final pickerTheme = DatePickerTheme.of(context);
    // Keep this wrapper when fitting switches off, so a resize cannot replace
    // the dialog's state and discard the user's pending date or open menu.
    Widget unchanged() => DatePickerTheme(data: pickerTheme, child: child);
    if (!Theme.of(context).useMaterial3 ||
        MediaQuery.orientationOf(context) != Orientation.portrait) {
      return unchanged();
    }
    final media = MediaQuery.of(context);
    final dialogScale =
        media.textScaler.clamp(maxScaleFactor: 3).scale(14) / 14;
    final dialogWidth = math.min(constraints.maxWidth - 32, 360 * dialogScale);
    // Mirror the forked picker's portrait geometry: a 52px month/year header
    // over seven grid rows that grow past 1.3x text, inside a dialog that
    // shrinks the grid when the actions would not otherwise fit. Reserve the
    // actions' 48px tap targets or their scaled label, plus 16px padding.
    final enlarged = dialogScale > 1.3 ? dialogScale - 1 : 0.0;
    final available =
        constraints.maxHeight -
        media.padding.vertical -
        media.viewInsets.vertical -
        verticalInsets -
        16 -
        math.max(48, 20 * dialogScale + 16) -
        52;
    final rowHeight = math.min(
      48 + enlarged * 30,
      math.min(336 + 7 * enlarged * 8, available) / 7,
    );
    final dayWidth = (dialogWidth - 24) / 7 - 8 - 2;
    final dayHeight = rowHeight - 8 - 2;
    if (dayWidth <= 0 || dayHeight <= 0) return unchanged();
    final defaults = DatePickerTheme.defaults(context).dayStyle!;
    final style = defaults.merge(pickerTheme.dayStyle);
    final fontSize = style.fontSize ?? defaults.fontSize!;
    final localizations = MaterialLocalizations.of(context);
    // This mirrors the existing SDK portrait-grid clamp, without installing
    // another clamp or changing the user's MediaQuery.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2);
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: scaler,
      locale: Localizations.localeOf(context),
      maxLines: 1,
    );
    bool fits(TextStyle candidate) {
      for (var day = 1; day <= 31; day++) {
        final label = localizations.formatDecimal(day);
        painter.text = TextSpan(text: label, style: candidate);
        painter.layout();
        if (painter.width > dayWidth || painter.height > dayHeight) {
          return false;
        }
        final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: label.length),
        );
        for (final box in boxes) {
          if (box.bottom - box.top > dayHeight) return false;
        }
      }
      return true;
    }

    if (fits(style)) {
      painter.dispose();
      return unchanged();
    }
    // Numeric days use their actual font metrics rather than prose leading.
    final fittedStyle = style.copyWith(height: ui.kTextHeightNone);
    var low = 0.0;
    var high = fontSize;
    for (var step = 0; step < 12; step++) {
      final middle = (low + high) / 2;
      if (fits(fittedStyle.copyWith(fontSize: middle))) {
        low = middle;
      } else {
        high = middle;
      }
    }
    painter.dispose();
    return DatePickerTheme(
      data: pickerTheme.copyWith(dayStyle: fittedStyle.copyWith(fontSize: low)),
      child: child,
    );
  },
);
