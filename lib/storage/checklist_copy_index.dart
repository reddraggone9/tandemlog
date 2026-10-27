import '../domain/event.dart';

/// Disposable lookup over immutable, already admitted checklist descriptors.
/// A null build means use the original SQL lookup for the entire scope.
class ChecklistCopyIndex {
  ChecklistCopyIndex._(this._claims);
  final Map<String, List<(LogEvent, Map<String, dynamic>)>> _claims;
  List<(LogEvent, Map<String, dynamic>)> operator [](String id) =>
      _claims[id] ?? const [];

  static ChecklistCopyIndex? build(
    Iterable<LogEvent> completions, {
    int maximumClaims = 2048,
    int maximumPayloadBytes = 4 * 1024 * 1024,
  }) {
    if (maximumClaims < 1 || maximumPayloadBytes < 1) {
      throw ArgumentError('Invalid checklist lookup budget.');
    }
    final ordered = <LogEvent>[];
    var payload = 0, count = 0;
    for (final completion in completions) {
      final raw = completion.canonicalRaw;
      if (raw == null || completion.type != 'task.completedWithChecklist') {
        throw FormatFailure('Checklist lookup requires canonical completions.');
      }
      payload += raw.length * 4;
      for (final item
          in (completion.data['checklist'] as Map)['items'] as List) {
        count++;
        payload += ((item as Map)['id'] as String).length * 2 + 64;
        if (count > maximumClaims || payload > maximumPayloadBytes) return null;
      }
      if (payload > maximumPayloadBytes) return null;
      ordered.add(completion);
    }
    ordered.sort(compareEvents);
    final claims = <String, List<(LogEvent, Map<String, dynamic>)>>{};
    for (final completion in ordered) {
      for (final item
          in (completion.data['checklist'] as Map)['items'] as List) {
        final value = Map<String, dynamic>.unmodifiable(item as Map);
        (claims[value['id'] as String] ??= []).add((completion, value));
      }
    }
    return ChecklistCopyIndex._(
      Map<String, List<(LogEvent, Map<String, dynamic>)>>.unmodifiable({
        for (final entry in claims.entries)
          entry.key: List<(LogEvent, Map<String, dynamic>)>.unmodifiable(
            entry.value,
          ),
      }),
    );
  }
}
