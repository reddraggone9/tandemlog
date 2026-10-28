// dart format width=100
// Fork of Flutter's Material CalendarDatePicker for Tandemlog's date dialog.
//
// Upstream baseline (diff future pins against exactly this file):
//   Flutter 3.47.5, framework revision 6a19cca56475dbfba1478ee68d7bd0c2ef891da1
//   packages/flutter/lib/src/material/calendar_date_picker.dart
//   git blob bce7bedec61a98a840e1aa7638db3e4219230b3c
//
// Local changes (everything else is upstream text, formatted at upstream's
// 100-column width so `diff` against the baseline stays small):
//   - Imports use the public material library; `library`/`@docImport` dropped.
//   - CalendarDatePicker is renamed CivilCalendarDatePicker.
//   - The "October 2026 ▾" mode toggle becomes separate "October ▾" and
//     "2026 ▾" menus (_DatePickerModeToggleButton). Month opens a 12-month
//     grid; year opens the year list, a picked year opens that year's month
//     grid, and a picked month returns to the day grid with the tentative day
//     clamped (the former _handleYearChanged). Back/Escape return to days.
//   - Month/year modes use the app's CivilMonthGrid/CivilYearGrid; the unused
//     upstream YearPicker and its constants/grid delegate are removed.
//
// Copyright 2014 The Flutter Authors. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
//       copyright notice, this list of conditions and the following
//       disclaimer in the documentation and/or other materials provided
//       with the distribution.
//     * Neither the name of Google Inc. nor the names of its
//       contributors may be used to endorse or promote products derived
//       from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
// ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

// Upstream text is kept verbatim, including members deprecated after the fork.
// ignore_for_file: deprecated_member_use

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'civil_month_year_grids.dart';

const Duration _monthScrollDuration = Duration(milliseconds: 200);

// Current M2 implementation is not compliant with the M2 specification.
// Instead of a 42 pixels row height it should be 40 with a 2 pixels inner padding.
// See: https://m2.material.io/components/date-pickers#specs.
const double _dayPickerRowHeightM2 = 42.0;
// For M3, row height is 48 pxiels with 4 pixels inner padding.
// See: https://m3.material.io/components/date-pickers/specs#2d53890e-a08f-4c63-a0d9-abd9e95b4245.
const double _dayPickerRowHeightM3 = 48.0;

const int _maxDayPickerRowCount = 6; // A 31 day month that starts on Saturday.
// One extra row for the day-of-week header.
const double _maxDayPickerHeightM2 = _dayPickerRowHeightM2 * (_maxDayPickerRowCount + 1);
const double _maxDayPickerHeightM3 = _dayPickerRowHeightM3 * (_maxDayPickerRowCount + 1);

const double _monthPickerHorizontalPaddingPortraitM3 = 12.0;
const double _monthPickerHorizontalPaddingOther = 8.0;

const double _subHeaderHeight = 52.0;
const double _monthNavButtonsWidth = 108.0;

// 3.0 is the maximum scale factor on mobile phones. As of 07/30/24, iOS goes up
// to a max of 3.0 text scale factor, and Android goes up to 2.0. This is the
// default used for non-range date pickers. This default is changed to a lower
// value at different parts of the date pickers depending on content, and device
// orientation.
const double _kMaxTextScaleFactor = 3.0;

const double _kModeToggleButtonMaxScaleFactor = 2.0;

// The max scale factor of the day picker grid. This affects the size of the
// individual days in calendar view. Due to them filling a majority of the modal,
// which covers most of the screen, there's a limit in how large they can grow.
// There is also less room vertically in landscape orientation.
const double _kDayPickerGridPortraitMaxScaleFactor = 2.0;
const double _kDayPickerGridLandscapeMaxScaleFactor = 1.5;

// 14 is a common font size used to compute the effective text scale.
const double _fontSizeToScale = 14.0;

// Local: the picker's three bodies. Upstream's DatePickerMode has day/year only.
enum _CivilPickerMode { day, month, year }

// Local: the app ships English DefaultMaterialLocalizations, which format a
// month only together with its year. Semantics keep the localized month/year.
const List<String> _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Displays a grid of days for a given month and allows the user to select a
/// date.
///
/// Days are arranged in a rectangular grid with one column for each day of the
/// week. Controls are provided to change the year and month that the grid is
/// showing.
///
/// The calendar picker widget is rarely used directly. Instead, consider using
/// [showDatePicker], which will create a dialog that uses this as well as
/// provides a text entry option.
///
/// See also:
///
///  * [showDatePicker], which creates a Dialog that contains a
///    [CalendarDatePicker] and provides an optional compact view where the
///    user can enter a date as a line of text.
///  * [showTimePicker], which shows a dialog that contains a Material Design
///    time picker.
///
class CivilCalendarDatePicker extends StatefulWidget {
  /// Creates a calendar date picker.
  ///
  /// It will display a grid of days for the [initialDate]'s month, or, if that
  /// is null, the [currentDate]'s month. The day indicated by [initialDate] will
  /// be selected if it is not null.
  ///
  /// The optional [onDisplayedMonthChanged] callback can be used to track
  /// the currently displayed month.
  ///
  /// The user interface provides a way to change the year of the month being
  /// displayed. By default it will show the day grid, but this can be changed
  /// to start in the year selection interface with [initialCalendarMode] set
  /// to [DatePickerMode.year].
  ///
  /// The [lastDate] must be after or equal to [firstDate].
  ///
  /// The [initialDate], if provided, must be between [firstDate] and [lastDate]
  /// or equal to one of them.
  ///
  /// The [currentDate] represents the current day (i.e. today). This
  /// date will be highlighted in the day grid. If null, the date of
  /// `DateTime.now()` will be used.
  ///
  /// If [selectableDayPredicate] and [initialDate] are both non-null,
  /// [selectableDayPredicate] must return `true` for the [initialDate].
  ///
  /// {@template flutter.material.calendar_date_picker.calendarDelegate}
  /// The [calendarDelegate] controls date interpretation, formatting, and
  /// navigation within the picker. By providing a custom implementation,
  /// you can support alternative calendar systems such as Nepali, Hijri,
  /// Buddhist, and more. Defaults to [GregorianCalendarDelegate].
  /// {@endtemplate}
  CivilCalendarDatePicker({
    super.key,
    required DateTime? initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    DateTime? currentDate,
    required this.onDateChanged,
    this.onDisplayedMonthChanged,
    this.initialCalendarMode = DatePickerMode.day,
    this.selectableDayPredicate,
    this.calendarDelegate = const GregorianCalendarDelegate(),
  }) : initialDate = initialDate == null ? null : calendarDelegate.dateOnly(initialDate),
       firstDate = calendarDelegate.dateOnly(firstDate),
       lastDate = calendarDelegate.dateOnly(lastDate),
       currentDate = calendarDelegate.dateOnly(currentDate ?? calendarDelegate.now()) {
    assert(
      !this.lastDate.isBefore(this.firstDate),
      'lastDate ${this.lastDate} must be on or after firstDate ${this.firstDate}.',
    );
    assert(
      this.initialDate == null || !this.initialDate!.isBefore(this.firstDate),
      'initialDate ${this.initialDate} must be on or after firstDate ${this.firstDate}.',
    );
    assert(
      this.initialDate == null || !this.initialDate!.isAfter(this.lastDate),
      'initialDate ${this.initialDate} must be on or before lastDate ${this.lastDate}.',
    );
    assert(
      selectableDayPredicate == null ||
          this.initialDate == null ||
          selectableDayPredicate!(this.initialDate!),
      'Provided initialDate ${this.initialDate} must satisfy provided selectableDayPredicate.',
    );
  }

  /// The initially selected [DateTime] that the picker should display.
  ///
  /// Subsequently changing this has no effect. To change the selected date,
  /// change the [key] to create a new instance of the [CalendarDatePicker], and
  /// provide that widget the new [initialDate]. This will reset the widget's
  /// interactive state.
  final DateTime? initialDate;

  /// The earliest allowable [DateTime] that the user can select.
  final DateTime firstDate;

  /// The latest allowable [DateTime] that the user can select.
  final DateTime lastDate;

  /// The [DateTime] representing today. It will be highlighted in the day grid.
  final DateTime currentDate;

  /// Called when the user selects a date in the picker.
  final ValueChanged<DateTime> onDateChanged;

  /// Called when the user navigates to a new month/year in the picker.
  final ValueChanged<DateTime>? onDisplayedMonthChanged;

  /// The initial display of the calendar picker.
  ///
  /// Subsequently changing this has no effect. To change the calendar mode,
  /// change the [key] to create a new instance of the [CalendarDatePicker], and
  /// provide that widget a new [initialCalendarMode]. This will reset the
  /// widget's interactive state.
  final DatePickerMode initialCalendarMode;

  /// Function to provide full control over which dates in the calendar can be selected.
  final SelectableDayPredicate? selectableDayPredicate;

  /// {@macro flutter.material.calendar_date_picker.calendarDelegate}
  final CalendarDelegate<DateTime> calendarDelegate;

  @override
  State<CivilCalendarDatePicker> createState() => _CalendarDatePickerState();
}

class _CalendarDatePickerState extends State<CivilCalendarDatePicker> {
  bool _announcedInitialDate = false;
  String _announcementText = '';
  late _CivilPickerMode _mode;
  late DateTime _currentDisplayedMonthDate;
  DateTime? _selectedDate;
  final GlobalKey _monthPickerKey = GlobalKey();
  final GlobalKey _yearPickerKey = GlobalKey();
  late MaterialLocalizations _localizations;
  late TextDirection _textDirection;

  @override
  void initState() {
    super.initState();
    _mode = switch (widget.initialCalendarMode) {
      DatePickerMode.day => _CivilPickerMode.day,
      DatePickerMode.year => _CivilPickerMode.year,
    };
    final DateTime currentDisplayedDate = widget.initialDate ?? widget.currentDate;
    _currentDisplayedMonthDate = widget.calendarDelegate.getMonth(
      currentDisplayedDate.year,
      currentDisplayedDate.month,
    );
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    assert(debugCheckHasMaterial(context));
    assert(debugCheckHasMaterialLocalizations(context));
    assert(debugCheckHasDirectionality(context));
    _localizations = MaterialLocalizations.of(context);
    _textDirection = Directionality.of(context);
    if (!_announcedInitialDate && widget.initialDate != null) {
      assert(_selectedDate != null);
      _announcedInitialDate = true;
      final bool isToday = widget.calendarDelegate.isSameDay(widget.currentDate, _selectedDate);
      final semanticLabelSuffix = isToday ? ', ${_localizations.currentDateLabel}' : '';
      _announce('${_localizations.formatFullDate(_selectedDate!)}$semanticLabelSuffix');
    }
  }

  // Auxiliary method for handling the difference between platforms
  void _announce(String message) {
    if (MediaQuery.maybeSupportsAnnounceOf(context) ?? false) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ).catchError(_reportAnnouncementError);
    } else {
      // If SemanticsService.sendAnnouncement is not supported,
      // we use live region to achieve the announcement effect instead.
      _announcementText = message;
    }
  }

  void _vibrate() {
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        HapticFeedback.vibrate();
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        break;
    }
  }

  void _handleModeChanged(_CivilPickerMode mode) {
    _vibrate();
    setState(() {
      _mode = mode;
      if (_selectedDate case final DateTime selected) {
        final String message = switch (mode) {
          _CivilPickerMode.day => widget.calendarDelegate.formatMonthYear(selected, _localizations),
          _CivilPickerMode.month => widget.calendarDelegate.formatYear(
            _currentDisplayedMonthDate.year,
            _localizations,
          ),
          _CivilPickerMode.year => widget.calendarDelegate.formatYear(
            selected.year,
            _localizations,
          ),
        };
        _announce(message);
      }
    });
  }

  // Local: a picked year shows that year's month grid; the selection waits for
  // a month. Keep the displayed month when that year allows it.
  void _handleYearChanged(DateTime value) {
    DateTime month = widget.calendarDelegate.getMonth(value.year, _currentDisplayedMonthDate.month);
    if (month.isBefore(
      widget.calendarDelegate.getMonth(widget.firstDate.year, widget.firstDate.month),
    )) {
      month = widget.calendarDelegate.getMonth(widget.firstDate.year, widget.firstDate.month);
    } else if (month.isAfter(widget.lastDate)) {
      month = widget.calendarDelegate.getMonth(widget.lastDate.year, widget.lastDate.month);
    }
    setState(() {
      _handleMonthChanged(month);
    });
    _handleModeChanged(_CivilPickerMode.month);
  }

  void _handleMonthChanged(DateTime date) {
    setState(() {
      if (_currentDisplayedMonthDate.year != date.year ||
          _currentDisplayedMonthDate.month != date.month) {
        _currentDisplayedMonthDate = widget.calendarDelegate.getMonth(date.year, date.month);
        widget.onDisplayedMonthChanged?.call(_currentDisplayedMonthDate);
      }
    });
  }

  void _handleMonthSelected(DateTime value) {
    _vibrate();

    final int daysInMonth = widget.calendarDelegate.getDaysInMonth(value.year, value.month);
    final int preferredDay = math.min(_selectedDate?.day ?? 1, daysInMonth);
    value = widget.calendarDelegate.getDay(value.year, value.month, preferredDay);

    if (value.isBefore(widget.firstDate)) {
      value = widget.firstDate;
    } else if (value.isAfter(widget.lastDate)) {
      value = widget.lastDate;
    }

    setState(() {
      _mode = _CivilPickerMode.day;
      _handleMonthChanged(value);

      if (_isSelectable(value)) {
        _selectedDate = value;
        widget.onDateChanged(_selectedDate!);
      }
    });
  }

  void _handleDayChanged(DateTime value) {
    _vibrate();
    setState(() {
      _selectedDate = value;
      widget.onDateChanged(_selectedDate!);
      switch (Theme.of(context).platform) {
        case TargetPlatform.linux:
        case TargetPlatform.macOS:
        case TargetPlatform.windows:
          final bool isToday = widget.calendarDelegate.isSameDay(widget.currentDate, _selectedDate);
          final semanticLabelSuffix = isToday ? ', ${_localizations.currentDateLabel}' : '';
          SemanticsService.sendAnnouncement(
            View.of(context),
            '${_localizations.selectedDateLabel} ${widget.calendarDelegate.formatFullDate(_selectedDate!, _localizations)}$semanticLabelSuffix',
            _textDirection,
          ).catchError(_reportAnnouncementError);
        case TargetPlatform.android:
        case TargetPlatform.iOS:
        case TargetPlatform.fuchsia:
          break;
      }
    });
  }

  bool _isSelectable(DateTime date) {
    return widget.selectableDayPredicate?.call(date) ?? true;
  }

  Widget _buildPicker() {
    switch (_mode) {
      case _CivilPickerMode.day:
        return _MonthPicker(
          key: _monthPickerKey,
          calendarDelegate: widget.calendarDelegate,
          initialMonth: _currentDisplayedMonthDate,
          currentDate: widget.currentDate,
          firstDate: widget.firstDate,
          lastDate: widget.lastDate,
          selectedDate: _selectedDate,
          onChanged: _handleDayChanged,
          onDisplayedMonthChanged: _handleMonthChanged,
          selectableDayPredicate: widget.selectableDayPredicate,
        );
      case _CivilPickerMode.month:
        return Padding(
          padding: const EdgeInsets.only(top: _subHeaderHeight),
          child: CivilMonthGrid(
            year: _currentDisplayedMonthDate.year,
            firstDate: widget.firstDate,
            lastDate: widget.lastDate,
            selectedDate: _selectedDate,
            onChanged: _handleMonthSelected,
          ),
        );
      case _CivilPickerMode.year:
        return Padding(
          padding: const EdgeInsets.only(top: _subHeaderHeight),
          child: CivilYearGrid(
            key: _yearPickerKey,
            firstDate: widget.firstDate,
            lastDate: widget.lastDate,
            selectedDate: _currentDisplayedMonthDate,
            onChanged: _handleYearChanged,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMaterial(context));
    assert(debugCheckHasMaterialLocalizations(context));
    assert(debugCheckHasDirectionality(context));
    final double textScaleFactor =
        MediaQuery.textScalerOf(
          context,
        ).clamp(maxScaleFactor: _kMaxTextScaleFactor).scale(_fontSizeToScale) /
        _fontSizeToScale;

    // Conform to M3 spec in portrait mode (landscape mode is not specified).
    final Orientation orientation = MediaQuery.orientationOf(context);
    final double maxDayPickerHeight =
        Theme.of(context).useMaterial3 && orientation == Orientation.portrait
        ? _maxDayPickerHeightM3
        : _maxDayPickerHeightM2;

    // Scale the height of the picker area up with larger text. The size of the
    // picker has room for larger text, up until a scale factor of 1.3. After
    // after which, we increase the height to add room for content to continue
    // to scale the text size.
    final double scaledMaxDayPickerHeight = textScaleFactor > 1.3
        ? maxDayPickerHeight + ((_maxDayPickerRowCount + 1) * ((textScaleFactor - 1) * 8))
        : maxDayPickerHeight;
    final picker = SizedBox(
      height: _subHeaderHeight + scaledMaxDayPickerHeight,
      child: _buildPicker(),
    );
    // Local: Back/Escape leave the month or year body before closing a dialog.
    return PopScope(
      canPop: _mode == _CivilPickerMode.day,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _handleModeChanged(_CivilPickerMode.day);
        }
      },
      child: Stack(
        children: <Widget>[
          if (MediaQuery.maybeSupportsAnnounceOf(context) ?? false)
            picker
          else
            Semantics(
              container: true,
              liveRegion: true,
              accessibilityFocusBlockType: AccessibilityFocusBlockType.blockNode,
              label: _announcementText,
              child: picker,
            ),

          // Put the mode toggle button on top so that it won't be covered up by the _MonthPicker
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: _kModeToggleButtonMaxScaleFactor,
            child: _DatePickerModeToggleButton(
              mode: _mode,
              monthTitle: _monthNames[_currentDisplayedMonthDate.month - 1],
              title: widget.calendarDelegate.formatMonthYear(
                _currentDisplayedMonthDate,
                _localizations,
              ),
              yearTitle: widget.calendarDelegate.formatYear(
                _currentDisplayedMonthDate.year,
                _localizations,
              ),
              onMonthPressed: () => _handleModeChanged(switch (_mode) {
                _CivilPickerMode.month => _CivilPickerMode.day,
                _ => _CivilPickerMode.month,
              }),
              onTitlePressed: () => _handleModeChanged(switch (_mode) {
                _CivilPickerMode.year => _CivilPickerMode.day,
                _ => _CivilPickerMode.year,
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Local: the month and year menus above the calendar grid.
///
/// Each menu toggles its own body (the month grid or the year list) and the
/// day grid; its arrow turns while its body is shown.
class _DatePickerModeToggleButton extends StatefulWidget {
  const _DatePickerModeToggleButton({
    required this.mode,
    required this.monthTitle,
    required this.title,
    required this.yearTitle,
    required this.onMonthPressed,
    required this.onTitlePressed,
  });

  /// The current display of the calendar picker.
  final _CivilPickerMode mode;

  /// The month being viewed, without its year.
  final String monthTitle;

  /// The localized month and year being viewed, for semantics.
  final String title;

  /// The year being viewed.
  final String yearTitle;

  /// The callback when the month is pressed.
  final VoidCallback onMonthPressed;

  /// The callback when the year is pressed.
  final VoidCallback onTitlePressed;

  @override
  _DatePickerModeToggleButtonState createState() => _DatePickerModeToggleButtonState();
}

class _DatePickerModeToggleButtonState extends State<_DatePickerModeToggleButton>
    with TickerProviderStateMixin {
  late AnimationController _monthController;
  late AnimationController _controller;

  AnimationController _arrow(bool open) => AnimationController(
    value: open ? 0.5 : 0,
    upperBound: 0.5,
    duration: const Duration(milliseconds: 200),
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _monthController = _arrow(widget.mode == _CivilPickerMode.month);
    _controller = _arrow(widget.mode == _CivilPickerMode.year);
  }

  @override
  void didUpdateWidget(_DatePickerModeToggleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode == widget.mode) {
      return;
    }

    for (final (AnimationController controller, _CivilPickerMode mode)
        in <(AnimationController, _CivilPickerMode)>[
          (_monthController, _CivilPickerMode.month),
          (_controller, _CivilPickerMode.year),
        ]) {
      if (widget.mode == mode) {
        controller.forward();
      } else {
        controller.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DatePickerThemeData datePickerTheme = DatePickerTheme.of(context);
    final DatePickerThemeData defaults = DatePickerTheme.defaults(context);
    final TextStyle? buttonTextStyle =
        datePickerTheme.toggleButtonTextStyle ?? defaults.toggleButtonTextStyle;
    final Color? subHeaderForegroundColor =
        datePickerTheme.subHeaderForegroundColor ?? defaults.subHeaderForegroundColor;
    final Color? buttonTextColor =
        datePickerTheme.toggleButtonTextStyle?.color ??
        datePickerTheme.subHeaderForegroundColor ??
        defaults.toggleButtonTextStyle?.color;

    Widget menu({
      required Key key,
      required String label,
      required String value,
      required String text,
      required AnimationController turns,
      required VoidCallback onPressed,
    }) {
      return Semantics(
        key: key,
        label: label,
        value: value,
        button: true,
        container: true,
        excludeSemantics: true,
        child: SizedBox(
          height: _subHeaderHeight,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      style: buttonTextStyle?.apply(color: buttonTextColor),
                    ),
                  ),
                  RotationTransition(
                    turns: turns,
                    child: Icon(Icons.arrow_drop_down, color: subHeaderForegroundColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Narrow dialogs show "Feb" rather than an ellipsized "Febr…". If even
    // that does not fit at large text, shrink only these labels (never below
    // 100%) so the month, year and paging buttons all stay visible.
    final double reserved =
        16 + 4 + (widget.mode == _CivilPickerMode.day ? _monthNavButtonsWidth : 0);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    double textWidth(String text, TextScaler textScaler) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: buttonTextStyle),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final double width = painter.width;
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Each menu adds 16px padding and a 24px arrow.
        final double textSpace = constraints.maxWidth - reserved - 2 * (16 + 24);
        final String shortTitle = widget.monthTitle.substring(0, 3);
        final bool full =
            textWidth(widget.monthTitle, scaler) + textWidth(widget.yearTitle, scaler) <= textSpace;
        TextScaler headerScaler = scaler;
        if (!full &&
            textWidth(shortTitle, scaler) + textWidth(widget.yearTitle, scaler) > textSpace) {
          final double unscaled =
              textWidth(shortTitle, TextScaler.noScaling) +
              textWidth(widget.yearTitle, TextScaler.noScaling);
          final double factor = math.max(1, textSpace / unscaled);
          headerScaler = scaler.clamp(maxScaleFactor: math.max(1, factor - .01));
        }
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: headerScaler),
          child: SizedBox(
            height: _subHeaderHeight,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: menu(
                      key: const ValueKey<String>('civil-month-button'),
                      label: 'Select month',
                      value: widget.title,
                      text: full ? widget.monthTitle : shortTitle,
                      turns: _monthController,
                      onPressed: widget.onMonthPressed,
                    ),
                  ),
                  menu(
                    key: const ValueKey<String>('civil-year-button'),
                    label: MaterialLocalizations.of(context).selectYearSemanticsLabel,
                    value: widget.yearTitle,
                    text: widget.yearTitle,
                    turns: _controller,
                    onPressed: widget.onTitlePressed,
                  ),
                  if (widget.mode == _CivilPickerMode.day)
                    // Give space for the prev/next month buttons that are underneath this row
                    const SizedBox(width: _monthNavButtonsWidth),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _monthController.dispose();
    _controller.dispose();
    super.dispose();
  }
}

class _MonthPicker extends StatefulWidget {
  /// Creates a month picker.
  _MonthPicker({
    super.key,
    required this.initialMonth,
    required this.currentDate,
    required this.firstDate,
    required this.lastDate,
    required this.selectedDate,
    required this.onChanged,
    required this.onDisplayedMonthChanged,
    required this.calendarDelegate,
    this.selectableDayPredicate,
  }) : assert(!firstDate.isAfter(lastDate)),
       assert(selectedDate == null || !selectedDate.isBefore(firstDate)),
       assert(selectedDate == null || !selectedDate.isAfter(lastDate));

  /// The initial month to display.
  ///
  /// Subsequently changing this has no effect. To change the selected month,
  /// change the [key] to create a new instance of the [_MonthPicker], and
  /// provide that widget the new [initialMonth]. This will reset the widget's
  /// interactive state.
  final DateTime initialMonth;

  /// The current date.
  ///
  /// This date is subtly highlighted in the picker.
  final DateTime currentDate;

  /// The earliest date the user is permitted to pick.
  ///
  /// This date must be on or before the [lastDate].
  final DateTime firstDate;

  /// The latest date the user is permitted to pick.
  ///
  /// This date must be on or after the [firstDate].
  final DateTime lastDate;

  /// The currently selected date.
  ///
  /// This date is highlighted in the picker.
  final DateTime? selectedDate;

  /// Called when the user picks a day.
  final ValueChanged<DateTime> onChanged;

  /// Called when the user navigates to a new month.
  final ValueChanged<DateTime> onDisplayedMonthChanged;

  /// Optional user supplied predicate function to customize selectable days.
  final SelectableDayPredicate? selectableDayPredicate;

  /// {@macro flutter.material.calendar_date_picker.calendarDelegate}
  final CalendarDelegate<DateTime> calendarDelegate;

  @override
  _MonthPickerState createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  final GlobalKey _pageViewKey = GlobalKey();
  String _announcementText = '';
  late DateTime _currentMonth;
  late PageController _pageController;
  late MaterialLocalizations _localizations;
  Map<ShortcutActivator, Intent>? _shortcutMap;
  Map<Type, Action<Intent>>? _actionMap;
  late FocusNode _dayGridFocus;
  DateTime? _focusedDay;

  @override
  void initState() {
    super.initState();
    _currentMonth = widget.initialMonth;
    _pageController = PageController(
      initialPage: widget.calendarDelegate.monthDelta(widget.firstDate, _currentMonth),
    );
    _shortcutMap = const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
        TraversalDirection.left,
      ),
      SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
        TraversalDirection.right,
      ),
      SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
        TraversalDirection.down,
      ),
      SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
    };
    _actionMap = <Type, Action<Intent>>{
      NextFocusIntent: CallbackAction<NextFocusIntent>(onInvoke: _handleGridNextFocus),
      PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(onInvoke: _handleGridPreviousFocus),
      DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
        onInvoke: _handleDirectionFocus,
      ),
    };
    _dayGridFocus = FocusNode(debugLabel: 'Day Grid');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _localizations = MaterialLocalizations.of(context);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _dayGridFocus.dispose();
    super.dispose();
  }

  void _handleDateSelected(DateTime selectedDate) {
    _focusedDay = selectedDate;
    widget.onChanged(selectedDate);
  }

  // Auxiliary method for handling the difference between platforms
  void _announce(String message) {
    if (MediaQuery.maybeSupportsAnnounceOf(context) ?? false) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ).catchError(_reportAnnouncementError);
    } else {
      // If SemanticsService.sendAnnouncement is not supported,
      // we use live region to achieve the announcement effect instead.
      _announcementText = message;
    }
  }

  void _handleMonthPageChanged(int monthPage) {
    setState(() {
      final DateTime monthDate = widget.calendarDelegate.addMonthsToMonthDate(
        widget.firstDate,
        monthPage,
      );
      if (!widget.calendarDelegate.isSameMonth(_currentMonth, monthDate)) {
        _currentMonth = widget.calendarDelegate.getMonth(monthDate.year, monthDate.month);
        widget.onDisplayedMonthChanged(_currentMonth);
        if (_focusedDay != null &&
            !widget.calendarDelegate.isSameMonth(_focusedDay, _currentMonth)) {
          // We have navigated to a new month with the grid focused, but the
          // focused day is not in this month. Choose a new one trying to keep
          // the same day of the month.
          _focusedDay = _focusableDayForMonth(_currentMonth, _focusedDay!.day);
        }
        _announce(widget.calendarDelegate.formatMonthYear(_currentMonth, _localizations));
      }
    });
  }

  /// Returns a focusable date for the given month.
  ///
  /// If the preferredDay is available in the month it will be returned,
  /// otherwise the first selectable day in the month will be returned. If
  /// no dates are selectable in the month, then it will return null.
  DateTime? _focusableDayForMonth(DateTime month, int preferredDay) {
    final int daysInMonth = widget.calendarDelegate.getDaysInMonth(month.year, month.month);

    // Can we use the preferred day in this month?
    if (preferredDay <= daysInMonth) {
      final DateTime newFocus = widget.calendarDelegate.getDay(
        month.year,
        month.month,
        preferredDay,
      );
      if (_isSelectable(newFocus)) {
        return newFocus;
      }
    }

    // Start at the 1st and take the first selectable date.
    for (var day = 1; day <= daysInMonth; day++) {
      final DateTime newFocus = widget.calendarDelegate.getDay(month.year, month.month, day);
      if (_isSelectable(newFocus)) {
        return newFocus;
      }
    }
    return null;
  }

  /// Navigate to the next month.
  void _handleNextMonth() {
    if (!_isDisplayingLastMonth) {
      _pageController.nextPage(duration: _monthScrollDuration, curve: Curves.ease);
    }
  }

  /// Navigate to the previous month.
  void _handlePreviousMonth() {
    if (!_isDisplayingFirstMonth) {
      _pageController.previousPage(duration: _monthScrollDuration, curve: Curves.ease);
    }
  }

  /// Navigate to the given month.
  void _showMonth(DateTime month, {bool jump = false}) {
    final int monthPage = widget.calendarDelegate.monthDelta(widget.firstDate, month);
    if (jump) {
      _pageController.jumpToPage(monthPage);
    } else {
      _pageController.animateToPage(monthPage, duration: _monthScrollDuration, curve: Curves.ease);
    }
  }

  /// True if the earliest allowable month is displayed.
  bool get _isDisplayingFirstMonth {
    return !_currentMonth.isAfter(
      widget.calendarDelegate.getMonth(widget.firstDate.year, widget.firstDate.month),
    );
  }

  /// True if the latest allowable month is displayed.
  bool get _isDisplayingLastMonth {
    return !_currentMonth.isBefore(
      widget.calendarDelegate.getMonth(widget.lastDate.year, widget.lastDate.month),
    );
  }

  /// Handler for when the overall day grid obtains or loses focus.
  void _handleGridFocusChange(bool focused) {
    setState(() {
      if (focused && _focusedDay == null) {
        if (widget.calendarDelegate.isSameMonth(widget.selectedDate, _currentMonth)) {
          _focusedDay = widget.selectedDate;
        } else if (widget.calendarDelegate.isSameMonth(widget.currentDate, _currentMonth)) {
          _focusedDay = _focusableDayForMonth(_currentMonth, widget.currentDate.day);
        } else {
          _focusedDay = _focusableDayForMonth(_currentMonth, 1);
        }
      }
    });
  }

  /// Move focus to the next element after the day grid.
  void _handleGridNextFocus(NextFocusIntent intent) {
    _dayGridFocus.requestFocus();
    _dayGridFocus.nextFocus();
  }

  /// Move focus to the previous element before the day grid.
  void _handleGridPreviousFocus(PreviousFocusIntent intent) {
    _dayGridFocus.requestFocus();
    _dayGridFocus.previousFocus();
  }

  /// Move the internal focus date in the direction of the given intent.
  ///
  /// This will attempt to move the focused day to the next selectable day in
  /// the given direction. If the new date is not in the current month, then
  /// the page view will be scrolled to show the new date's month.
  ///
  /// For horizontal directions, it will move forward or backward a day (depending
  /// on the current [TextDirection]). For vertical directions it will move up and
  /// down a week at a time.
  void _handleDirectionFocus(DirectionalFocusIntent intent) {
    assert(_focusedDay != null);
    setState(() {
      final DateTime? nextDate = _nextDateInDirection(_focusedDay!, intent.direction);
      if (nextDate != null) {
        _focusedDay = nextDate;
        if (!widget.calendarDelegate.isSameMonth(_focusedDay, _currentMonth)) {
          _showMonth(_focusedDay!);
        }
      }
    });
  }

  static const Map<TraversalDirection, int> _directionOffset = <TraversalDirection, int>{
    TraversalDirection.up: -DateTime.daysPerWeek,
    TraversalDirection.right: 1,
    TraversalDirection.down: DateTime.daysPerWeek,
    TraversalDirection.left: -1,
  };

  int _dayDirectionOffset(TraversalDirection traversalDirection, TextDirection textDirection) {
    // Swap left and right if the text direction if RTL
    if (textDirection == TextDirection.rtl) {
      if (traversalDirection == TraversalDirection.left) {
        traversalDirection = TraversalDirection.right;
      } else if (traversalDirection == TraversalDirection.right) {
        traversalDirection = TraversalDirection.left;
      }
    }
    return _directionOffset[traversalDirection]!;
  }

  DateTime? _nextDateInDirection(DateTime date, TraversalDirection direction) {
    final TextDirection textDirection = Directionality.of(context);
    DateTime nextDate = widget.calendarDelegate.addDaysToDate(
      date,
      _dayDirectionOffset(direction, textDirection),
    );
    while (!nextDate.isBefore(widget.firstDate) && !nextDate.isAfter(widget.lastDate)) {
      if (_isSelectable(nextDate)) {
        return nextDate;
      }
      nextDate = widget.calendarDelegate.addDaysToDate(
        nextDate,
        _dayDirectionOffset(direction, textDirection),
      );
    }
    return null;
  }

  bool _isSelectable(DateTime date) {
    return widget.selectableDayPredicate?.call(date) ?? true;
  }

  Widget _buildItems(BuildContext context, int index) {
    final DateTime month = widget.calendarDelegate.addMonthsToMonthDate(widget.firstDate, index);
    return _DayPicker(
      key: ValueKey<DateTime>(month),
      calendarDelegate: widget.calendarDelegate,
      selectedDate: widget.selectedDate,
      currentDate: widget.currentDate,
      onChanged: _handleDateSelected,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      displayedMonth: month,
      selectableDayPredicate: widget.selectableDayPredicate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color? subHeaderForegroundColor =
        DatePickerTheme.of(context).subHeaderForegroundColor ??
        DatePickerTheme.defaults(context).subHeaderForegroundColor;

    final bool supportsAnnounce = MediaQuery.maybeSupportsAnnounceOf(context) ?? false;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: !supportsAnnounce,
      accessibilityFocusBlockType: !supportsAnnounce
          ? AccessibilityFocusBlockType.blockNode
          : AccessibilityFocusBlockType.none,
      label: !supportsAnnounce ? _announcementText : null,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: _subHeaderHeight,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
              child: Row(
                children: <Widget>[
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.chevron_left,
                      semanticLabel: _isDisplayingFirstMonth
                          ? _localizations.previousMonthTooltip
                          : null,
                    ),
                    color: subHeaderForegroundColor,
                    tooltip: _isDisplayingFirstMonth ? null : _localizations.previousMonthTooltip,
                    onPressed: _isDisplayingFirstMonth ? null : _handlePreviousMonth,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.chevron_right,
                      semanticLabel: _isDisplayingLastMonth
                          ? _localizations.nextMonthTooltip
                          : null,
                    ),
                    color: subHeaderForegroundColor,
                    tooltip: _isDisplayingLastMonth ? null : _localizations.nextMonthTooltip,
                    onPressed: _isDisplayingLastMonth ? null : _handleNextMonth,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FocusableActionDetector(
              shortcuts: _shortcutMap,
              actions: _actionMap,
              focusNode: _dayGridFocus,
              onFocusChange: _handleGridFocusChange,
              child: _FocusedDate(
                calendarDelegate: widget.calendarDelegate,
                date: _dayGridFocus.hasFocus ? _focusedDay : null,
                // Wrap the PageView with `Material`, so when its child paints on materials
                // the content won't go out of boundary during page transition.
                child: Material(
                  type: MaterialType.transparency,
                  child: PageView.builder(
                    key: _pageViewKey,
                    controller: _pageController,
                    itemBuilder: _buildItems,
                    itemCount:
                        widget.calendarDelegate.monthDelta(widget.firstDate, widget.lastDate) + 1,
                    onPageChanged: _handleMonthPageChanged,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// InheritedWidget indicating what the current focused date is for its children.
///
/// This is used by the [_MonthPicker] to let its children [_DayPicker]s know
/// what the currently focused date (if any) should be.
class _FocusedDate extends InheritedWidget {
  const _FocusedDate({required super.child, required this.calendarDelegate, this.date});

  final CalendarDelegate<DateTime> calendarDelegate;
  final DateTime? date;

  @override
  bool updateShouldNotify(_FocusedDate oldWidget) {
    return !calendarDelegate.isSameDay(date, oldWidget.date);
  }

  static DateTime? maybeOf(BuildContext context) {
    final _FocusedDate? focusedDate = context.dependOnInheritedWidgetOfExactType<_FocusedDate>();
    return focusedDate?.date;
  }
}

/// Displays the days of a given month and allows choosing a day.
///
/// The days are arranged in a rectangular grid with one column for each day of
/// the week.
class _DayPicker extends StatefulWidget {
  /// Creates a day picker.
  _DayPicker({
    super.key,
    required this.currentDate,
    required this.displayedMonth,
    required this.firstDate,
    required this.lastDate,
    required this.selectedDate,
    required this.onChanged,
    required this.calendarDelegate,
    this.selectableDayPredicate,
  }) : assert(!firstDate.isAfter(lastDate)),
       assert(selectedDate == null || !selectedDate.isBefore(firstDate)),
       assert(selectedDate == null || !selectedDate.isAfter(lastDate));

  /// The currently selected date.
  ///
  /// This date is highlighted in the picker.
  final DateTime? selectedDate;

  /// The current date at the time the picker is displayed.
  final DateTime currentDate;

  /// Called when the user picks a day.
  final ValueChanged<DateTime> onChanged;

  /// The earliest date the user is permitted to pick.
  ///
  /// This date must be on or before the [lastDate].
  final DateTime firstDate;

  /// The latest date the user is permitted to pick.
  ///
  /// This date must be on or after the [firstDate].
  final DateTime lastDate;

  /// The month whose days are displayed by this picker.
  final DateTime displayedMonth;

  /// Optional user supplied predicate function to customize selectable days.
  final SelectableDayPredicate? selectableDayPredicate;

  /// {@macro flutter.material.calendar_date_picker.calendarDelegate}
  final CalendarDelegate<DateTime> calendarDelegate;

  @override
  _DayPickerState createState() => _DayPickerState();
}

class _DayPickerState extends State<_DayPicker> {
  /// List of [FocusNode]s, one for each day of the month.
  late List<FocusNode> _dayFocusNodes;

  @override
  void initState() {
    super.initState();
    final int daysInMonth = widget.calendarDelegate.getDaysInMonth(
      widget.displayedMonth.year,
      widget.displayedMonth.month,
    );
    _dayFocusNodes = List<FocusNode>.generate(
      daysInMonth,
      (int index) => FocusNode(skipTraversal: true, debugLabel: 'Day ${index + 1}'),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check to see if the focused date is in this month, if so focus it.
    final DateTime? focusedDate = _FocusedDate.maybeOf(context);
    if (focusedDate != null &&
        widget.calendarDelegate.isSameMonth(widget.displayedMonth, focusedDate)) {
      _dayFocusNodes[focusedDate.day - 1].requestFocus();
    }
  }

  @override
  void dispose() {
    for (final FocusNode node in _dayFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Builds widgets showing abbreviated days of week. The first widget in the
  /// returned list corresponds to the first day of week for the current locale.
  ///
  /// Examples:
  ///
  ///     ┌ Sunday is the first day of week in the US (en_US)
  ///     |
  ///     S M T W T F S  ← the returned list contains these widgets
  ///     _ _ _ _ _ 1 2
  ///     3 4 5 6 7 8 9
  ///
  ///     ┌ But it's Monday in the UK (en_GB)
  ///     |
  ///     M T W T F S S  ← the returned list contains these widgets
  ///     _ _ _ _ 1 2 3
  ///     4 5 6 7 8 9 10
  ///
  List<Widget> _dayHeaders(TextStyle? headerStyle, MaterialLocalizations localizations) {
    final result = <Widget>[];
    for (
      int i = localizations.firstDayOfWeekIndex;
      result.length < DateTime.daysPerWeek;
      i = (i + 1) % DateTime.daysPerWeek
    ) {
      final String weekday = localizations.narrowWeekdays[i];
      result.add(
        ExcludeSemantics(
          child: Center(child: Text(weekday, style: headerStyle)),
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations localizations = MaterialLocalizations.of(context);
    final DatePickerThemeData datePickerTheme = DatePickerTheme.of(context);
    final DatePickerThemeData defaults = DatePickerTheme.defaults(context);
    final TextStyle? weekdayStyle = datePickerTheme.weekdayStyle ?? defaults.weekdayStyle;

    final Orientation orientation = MediaQuery.orientationOf(context);
    final isLandscapeOrientation = orientation == Orientation.landscape;

    final int year = widget.displayedMonth.year;
    final int month = widget.displayedMonth.month;

    final int daysInMonth = widget.calendarDelegate.getDaysInMonth(year, month);
    final int dayOffset = widget.calendarDelegate.firstDayOffset(year, month, localizations);

    final List<Widget> dayItems = _dayHeaders(weekdayStyle, localizations);
    // 1-based day of month, e.g. 1-31 for January, and 1-29 for February on
    // a leap year.
    int day = -dayOffset;
    while (day < daysInMonth) {
      day++;
      if (day < 1) {
        dayItems.add(const SizedBox.shrink());
      } else {
        final DateTime dayToBuild = widget.calendarDelegate.getDay(year, month, day);
        final bool isDisabled =
            dayToBuild.isAfter(widget.lastDate) ||
            dayToBuild.isBefore(widget.firstDate) ||
            (widget.selectableDayPredicate != null && !widget.selectableDayPredicate!(dayToBuild));
        final bool isSelectedDay = widget.calendarDelegate.isSameDay(
          widget.selectedDate,
          dayToBuild,
        );
        final bool isToday = widget.calendarDelegate.isSameDay(widget.currentDate, dayToBuild);

        dayItems.add(
          _Day(
            dayToBuild,
            key: ValueKey<DateTime>(dayToBuild),
            isDisabled: isDisabled,
            isSelectedDay: isSelectedDay,
            isToday: isToday,
            onChanged: widget.onChanged,
            focusNode: _dayFocusNodes[day - 1],
            calendarDelegate: widget.calendarDelegate,
          ),
        );
      }
    }

    final double monthPickerHorizontalPadding =
        Theme.of(context).useMaterial3 && !isLandscapeOrientation
        ? _monthPickerHorizontalPaddingPortraitM3
        : _monthPickerHorizontalPaddingOther;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: monthPickerHorizontalPadding),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: isLandscapeOrientation
            ? _kDayPickerGridLandscapeMaxScaleFactor
            : _kDayPickerGridPortraitMaxScaleFactor,
        child: GridView.custom(
          physics: const ClampingScrollPhysics(),
          gridDelegate: _DayPickerGridDelegate(context),
          childrenDelegate: SliverChildListDelegate(dayItems, addRepaintBoundaries: false),
        ),
      ),
    );
  }
}

class _Day extends StatefulWidget {
  const _Day(
    this.day, {
    super.key,
    required this.isDisabled,
    required this.isSelectedDay,
    required this.isToday,
    required this.onChanged,
    required this.focusNode,
    required this.calendarDelegate,
  });

  final DateTime day;
  final bool isDisabled;
  final bool isSelectedDay;
  final bool isToday;
  final ValueChanged<DateTime> onChanged;
  final FocusNode focusNode;
  final CalendarDelegate<DateTime> calendarDelegate;

  @override
  State<_Day> createState() => _DayState();
}

class _DayState extends State<_Day> {
  final MaterialStatesController _statesController = MaterialStatesController();

  @override
  Widget build(BuildContext context) {
    final DatePickerThemeData defaults = DatePickerTheme.defaults(context);
    final DatePickerThemeData datePickerTheme = DatePickerTheme.of(context);
    final TextStyle? dayStyle = datePickerTheme.dayStyle ?? defaults.dayStyle;
    T? effectiveValue<T>(T? Function(DatePickerThemeData? theme) getProperty) {
      return getProperty(datePickerTheme) ?? getProperty(defaults);
    }

    T? resolve<T>(
      WidgetStateProperty<T>? Function(DatePickerThemeData? theme) getProperty,
      Set<WidgetState> states,
    ) {
      return effectiveValue((DatePickerThemeData? theme) {
        return getProperty(theme)?.resolve(states);
      });
    }

    final MaterialLocalizations localizations = MaterialLocalizations.of(context);
    final semanticLabelSuffix = widget.isToday ? ', ${localizations.currentDateLabel}' : '';

    final states = <WidgetState>{
      if (widget.isDisabled) WidgetState.disabled,
      if (widget.isSelectedDay) WidgetState.selected,
    };

    _statesController.value = states;

    final Color? dayForegroundColor = resolve<Color?>(
      (DatePickerThemeData? theme) =>
          widget.isToday ? theme?.todayForegroundColor : theme?.dayForegroundColor,
      states,
    );
    final Color? dayBackgroundColor = resolve<Color?>(
      (DatePickerThemeData? theme) =>
          widget.isToday ? theme?.todayBackgroundColor : theme?.dayBackgroundColor,
      states,
    );
    final WidgetStateProperty<Color?> dayOverlayColor = WidgetStateProperty.resolveWith<Color?>(
      (Set<WidgetState> states) =>
          effectiveValue((DatePickerThemeData? theme) => theme?.dayOverlayColor?.resolve(states)),
    );
    final OutlinedBorder dayShape = resolve<OutlinedBorder?>(
      (DatePickerThemeData? theme) => theme?.dayShape,
      states,
    )!;
    final bool hasCustomBorderColor =
        datePickerTheme.todayBorder != null && datePickerTheme.todayBorder!.color.opacity != 0.0;
    final BorderSide todayBorderSide = hasCustomBorderColor
        ? datePickerTheme.todayBorder!
        : (datePickerTheme.todayBorder ?? defaults.todayBorder!).copyWith(
            color: dayForegroundColor,
          );
    final decoration = widget.isToday
        ? ShapeDecoration(
            color: dayBackgroundColor,
            shape: dayShape.copyWith(side: todayBorderSide),
          )
        : ShapeDecoration(color: dayBackgroundColor, shape: dayShape);

    Widget dayWidget = Ink(
      decoration: decoration,
      child: Center(
        child: Text(
          localizations.formatDecimal(widget.day.day),
          style: dayStyle?.apply(color: dayForegroundColor),
        ),
      ),
    );

    // Adds padding as per M3 guidelines for portrait mode. Not applied in landscape
    // mode currently due to unclear specifications.
    final Orientation orientation = MediaQuery.orientationOf(context);
    if (Theme.of(context).useMaterial3 && orientation == Orientation.portrait) {
      dayWidget = Padding(padding: const EdgeInsets.all(4.0), child: dayWidget);
    }
    dayWidget = Semantics(
      // We want the day of month to be spoken first irrespective of the
      // locale-specific preferences or TextDirection. This is because
      // an accessibility user is more likely to be interested in the
      // day of month before the rest of the date, as they are looking
      // for the day of month. To do that we prepend day of month to the
      // formatted full date.
      label:
          '${localizations.formatDecimal(widget.day.day)}, ${widget.calendarDelegate.formatFullDate(widget.day, localizations)}$semanticLabelSuffix',
      // Set button to true to make the date selectable.
      button: true,
      selected: widget.isSelectedDay,
      enabled: !widget.isDisabled,
      excludeSemantics: true,
      child: dayWidget,
    );

    if (!widget.isDisabled) {
      dayWidget = InkResponse(
        focusNode: widget.focusNode,
        onTap: () => widget.onChanged(widget.day),
        statesController: _statesController,
        overlayColor: dayOverlayColor,
        customBorder: dayShape,
        containedInkWell: true,
        child: dayWidget,
      );
    }

    return dayWidget;
  }

  @override
  void dispose() {
    _statesController.dispose();
    super.dispose();
  }
}

class _DayPickerGridDelegate extends SliverGridDelegate {
  const _DayPickerGridDelegate(this.context);

  final BuildContext context;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final double textScaleFactor =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 3.0).scale(_fontSizeToScale) /
        _fontSizeToScale;
    // Conform to M3 spec in portrait mode (landscape mode is not specified).
    final Orientation orientation = MediaQuery.orientationOf(context);
    final double dayPickerRowHeight =
        Theme.of(context).useMaterial3 && orientation == Orientation.portrait
        ? _dayPickerRowHeightM3
        : _dayPickerRowHeightM2;
    final double scaledRowHeight = textScaleFactor > 1.3
        ? ((textScaleFactor - 1) * 30) + dayPickerRowHeight
        : dayPickerRowHeight;
    const int columnCount = DateTime.daysPerWeek;
    final double tileWidth = constraints.crossAxisExtent / columnCount;
    final double tileHeight = math.min(
      scaledRowHeight,
      constraints.viewportMainAxisExtent / (_maxDayPickerRowCount + 1),
    );
    return SliverGridRegularTileLayout(
      childCrossAxisExtent: tileWidth,
      childMainAxisExtent: tileHeight,
      crossAxisCount: columnCount,
      crossAxisStride: tileWidth,
      mainAxisStride: tileHeight,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(_DayPickerGridDelegate oldDelegate) => false;
}

void _reportAnnouncementError(Object exception, StackTrace stack) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: exception,
      stack: stack,
      library: 'material library',
      context: ErrorDescription('while sending semantics announcement'),
    ),
  );
}
