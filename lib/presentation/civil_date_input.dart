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
      hintMaxLines: 2,
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

  bool monthMode = false;
  bool choosingYear = false;
  late int jumpYear = displayedMonth.year;
  LocalHistoryEntry? jumpHistory;

  void jump() {
    if (monthMode) {
      jumpHistory?.remove();
      return;
    }
    setState(() {
      jumpYear = displayedMonth.year;
      choosingYear = false;
      monthMode = true;
    });
    jumpHistory = LocalHistoryEntry(
      onRemove: () {
        jumpHistory = null;
        if (mounted) setState(() => monthMode = false);
      },
    );
    ModalRoute.of(context)!.addLocalHistoryEntry(jumpHistory!);
  }

  void chooseMonth(int month) {
    final day = math.min(date.day, DateTime(jumpYear, month + 1, 0).day);
    final chosen = DateTime(jumpYear, month, day);
    setState(() {
      date = chosen.isBefore(widget.firstDate)
          ? widget.firstDate
          : chosen.isAfter(widget.lastDate)
          ? widget.lastDate
          : chosen;
      calendarSeed = date;
      displayedMonth = date;
    });
    jumpHistory!.remove();
  }

  Widget monthGrid(BuildContext context) => Column(
    children: [
      TextButton.icon(
        onPressed: () => setState(() => choosingYear = !choosingYear),
        icon: const Icon(Icons.arrow_drop_down),
        label: Text(
          MaterialLocalizations.of(context).formatYear(DateTime(jumpYear)),
        ),
      ),
      Expanded(
        child: choosingYear
            ? CivilYearGrid(
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                selectedDate: DateTime(jumpYear),
                onChanged: (value) => setState(() {
                  jumpYear = value.year;
                  choosingYear = false;
                }),
              )
            : LayoutBuilder(
                builder: (context, constraints) => GridView.count(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  crossAxisCount: 3,
                  childAspectRatio:
                      (constraints.maxWidth - 24) /
                      3 /
                      math.max(48, constraints.maxHeight / 4),
                  children: [
                    for (var month = 1; month <= 12; month++)
                      TextButton(
                        onPressed:
                            DateTime(
                                  jumpYear,
                                  month + 1,
                                  0,
                                ).isBefore(widget.firstDate) ||
                                DateTime(
                                  jumpYear,
                                  month,
                                ).isAfter(widget.lastDate)
                            ? null
                            : () => chooseMonth(month),
                        child: Semantics(
                          label: MaterialLocalizations.of(
                            context,
                          ).formatMonthYear(DateTime(jumpYear, month)),
                          excludeSemantics: true,
                          child: Text(_months[month - 1]),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    ],
  );

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
                                icon: Icon(
                                  monthMode
                                      ? Icons.arrow_back
                                      : Icons.calendar_month,
                                ),
                                label: Text(
                                  monthMode ? 'Calendar' : 'Month / year',
                                ),
                              ),
                      ),
                    ),
                    if (!monthMode)
                      IconButton(
                        tooltip: inputMode
                            ? localizations.calendarModeButtonLabel
                            : localizations.inputDateModeButtonLabel,
                        onPressed: toggleInput,
                        icon: Icon(
                          inputMode
                              ? Icons.calendar_today
                              : Icons.edit_outlined,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: monthMode
                    ? monthGrid(context)
                    : inputMode
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
                      onPressed: () {
                        jumpHistory?.remove();
                        Navigator.pop(context);
                      },
                      child: Text(localizations.cancelButtonLabel),
                    ),
                    if (!monthMode)
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

/// App-owned year geometry keeps the selected year visible at enlarged text.
/// Material YearPicker's initial offset assumes three columns even when its
/// own large-text layout switches to two. Keep public scrolling/focus APIs.
class CivilYearGrid extends StatefulWidget {
  const CivilYearGrid({
    super.key,
    required this.firstDate,
    required this.lastDate,
    required this.selectedDate,
    required this.onChanged,
  });
  final DateTime firstDate, lastDate, selectedDate;
  final ValueChanged<DateTime> onChanged;
  @override
  State<CivilYearGrid> createState() => _CivilYearGridState();
}

class _CivilYearGridState extends State<CivilYearGrid> {
  ScrollController? controller;
  (int, double, double)? geometry;
  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final columns =
          (constraints.maxWidth / math.max(104, scaler.scale(18) * 4))
              .floor()
              .clamp(1, 3);
      final minimumRowHeight = math.max(48.0, scaler.scale(20) + 24);
      final visibleRows = math.max(
        1,
        (constraints.maxHeight / minimumRowHeight).floor(),
      );
      final rowHeight = constraints.maxHeight / visibleRows;
      final nextGeometry = (columns, rowHeight, constraints.maxHeight);
      final count = widget.lastDate.year - widget.firstDate.year + 1;
      final selectedRow =
          (widget.selectedDate.year - widget.firstDate.year) ~/ columns;
      final offset = math.max(
        0.0,
        (selectedRow - visibleRows ~/ 2) * rowHeight,
      );
      controller ??= ScrollController(initialScrollOffset: offset);
      if (geometry != null && geometry != nextGeometry) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && controller!.hasClients) {
            controller!.jumpTo(
              offset.clamp(0.0, controller!.position.maxScrollExtent),
            );
          }
        });
      }
      geometry = nextGeometry;
      return GridView.builder(
        key: const ValueKey('civil-year-grid'),
        controller: controller,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: rowHeight,
        ),
        itemCount: count,
        itemBuilder: (context, index) {
          final year = widget.firstDate.year + index;
          final selected = year == widget.selectedDate.year;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Semantics(
              selected: selected,
              child: TextButton(
                autofocus: selected,
                style: selected
                    ? TextButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                      )
                    : null,
                onPressed: () => widget.onChanged(DateTime(year)),
                child: Text(
                  MaterialLocalizations.of(context).formatYear(DateTime(year)),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
