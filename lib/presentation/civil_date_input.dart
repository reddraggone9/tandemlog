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
  late DateTime calendarSeed = date;
  late DateTime displayedMonth = date;
  bool inputMode = false;
  final inputForm = GlobalKey<FormState>();
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  Future<void> jump() async {
    var year = displayedMonth.year;
    var choosingYear = false;
    final chosen = await showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Month / year'),
          scrollable: true,
          content: SizedBox(
            width: 320,
            height: 320,
            child: Column(
              children: [
                TextButton.icon(
                  onPressed: () => update(() => choosingYear = !choosingYear),
                  icon: const Icon(Icons.arrow_drop_down),
                  label: Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatYear(DateTime(year)),
                  ),
                ),
                Expanded(
                  child: choosingYear
                      ? YearPicker(
                          firstDate: widget.firstDate,
                          lastDate: widget.lastDate,
                          selectedDate: DateTime(year),
                          onChanged: (value) => update(() {
                            year = value.year;
                            choosingYear = false;
                          }),
                        )
                      : GridView.count(
                          crossAxisCount: 3,
                          childAspectRatio: 1.25,
                          children: [
                            for (var month = 1; month <= 12; month++)
                              TextButton(
                                onPressed: () => Navigator.pop(
                                  context,
                                  DateTime(year, month),
                                ),
                                child: Semantics(
                                  label: MaterialLocalizations.of(
                                    context,
                                  ).formatMonthYear(DateTime(year, month)),
                                  excludeSemantics: true,
                                  child: Text(_months[month - 1]),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || chosen == null) return;
    final day = math.min(
      date.day,
      DateTime(chosen.year, chosen.month + 1, 0).day,
    );
    setState(() {
      date = DateTime(chosen.year, chosen.month, day);
      calendarSeed = date;
      displayedMonth = date;
    });
  }

  void confirm() {
    if (inputMode) {
      if (!(inputForm.currentState?.validate() ?? false)) return;
      inputForm.currentState!.save();
    }
    Navigator.pop(context, date);
  }

  void toggleInput() {
    if (inputMode) {
      if (!(inputForm.currentState?.validate() ?? false)) return;
      inputForm.currentState!.save();
    }
    setState(() {
      inputMode = !inputMode;
      calendarSeed = date;
      displayedMonth = date;
    });
  }

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
          height: 568 * scale,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: inputMode
                            ? Text(localizations.datePickerHelpText)
                            : TextButton.icon(
                                onPressed: jump,
                                icon: const Icon(Icons.calendar_month),
                                label: const Text('Month / year'),
                              ),
                      ),
                    ),
                    IconButton(
                      tooltip: inputMode
                          ? localizations.calendarModeButtonLabel
                          : localizations.inputDateModeButtonLabel,
                      onPressed: toggleInput,
                      icon: Icon(
                        inputMode ? Icons.calendar_today : Icons.edit_outlined,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: inputMode
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: inputForm,
                          child: InputDatePickerFormField(
                            initialDate: date,
                            firstDate: widget.firstDate,
                            lastDate: widget.lastDate,
                            autofocus: true,
                            onDateSaved: (value) => date = value,
                            onDateSubmitted: (_) => confirm(),
                          ),
                        ),
                      )
                    : CalendarDatePicker(
                        key: ValueKey(calendarSeed),
                        initialDate: date,
                        firstDate: widget.firstDate,
                        lastDate: widget.lastDate,
                        onDateChanged: (value) => setState(() => date = value),
                        onDisplayedMonthChanged: (value) =>
                            displayedMonth = value,
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
                      onPressed: confirm,
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
    // the dialog's state and discard the user's pending date or input mode.
    Widget unchanged() => DatePickerTheme(data: pickerTheme, child: child);
    if (!Theme.of(context).useMaterial3 ||
        MediaQuery.orientationOf(context) != Orientation.portrait) {
      return unchanged();
    }
    final media = MediaQuery.of(context);
    final dialogScale =
        media.textScaler.clamp(maxScaleFactor: 3).scale(14) / 14;
    final dialogWidth = math.min(constraints.maxWidth - 32, 360 * dialogScale);
    final dialogHeight = math.min(
      constraints.maxHeight -
          media.padding.vertical -
          media.viewInsets.vertical -
          verticalInsets,
      568 * dialogScale,
    );
    final headerScale = dialogScale.clamp(1.0, 1.4);
    final headerHeight = 120 * (headerScale > 1.3 ? headerScale - .2 : 1);
    final gridScale = media.textScaler.clamp(maxScaleFactor: 2).scale(14) / 14;
    // Conservatively reserve the SDK header plus 52px actions/navigation and
    // seven grid rows; the app header is no taller.
    final rowHeight = math.min(
      48 + (gridScale > 1.3 ? (gridScale - 1) * 30 : 0),
      (dialogHeight - headerHeight - 104) / 7,
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
