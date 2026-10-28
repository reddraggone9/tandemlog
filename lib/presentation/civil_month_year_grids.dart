import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The calendar's month body: twelve months of [year], four rows of three.
/// Compact English labels match the app; semantics use the localized
/// month and year.
class CivilMonthGrid extends StatelessWidget {
  const CivilMonthGrid({
    super.key,
    required this.year,
    required this.firstDate,
    required this.lastDate,
    required this.selectedDate,
    required this.onChanged,
  });
  final int year;
  final DateTime firstDate, lastDate;
  final DateTime? selectedDate;

  /// Receives the first day of the chosen month.
  final ValueChanged<DateTime> onChanged;

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

  Widget _month(BuildContext context, int month) {
    final colors = Theme.of(context).colorScheme;
    final selected = selectedDate?.year == year && selectedDate?.month == month;
    return Semantics(
      selected: selected,
      child: TextButton(
        autofocus: selected,
        style: selected
            ? TextButton.styleFrom(
                backgroundColor: colors.secondaryContainer,
                foregroundColor: colors.onSecondaryContainer,
              )
            : null,
        onPressed:
            DateTime(year, month + 1, 0).isBefore(firstDate) ||
                DateTime(year, month).isAfter(lastDate)
            ? null
            : () => onChanged(DateTime(year, month)),
        child: Semantics(
          label: MaterialLocalizations.of(
            context,
          ).formatMonthYear(DateTime(year, month)),
          excludeSemantics: true,
          child: Text(_months[month - 1]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.count(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        crossAxisCount: 3,
        childAspectRatio:
            (constraints.maxWidth - 24) /
            3 /
            math.max(48, constraints.maxHeight / 4),
        children: [
          for (var month = 1; month <= 12; month++) _month(context, month),
        ],
      ),
    );
  }
}

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
