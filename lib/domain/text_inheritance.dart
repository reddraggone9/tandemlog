import 'dart:convert';
import 'event.dart';
export 'event.dart' show validateTextInheritance;

sealed class TextResolutionCut {
  bool get isPending;
  List<LogEvent> get recordsForResolution;
}

class TextInheritanceVerification extends TextResolutionCut {
  TextInheritanceVerification(
    Iterable<String> missing,
    Iterable<LogEvent> prefix,
  ) : missingFrontiers = Set.unmodifiable(missing),
      observedPrefix = List.unmodifiable(prefix);
  final Set<String> missingFrontiers;
  final List<LogEvent> observedPrefix;
  @override
  bool get isPending => missingFrontiers.isNotEmpty;
  @override
  List<LogEvent> get recordsForResolution => observedPrefix;
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

/// Selected dependency records never stand in for a complete generic prefix.
/// This private cut identity is minted only by its immutable selected index.
final class SelectedTextInheritanceCut extends TextResolutionCut {
  SelectedTextInheritanceCut._(
    this.index,
    this.frontiers,
    Iterable<String> missing,
    Iterable<LogEvent> selected,
  ) : missingFrontiers = Set.unmodifiable(missing),
      recordsForResolution = List.unmodifiable(selected);
  final SelectedTextInheritanceIndex index;
  final Map<String, int> frontiers;
  final Set<String> missingFrontiers;
  @override
  final List<LogEvent> recordsForResolution;
  @override
  bool get isPending => missingFrontiers.isNotEmpty;
}

/// Pure selection under a complete owning canonical read scope. Storage checks
/// that scope; this index has no database or transport access. Generic sparse
/// and arbitrary list inputs continue to use TextInheritanceIndex unchanged.
final class SelectedTextInheritanceIndex {
  factory SelectedTextInheritanceIndex.fromCanonical(
    Iterable<String> raw,
    Map<String, String> headRaws,
    Map<String, int> availableSequences,
  ) {
    final records = <String, LogEvent>{};
    var decoded = 0;
    for (final value in raw) {
      final event = _freezeSelectedEvent(LogEvent.decode(value));
      decoded++;
      final old = records[event.id];
      if (old != null && old.canonicalRaw != event.canonicalRaw) {
        throw FormatFailure('Conflicting text lineage records.');
      }
      records[event.id] = event;
    }
    final ordered = records.values.toList()..sort(compareEvents);
    return SelectedTextInheritanceIndex._(
      ordered,
      headRaws,
      availableSequences,
      _SelectedDecodeCounter(decoded),
    );
  }
  SelectedTextInheritanceIndex._(
    Iterable<LogEvent> selected,
    Map<String, String> headRaws,
    Map<String, int> availableSequences, [
    _SelectedDecodeCounter? counter,
    Map<String, LogEvent>? decodedHeads,
  ]) : _decodeCounter = counter ?? _SelectedDecodeCounter(0),
       _heads = decodedHeads ?? <String, LogEvent>{},
       records = List.unmodifiable(selected),
       headRaws = Map.unmodifiable(headRaws),
       availableSequences = Map.unmodifiable(availableSequences),
       _byId = Map.unmodifiable({
         for (final event in selected) event.id: event,
       });
  final List<LogEvent> records;
  final Map<String, LogEvent> _byId;
  final Map<String, String> headRaws;
  final Map<String, int> availableSequences;
  final Map<String, LogEvent> _heads;
  final _SelectedDecodeCounter _decodeCounter;
  final _cuts = <String, SelectedTextInheritanceCut>{};
  final _cutCosts = <String, int>{};
  int _retainedCutBytes = 0;
  int get decodedRecordCount => _decodeCounter.count;

  SelectedTextInheritanceIndex forCut(SelectedTextInheritanceCut cut) {
    if (!identical(cut.index, this) || cut.isPending) {
      throw StateError('Selected cut belongs to another immutable input.');
    }
    return SelectedTextInheritanceIndex._(
      cut.recordsForResolution,
      headRaws,
      {
        for (final entry in cut.frontiers.entries)
          entry.key: entry.value < (availableSequences[entry.key] ?? 0)
              ? entry.value
              : (availableSequences[entry.key] ?? 0),
      },
      _decodeCounter,
      _heads,
    );
  }

  SelectedTextInheritanceCut verify(
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
    final old = _cuts[key];
    if (old != null) return old;
    final frontiers = descriptor['frontiers'] as Map<String, dynamic>;
    final bounds = <String, int>{}, missing = <String>{};
    for (final entry in frontiers.entries) {
      final frontier = entry.value as Map<String, dynamic>;
      final seq = frontier['seq'] as int;
      bounds[entry.key] = seq;
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
      final raw = headRaws[id];
      if (seq > (availableSequences[entry.key] ?? 0) || raw == null) {
        missing.add(id);
        continue;
      }
      final head = _heads.putIfAbsent(id, () {
        _decodeCounter.count++;
        return _freezeSelectedEvent(LogEvent.decode(raw));
      });
      if (_byId[id] != null && _byId[id]!.canonicalRaw != raw) {
        throw FormatFailure(
          'Selected frontier record differs from selected history.',
        );
      }
      if (head.space != completion.space ||
          head.id != id ||
          head.hash != frontier['hash']) {
        throw FormatFailure('Text inheritance frontier hash mismatch.');
      }
      if (head.clock >= completion.clock) {
        throw FormatFailure(
          'Text inheritance cannot reference a forward clock.',
        );
      }
    }
    final prefix = records
        .where(
          (event) =>
              event.space == completion.space &&
              event.sequence <= (bounds[event.writer] ?? -1),
        )
        .toList();
    if (prefix.any((event) => event.clock >= completion.clock)) {
      throw FormatFailure(
        'Text inheritance observed prefix has a forward clock.',
      );
    }
    final result = SelectedTextInheritanceCut._(
      this,
      Map.unmodifiable(bounds),
      missing,
      prefix,
    );
    if (!result.isPending) {
      final cost =
          key.length * 2 + prefix.length * 16 + bounds.length * 128 + 256;
      if (cost <= TextInheritanceIndex.maximumCachedCutBytes) {
        while (_cuts.isNotEmpty &&
            (_cuts.length >= TextInheritanceIndex.maximumCachedCuts ||
                _retainedCutBytes + cost >
                    TextInheritanceIndex.maximumCachedCutBytes)) {
          final first = _cuts.keys.first;
          _cuts.remove(first);
          _retainedCutBytes -= _cutCosts.remove(first)!;
        }
        _cuts[key] = result;
        _cutCosts[key] = cost;
        _retainedCutBytes += cost;
      }
    }
    return result;
  }
}

Object? _freezeSelectedJson(Object? value) => switch (value) {
  Map<String, dynamic>() => Map<String, dynamic>.unmodifiable(
    value.map((key, item) => MapEntry(key, _freezeSelectedJson(item))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freezeSelectedJson)),
  _ => value,
};
LogEvent _freezeSelectedEvent(LogEvent event) => LogEvent(
  event.space,
  event.writer,
  event.sequence,
  event.clock,
  event.entity,
  event.type,
  _freezeSelectedJson(event.data) as Map<String, dynamic>,
  previousHash: event.previousHash,
  hash: event.hash,
  canonicalRaw: event.canonicalRaw,
  attributedWriter: event.attributedWriter,
  integrityHash: event.integrityHash,
  operationRevision: event.operationRevision,
);

final class _SelectedDecodeCounter {
  _SelectedDecodeCounter(this.count);
  int count;
}
