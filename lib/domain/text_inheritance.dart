import 'dart:convert';
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
  // Preserve validation-before-iteration behavior of the single-call API.
  validateTextInheritance(descriptor);
  return TextInheritanceIndex(
    available,
  ).verify(descriptor, completion: completion);
}

/// One exact input snapshot shared by multiple descriptor checks. No index
/// crosses an input revision, and observed subresolvers create their own index.
class TextInheritanceIndex {
  TextInheritanceIndex(Iterable<LogEvent> available)
    : _available = List.unmodifiable(available);
  TextInheritanceIndex.appended(
    TextInheritanceIndex prior,
    List<LogEvent> added,
  ) : _available = List.unmodifiable([...prior._available, ...added]) {
    for (final entry in prior._spaces.entries) {
      final records = Map<String, LogEvent>.of(entry.value.$1);
      for (final event in added.where((event) => event.space == entry.key)) {
        final previous = records[event.id];
        if (previous != null && previous.hash != event.hash) {
          throw FormatFailure('Conflicting canonical inheritance records.');
        }
        records[event.id] = event;
      }
      final suffix = added.where((event) => event.space == entry.key).toList();
      final oldOrdered = entry.value.$2;
      final fresh =
          suffix.map((event) => event.id).toSet().length == suffix.length &&
          suffix.every((event) => !entry.value.$1.containsKey(event.id));
      final later =
          suffix.isEmpty ||
          oldOrdered.isEmpty ||
          compareEvents(oldOrdered.last, suffix.first) < 0;
      final orderedSuffix = Iterable<int>.generate(
        suffix.isEmpty ? 0 : suffix.length - 1,
      ).every((i) => compareEvents(suffix[i], suffix[i + 1]) < 0);
      final ordered = fresh && later && orderedSuffix
          ? [...oldOrdered, ...suffix]
          : (records.values.toList()..sort(compareEvents));
      _spaces[entry.key] = (
        Map.unmodifiable(records),
        List.unmodifiable(ordered),
      );
    }
    for (final entry in prior._verified.entries) {
      final cut = entry.value;
      if (added.every(
        (event) =>
            event.space != cut.space ||
            event.sequence > (cut.frontiers[event.writer] ?? -1),
      )) {
        _remember(entry.key, cut);
      }
    }
  }
  final List<LogEvent> _available;
  final _spaces = <String, (Map<String, LogEvent>, List<LogEvent>)>{};
  final _verified = <String, _VerifiedInheritanceCut>{};
  static const maximumCachedCuts = 128;
  static const maximumCachedCutBytes = 2 * 1024 * 1024;
  int retainedCutBytes = 0, verifiedCutHits = 0, verifiedCutScans = 0;
  int get cachedCutCount => _verified.length;
  void _remember(String key, _VerifiedInheritanceCut cut) {
    if (cut.bytes > maximumCachedCutBytes) return;
    final old = _verified.remove(key);
    if (old != null) retainedCutBytes -= old.bytes;
    while (_verified.isNotEmpty &&
        (_verified.length >= maximumCachedCuts ||
            retainedCutBytes + cut.bytes > maximumCachedCutBytes)) {
      retainedCutBytes -= _verified.remove(_verified.keys.first)!.bytes;
    }
    _verified[key] = cut;
    retainedCutBytes += cut.bytes;
  }

  (Map<String, LogEvent>, List<LogEvent>) _space(String space) =>
      _spaces.putIfAbsent(space, () {
        final records = <String, LogEvent>{};
        // Foreign-space conflicts must not affect the space being verified.
        for (final event in _available) {
          if (event.space != space) continue;
          final previous = records[event.id];
          if (previous != null && previous.hash != event.hash) {
            throw FormatFailure('Conflicting canonical inheritance records.');
          }
          records[event.id] = event;
        }
        final ordered = records.values.toList()..sort(compareEvents);
        return (Map.unmodifiable(records), List.unmodifiable(ordered));
      });

  TextInheritanceVerification verify(
    Map<String, dynamic> descriptor, {
    required LogEvent completion,
  }) {
    validateTextInheritance(descriptor);
    final key = jsonEncode([
      completion.space,
      completion.writer,
      completion.sequence,
      completion.clock.toJson(),
      completion.hash,
      completion.integrityHash,
      descriptor,
    ]);
    final remembered = _verified.remove(key);
    if (remembered != null) {
      _verified[key] = remembered;
      verifiedCutHits++;
      return remembered.verification;
    }
    verifiedCutScans++;
    final (records, ordered) = _space(completion.space);
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
        throw FormatFailure(
          'Text inheritance cannot reference a forward clock.',
        );
      }
    }
    final prefix = ordered.where((event) {
      final frontier = frontiers[event.writer] as Map<String, dynamic>?;
      return frontier != null && event.sequence <= (frontier['seq'] as int);
    }).toList();
    for (final event in prefix) {
      if (event.clock >= completion.clock) {
        throw FormatFailure(
          'Text inheritance observed prefix has a forward clock.',
        );
      }
    }
    final verification = TextInheritanceVerification(missing, prefix);
    if (!verification.isPending) {
      _remember(
        key,
        _VerifiedInheritanceCut(
          verification,
          completion.space,
          Map.unmodifiable(
            frontiers.map(
              (writer, value) => MapEntry(writer, (value as Map)['seq'] as int),
            ),
          ),
          key.length * 2 + prefix.length * 16 + frontiers.length * 128 + 256,
        ),
      );
    }
    return verification;
  }
}

class _VerifiedInheritanceCut {
  const _VerifiedInheritanceCut(
    this.verification,
    this.space,
    this.frontiers,
    this.bytes,
  );
  final TextInheritanceVerification verification;
  final String space;
  final Map<String, int> frontiers;
  final int bytes;
}
