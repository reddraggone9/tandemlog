import 'event.dart';
import 'wall_time.dart';

/// Permission belongs to an admitted workspace manifest, never process state.
/// Codecs may understand a name without permission to admit or reserve it.
enum TimeZoneNamePolicy {
  legacy,
  additional2026eV1;

  bool get allowsAdditionalTimeZones => this == additional2026eV1;

  void assertScheduleAllowed(Map<String, dynamic> schedule) {
    _assertNameAllowed(schedule['timeZone']);
  }

  void _assertNameAllowed(Object? name) {
    if (!allowsAdditionalTimeZones && additionalTimeZoneNames.contains(name)) {
      throw const TimeZoneUpgradeRequired();
    }
  }

  void assertTaskEventAllowed(LogEvent event) {
    void check(dynamic value) {
      if (value is Map) _assertNameAllowed(value['timeZone']);
    }

    check(event.data['schedule']);
    final successor = event.data['successor'];
    if (successor is Map) check(successor['schedule']);
    final nonText = event.data['nonText'];
    if (nonText is Map) {
      check(nonText['schedule']);
      final successor = nonText['successor'];
      if (successor is Map) check(successor['schedule']);
    }
  }
}
