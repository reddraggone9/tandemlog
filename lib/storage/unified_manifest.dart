import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../domain/event.dart';
import '../food/food_record.dart';
import 'unified_record.dart';

String bytesDigest(List<int> bytes) => sha256.convert(bytes).toString();

class LegacySeal {
  LegacySeal(
    this.name,
    this.owner,
    this.kind,
    this.length,
    this.digest,
    this.count,
    this.head,
  );
  final String name, owner, kind, digest, head;
  final int length, count;
  Map<String, dynamic> toJson() => {
    'name': name,
    'owner': owner,
    'kind': kind,
    'length': length,
    'digest': digest,
    'count': count,
    'head': head,
  };
  factory LegacySeal.fromJson(Map<String, dynamic> j) {
    if (j.length != 7) throw FormatFailure('Unknown legacy seal fields.');
    return LegacySeal(
      j['name'] as String,
      j['owner'] as String,
      j['kind'] as String,
      j['length'] as int,
      j['digest'] as String,
      j['count'] as int,
      j['head'] as String,
    );
  }
}

/// The activation manifest binds the exact migration prefix; later events grow
/// the same file. Source seals are proofs, not live module streams.
class UnifiedManifest {
  UnifiedManifest(
    this.space,
    this.epoch,
    this.sourceDigest,
    Map<String, Map<String, dynamic>> owners,
    Iterable<LegacySeal> seals, {
    this.ready = true,
  }) : owners = Map.unmodifiable(
         owners.map(
           (k, v) => MapEntry(k, Map<String, dynamic>.unmodifiable(v)),
         ),
       ),
       seals = List.unmodifiable(seals) {
    if (!isCanonicalId(space) ||
        !isCanonicalId(epoch) ||
        !isEventHash(sourceDigest) ||
        owners.isEmpty ||
        owners.length > 256 ||
        owners.keys.any((id) => !isCanonicalId(id))) {
      throw FormatFailure('Invalid app activation manifest.');
    }
    for (final entry in owners.entries) {
      final j = entry.value;
      if (j.length != 3 ||
          j['count'] is! int ||
          (j['count'] as int) < 0 ||
          !isEventHash(j['head']) ||
          !isEventHash(j['digest'])) {
        throw FormatFailure('Invalid app migration prefix.');
      }
    }
    final names = <String>{};
    for (final seal in this.seals) {
      if (!owners.containsKey(seal.owner) ||
          !names.add(seal.name) ||
          !{'legacy.task', 'legacy.food'}.contains(seal.kind) ||
          seal.length < 0 ||
          seal.count < 0 ||
          !isEventHash(seal.digest) ||
          !isEventHash(seal.head) ||
          seal.name !=
              (seal.kind == 'legacy.task'
                  ? '${seal.owner}.jsonl'
                  : foodLogName(foodWriter(seal.owner)))) {
        throw FormatFailure('Invalid app legacy source seal.');
      }
    }
  }
  final String space, epoch, sourceDigest;
  final bool ready;
  final Map<String, Map<String, dynamic>> owners;
  final List<LegacySeal> seals;
  String get digest => bytesDigest(utf8.encode(encode()));
  String ownerOfLegacy(String semanticWriter, String kind) {
    if (kind.endsWith('task') && owners.containsKey(semanticWriter)) {
      return semanticWriter;
    }
    final matches = owners.keys.where(
      (owner) => foodWriter(owner) == semanticWriter,
    );
    if (kind.endsWith('food') && matches.length == 1) return matches.single;
    throw FormatFailure(
      'Historical writer has no authorized installation mapping.',
    );
  }

  Map<String, dynamic> toJson() => {
    'v': unifiedProtocol,
    'ready': ready,
    'id': space,
    'epoch': epoch,
    'sourceDigest': sourceDigest,
    'owners': owners,
    'legacySeals': seals.map((s) => s.toJson()).toList(),
  };
  UnifiedManifest staged() =>
      UnifiedManifest(space, epoch, sourceDigest, owners, seals, ready: false);
  String encode() => canonicalDataJson(toJson());
  factory UnifiedManifest.decode(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j.length != 7 || j['v'] != unifiedProtocol || j['ready'] is! bool) {
        throw FormatFailure(
          'Unknown app manifest. Update the app; history was preserved.',
        );
      }
      final result = UnifiedManifest(
        j['id'] as String,
        j['epoch'] as String,
        j['sourceDigest'] as String,
        (j['owners'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
        ),
        (j['legacySeals'] as List).map(
          (v) => LegacySeal.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
        ready: j['ready'] as bool,
      );
      if (result.encode() != raw) {
        throw FormatFailure('Noncanonical app manifest.');
      }
      return result;
    } on FormatFailure {
      rethrow;
    } catch (e) {
      throw FormatFailure('Invalid app manifest: $e');
    }
  }
}

class CutoverAcknowledgement {
  const CutoverAcknowledgement(
    this.writer,
    this.snapshotDigest, {
    required this.quiesced,
    required this.pendingResolved,
    this.readerVersion = unifiedProtocol,
  });
  final String writer, snapshotDigest;
  final bool quiesced, pendingResolved;
  final int readerVersion;
}

class UnifiedConversion {
  UnifiedConversion(this.manifest, this.files, this.originalEffects);
  final UnifiedManifest manifest;
  final Map<String, List<int>> files;
  final List<UnifiedEffect> originalEffects;
}

/// Pure, repeatable conversion. Callers must validate protected observations and
/// collect explicit participant attestations; this routine does not pause peers.
class UnifiedCutoverPlan {
  UnifiedCutoverPlan._(
    this.space,
    this.owners,
    this.participants,
    this.effects,
    this.seals,
    this.sourceDigest,
  );
  final String space, sourceDigest;
  final Set<String> owners, participants;
  final Map<String, List<UnifiedEffect>> effects;
  final List<LegacySeal> seals;

  factory UnifiedCutoverPlan.inspect({
    required String space,
    required Set<String> owners,
    required Set<String> participants,
    required Map<String, List<int>> sources,
    required bool hasUnresolvedPreparedWrites,
  }) {
    if (!isCanonicalId(space) ||
        owners.isEmpty ||
        owners.length > 256 ||
        owners.any((o) => !isCanonicalId(o)) ||
        participants.isEmpty ||
        participants.any((o) => !isCanonicalId(o)) ||
        hasUnresolvedPreparedWrites) {
      throw FormatFailure(
        'Cutover requires known owners and resolved prepared writes.',
      );
    }
    final effects = {for (final o in owners) o: <UnifiedEffect>[]};
    final seals = <LegacySeal>[];
    var totalBytes = 0;
    final names = sources.keys.toList()..sort();
    for (final name in names) {
      final task = name.endsWith('.jsonl');
      final matches = owners
          .where(
            (o) => name == (task ? '$o.jsonl' : foodLogName(foodWriter(o))),
          )
          .toList();
      if (matches.length != 1) {
        throw FormatFailure(
          'Unrecognized, conflicting or unowned legacy file $name.',
        );
      }
      final owner = matches.single, bytes = sources[name]!;
      totalBytes += bytes.length;
      if (totalBytes > maximumUnifiedWorkspaceBytes) {
        throw FormatFailure(
          'Legacy sources exceed the safe app workspace budget.',
        );
      }
      if (bytes.length > 64 * 1024 * 1024 ||
          (bytes.isNotEmpty && bytes.last != 10)) {
        throw FormatFailure(
          'Legacy file is incomplete or exceeds safe limits.',
        );
      }
      final kind = task ? 'legacy.task' : 'legacy.food';
      var sequence = 0;
      EventClock? clock;
      var head = eventGenesisHash(space, task ? owner : foodWriter(owner));
      final lines = utf8.decode(bytes).split('\n');
      for (final raw in lines.take(lines.length - 1)) {
        final e = UnifiedEffect(kind, raw);
        if (e.space != space ||
            e.writer != (task ? owner : foodWriter(owner)) ||
            e.sequence != sequence + 1 ||
            e.previousHash != head ||
            (clock != null && e.clock <= clock)) {
          throw FormatFailure(
            'Legacy chain, identity or clock differs in $name.',
          );
        }
        sequence++;
        clock = e.clock;
        head = e.semanticHash;
        effects[owner]!.add(e);
      }
      seals.add(
        LegacySeal(
          name,
          owner,
          kind,
          bytes.length,
          bytesDigest(bytes),
          sequence,
          head,
        ),
      );
    }
    final root = bytesDigest(
      utf8.encode(
        canonicalDataJson({
          'v': 1,
          'space': space,
          'owners': owners.toList()..sort(),
          'participants': participants.toList()..sort(),
          'sources': seals.map((s) => s.toJson()).toList(),
        }),
      ),
    );
    return UnifiedCutoverPlan._(
      space,
      Set.unmodifiable(owners),
      Set.unmodifiable(participants),
      Map.unmodifiable(
        effects.map((k, v) => MapEntry(k, List<UnifiedEffect>.unmodifiable(v))),
      ),
      List.unmodifiable(seals),
      root,
    );
  }

  UnifiedConversion convert(Iterable<CutoverAcknowledgement> acknowledgements) {
    final acknowledgementsByWriter = <String, CutoverAcknowledgement>{};
    for (final a in acknowledgements) {
      if (!participants.contains(a.writer) ||
          acknowledgementsByWriter.containsKey(a.writer) ||
          !a.quiesced ||
          !a.pendingResolved ||
          a.readerVersion != unifiedProtocol ||
          a.snapshotDigest != sourceDigest) {
        throw FormatFailure(
          'Participant is not upgraded, quiesced or synchronized.',
        );
      }
      acknowledgementsByWriter[a.writer] = a;
    }
    if (!acknowledgementsByWriter.keys.toSet().containsAll(participants)) {
      throw FormatFailure(
        'Missing/offline participant: coordinate or explicitly retire it.',
      );
    }
    return prepareConversion();
  }

  /// Prospective deterministic bytes only. This does not authorize staging or
  /// activation; callers must separately collect real participant receipts.
  UnifiedConversion prepareConversion() {
    final epoch = const Uuid().v5(
      space,
      'tandemlog:app-cutover:v4:$sourceDigest',
    );
    final files = <String, List<int>>{},
        heads = <String, Map<String, dynamic>>{};
    final originals = <UnifiedEffect>[];
    final orderedOwners = owners.toList()..sort();
    for (final owner in orderedOwners) {
      final ordered = List<UnifiedEffect>.of(effects[owner]!)
        ..sort((a, b) {
          final clock = a.clock.compareTo(b.clock);
          if (clock != 0) return clock;
          final kind = a.kind.compareTo(b.kind);
          if (kind != 0) return kind;
          final writer = a.writer.compareTo(b.writer);
          return writer != 0 ? writer : a.sequence.compareTo(b.sequence);
        });
      var head = unifiedGenesis(space, epoch, owner), sequence = 0;
      EventClock? clock;
      final output = StringBuffer();
      for (final e in ordered) {
        clock = EventClock.next(e.clock.value, clock);
        final record = UnifiedRecord(
          space: space,
          epoch: epoch,
          writer: owner,
          sequence: ++sequence,
          clock: clock,
          previousHash: head,
          effect: e,
          transactionStart: sequence,
          transactionCount: 1,
          transactionIndex: 0,
        );
        output.writeln(record.encode());
        head = record.hash;
        originals.add(e);
      }
      final bytes = utf8.encode(output.toString());
      if (bytes.length > maximumUnifiedFileBytes ||
          files.values.fold<int>(0, (n, b) => n + b.length) + bytes.length >
              maximumUnifiedWorkspaceBytes) {
        throw FormatFailure(
          'Converted history exceeds safe app read budgets; originals remain intact.',
        );
      }
      files[unifiedLogName(owner)] = Uint8List.fromList(
        bytes,
      ).asUnmodifiableView();
      heads[owner] = {
        'count': sequence,
        'head': head,
        'digest': bytesDigest(bytes),
      };
    }
    return UnifiedConversion(
      UnifiedManifest(space, epoch, sourceDigest, heads, seals),
      Map.unmodifiable(files),
      List.unmodifiable(originals),
    );
  }
}
