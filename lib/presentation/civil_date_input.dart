import 'dart:math' as math;
import 'dart:ui' as ui;

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
                  builder: _readableCalendarDays,
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

// The pinned Material3 portrait grid has 12px outer padding and 4px padding
// inside each of seven day cells; DatePickerDialog has 16px side insets.
// Fit localized day numbers to that width without changing the route's scaler,
// header, date semantics, keyboard behavior or full-cell tap targets.
Widget _readableCalendarDays(
  BuildContext context,
  Widget? child,
) => LayoutBuilder(
  builder: (context, constraints) {
    if (child == null) return const SizedBox.shrink();
    if (!Theme.of(context).useMaterial3 ||
        MediaQuery.orientationOf(context) != Orientation.portrait) {
      return child;
    }
    final media = MediaQuery.of(context);
    final dialogScale =
        media.textScaler.clamp(maxScaleFactor: 3).scale(14) / 14;
    final dialogWidth = math.min(constraints.maxWidth - 32, 360 * dialogScale);
    final dialogHeight = math.min(
      constraints.maxHeight -
          media.padding.vertical -
          media.viewInsets.vertical -
          48,
      568 * dialogScale,
    );
    final headerScale = dialogScale.clamp(1.0, 1.4);
    final headerHeight = 120 * (headerScale > 1.3 ? headerScale - .2 : 1);
    final gridScale = media.textScaler.clamp(maxScaleFactor: 2).scale(14) / 14;
    // Pinned SDK: 52px actions, 52px month navigation, seven grid rows.
    final rowHeight = math.min(
      48 + (gridScale > 1.3 ? (gridScale - 1) * 30 : 0),
      (dialogHeight - headerHeight - 104) / 7,
    );
    final dayWidth = (dialogWidth - 24) / 7 - 8 - 2;
    final dayHeight = rowHeight - 8 - 2;
    if (dayWidth <= 0 || dayHeight <= 0) return child;
    final pickerTheme = DatePickerTheme.of(context);
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
      return child;
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
