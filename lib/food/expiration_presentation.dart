import 'dart:async';

import 'package:flutter/material.dart';

enum FoodExpiryUrgency { normal, expired, soon, approaching }

/// Published expiry strings are canonical calendar dates, not instants.
/// Compare calendar boundaries rather than elapsed 24-hour periods across DST.
FoodExpiryUrgency foodExpiryUrgency(String? expiry, DateTime today) {
  if (expiry == null) return FoodExpiryUrgency.normal;
  String boundary(int days) {
    final date = DateTime(today.year, today.month, today.day + days);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  if (expiry.compareTo(boundary(0)) < 0) return FoodExpiryUrgency.expired;
  if (expiry.compareTo(boundary(3)) < 0) return FoodExpiryUrgency.soon;
  if (expiry.compareTo(boundary(7)) < 0) return FoodExpiryUrgency.approaching;
  return FoodExpiryUrgency.normal;
}

/// Darker orange/yellow on light surfaces keep ordinary-size date text readable.
/// The displayed date still carries the information when hues are indistinct.
Color foodExpiryColor(String? expiry, DateTime today, ColorScheme colors) =>
    switch (foodExpiryUrgency(expiry, today)) {
      FoodExpiryUrgency.expired => colors.error,
      FoodExpiryUrgency.soon =>
        colors.brightness == Brightness.dark
            ? const Color(0xffffb77d)
            : const Color(0xff9c4400),
      FoodExpiryUrgency.approaching =>
        colors.brightness == Brightness.dark
            ? const Color(0xffe8cb4a)
            : const Color(0xff746000),
      FoodExpiryUrgency.normal => colors.onSurface,
    };

Duration delayUntilNextLocalMidnight(DateTime now) =>
    DateTime(now.year, now.month, now.day + 1).difference(now);

typedef FoodExpirationSchedule =
    Timer Function(Duration delay, void Function() callback);

/// Owns only local display invalidation; it cannot read or mutate Food history.
/// The injected clock must supply the device's local calendar time.
class FoodExpirationClock extends ChangeNotifier with WidgetsBindingObserver {
  FoodExpirationClock({
    DateTime Function()? now,
    FoodExpirationSchedule? schedule,
  }) : _now = now ?? DateTime.now,
       _schedule = schedule ?? Timer.new {
    _today = _date(_now());
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (_active) refresh();
  }

  final DateTime Function() _now;
  final FoodExpirationSchedule _schedule;
  late DateTime _today;
  DateTime get today => _today;
  Timer? _timer;
  bool _active = false, _disposed = false;
  int _generation = 0;

  static DateTime _date(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void refresh() {
    if (_disposed || !_active) return;
    _cancel();
    final generation = _generation;
    final now = _now(), date = _date(now);
    if (date != _today) {
      _today = date;
      notifyListeners();
    }
    // A listener can suspend or refresh this clock synchronously.
    if (_disposed || !_active || generation != _generation) return;
    _timer = _schedule(delayUntilNextLocalMidnight(now), () {
      if (_disposed || !_active || generation != _generation) return;
      _timer = null;
      refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    _active = state == AppLifecycleState.resumed;
    if (_active) {
      refresh();
    } else {
      _cancel();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
