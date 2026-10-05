import 'event.dart';
export 'event.dart' show validateTextInheritance;

class TextInheritanceVerification {
  TextInheritanceVerification(
    Iterable<String> missing,
    Iterable<LogEvent> prefix,
  ) : missingFrontiers = Set.unmodifiable(missing),
      observedPrefix = List.unmodifiable(prefix);
  final Set<String> missingFrontiers;
  final List<LogEvent> observedPrefix;
  bool get isPending => missingFrontiers.isNotEmpty;
}

/// Available records must already have passed canonical stream admission. This
/// verifies declared heads, not signatures or native checkpoint contents.
TextInheritanceVerification verifyTextInheritance(
  Map<String, dynamic> descriptor, {
  required LogEvent completion,
  required Iterable<LogEvent> available,
}) {
  validateTextInheritance(descriptor);
  final records = <String, LogEvent>{};
  for (final event in available) {
    if (event.space != completion.space) continue;
    final previous = records[event.id];
    if (previous != null && previous.hash != event.hash) {
      throw FormatFailure('Conflicting canonical inheritance records.');
    }
    records[event.id] = event;
  }
  final frontiers = descriptor['frontiers'] as Map<String, dynamic>;
  final missing = <String>{};
  for (final entry in frontiers.entries) {
    final frontier = entry.value as Map<String, dynamic>;
    final seq = frontier['seq'] as int;
    if (entry.key == completion.writer && seq >= completion.sequence) {
      throw FormatFailure(
        'Text inheritance cannot reference a forward operation.',
      );
    }
    if (seq == 0) {
      if (frontier['hash'] != eventGenesisHash(completion.space, entry.key)) {
        throw FormatFailure('Text inheritance genesis hash mismatch.');
      }
      continue;
    }
    final id = '${entry.key}:$seq';
    final head = records[id];
    if (head == null) {
      missing.add(id);
      continue;
    }
    if (head.hash != frontier['hash']) {
      throw FormatFailure('Text inheritance frontier hash mismatch.');
    }
    if (head.clock >= completion.clock) {
      throw FormatFailure('Text inheritance cannot reference a forward clock.');
    }
  }
  final prefix = records.values.where((event) {
    final frontier = frontiers[event.writer] as Map<String, dynamic>?;
    return frontier != null && event.sequence <= (frontier['seq'] as int);
  }).toList()..sort(compareEvents);
  for (final event in prefix) {
    if (event.clock >= completion.clock) {
      throw FormatFailure(
        'Text inheritance observed prefix has a forward clock.',
      );
    }
  }
  return TextInheritanceVerification(missing, prefix);
}
