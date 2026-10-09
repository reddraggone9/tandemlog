/// Explicit immutable identifiers for the existing task module. SQL sites
/// interpolate these names deliberately; no runtime SQL rewriting or mutable
/// connection-wide aliases are used.
class TaskTables {
  const TaskTables.legacy() : _prefix = '';
  TaskTables.forLocation(String locationKey)
    : _prefix = _validatedPrefix(locationKey);
  final String _prefix;

  static String _validatedPrefix(String key) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
      throw ArgumentError('A task namespace needs a canonical location key.');
    }
    return 'tasks_${key}_';
  }

  String get events => '${_prefix}events';
  String get views => '${_prefix}views';
  String get streams => '${_prefix}streams';
  String get streamRanges => '${_prefix}stream_ranges';
  String get metadata => '${_prefix}metadata';
  String get positions => '${_prefix}positions';
  String get textFields => '${_prefix}text_fields';
  String get textActors => '${_prefix}text_actors';
  String get textOutbox => '${_prefix}text_outbox';
  String get eventsEntity => '${events}_entity';
  String get eventsType => '${events}_type';
  String get eventsClock => '${events}_clock';
  String get eventsSuccessor => '${events}_successor';
}
