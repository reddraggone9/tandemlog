import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/event.dart';
import '../food/food_record.dart';
import '../food/inventory.dart' show FoodAction;
import '../domain/validated_action_cache.dart';
import '../domain/utf8_byte_limit.dart';

const unifiedProtocol = 5;
const maximumUnifiedFileBytes = 32 * 1024 * 1024;
const maximumUnifiedWorkspaceBytes = 256 * 1024 * 1024;
const maximumUnifiedRecordBytes = 16 * 1024 * 1024;

String unifiedGenesis(String space, String epoch, String writer) => sha256
    .convert(utf8.encode('tandemlog:app-genesis:v5\n$space\n$epoch\n$writer'))
    .toString();

/// An immutable semantic event. Historical bytes are evidence, never a second
/// active writer or allocator. Physical positions and semantic IDs are distinct.
class UnifiedEffect {
  UnifiedEffect(this.kind, this.raw) {
    if (!{
      'history.task',
      'history.food',
      'task',
      'food',
      'writer.named',
      'writer.joined',
    }.contains(kind)) {
      throw FormatFailure(
        'Unknown app event $kind. Update the app; history was preserved.',
      );
    }
    if (kind == 'writer.joined') {
      if (raw != '{}') throw FormatFailure('Invalid installation header.');
    } else if (kind == 'writer.named') {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic> ||
          j.length != 1 ||
          !j.containsKey('name') ||
          (j['name'] != null && j['name'] is! String) ||
          canonicalDataJson(j) != raw) {
        throw FormatFailure('Invalid device name event.');
      }
      final value = j['name'] as String?;
      if (value != null &&
          (value.isEmpty ||
              value.trim() != value ||
              value.runes.length > 80 ||
              value.runes.any((r) => r < 32 || r == 127))) {
        throw FormatFailure(
          'Device name must be at most 80 characters without controls.',
        );
      }
      _name = value;
    } else if (kind.endsWith('task')) {
      _task = LogEvent.decode(raw);
    } else {
      _food = FoodRecord.decode(raw);
    }
  }
  UnifiedEffect._cachedTask(this.kind, this.raw, this._task);
  UnifiedEffect._cachedFood(this.kind, this.raw, this._food);
  final String kind, raw;
  // Exact source identity for pure admission memo keys. Compute once per
  // immutable decoded effect instead of reserializing every prior payload.
  late final String validationDigest = sha256
      .convert(utf8.encode(raw))
      .toString();
  String? _name;
  String? get name => _name;
  bool get isData => task != null || food != null;
  factory UnifiedEffect.joined() => UnifiedEffect('writer.joined', '{}');
  factory UnifiedEffect.named(String? value) {
    final name = value?.trim();
    return UnifiedEffect(
      'writer.named',
      canonicalDataJson({'name': name == null || name.isEmpty ? null : name}),
    );
  }
  LogEvent? _task;
  FoodRecord? _food;
  LogEvent? get task => _task;
  FoodRecord? get food => _food;
  bool get historical => kind.startsWith('history.');
  String get space => task?.space ?? food!.space;
  String get writer => task?.writer ?? food!.writer;
  int get sequence => task?.sequence ?? food!.sequence;
  EventClock get clock => task?.clock ?? food!.clock;
  String get id => task?.id ?? food!.id;
  String get author => task?.author ?? food!.author;
  String get integrityHash => task?.integrityHash ?? food!.integrityHash;
  String get semanticHash => task?.hash ?? food!.hash;
  String get previousHash => task?.previousHash ?? food!.previousHash;
  // This immutable envelope identity carries no readiness or admission proof.
  // Keep its String/hash representation instead of rebuilding it per refresh.
  late final String _key = '${task == null ? 'food:' : 'task:'}$space:$id';
  String get key => _key;
  Map<String, dynamic> toJson() => {'kind': kind, 'raw': raw};
}

class UnifiedFrontier {
  const UnifiedFrontier(this.sequence, this.hash);
  final int sequence;
  final String hash;
  Map<String, dynamic> toJson() => {'seq': sequence, 'hash': hash};
}

class UnifiedRecord {
  UnifiedRecord({
    required this.space,
    required this.epoch,
    required this.writer,
    required this.sequence,
    required this.clock,
    required this.previousHash,
    UnifiedEffect? effect,
    List<UnifiedEffect>? effects,
    Map<String, UnifiedFrontier> observed = const {},
    Map<String, dynamic>? provenance,
  }) : effects = List.unmodifiable(effects ?? [effect!]),
       observed = Map.unmodifiable(observed),
       provenance = provenance == null ? null : Map.unmodifiable(provenance) {
    if ((effect == null) == (effects == null) ||
        this.effects.isEmpty ||
        this.effects.length > 10000) {
      throw FormatFailure('Choose one bounded atomic action.');
    }
    final historical = this.effects.every((e) => e.historical);
    if (this.effects.any((e) => e.historical) && !historical ||
        historical && this.effects.length != 1 ||
        observed.length > 256 ||
        observed.entries.any(
          (e) =>
              !isCanonicalId(e.key) ||
              e.value.sequence < 0 ||
              e.value.sequence > 9007199254740991 ||
              !isEventHash(e.value.hash),
        ) ||
        historical && observed.isNotEmpty ||
        !historical &&
            (observed[writer]?.sequence != sequence - 1 ||
                observed[writer]?.hash != previousHash)) {
      throw FormatFailure('Invalid action observed history.');
    }
    if (![space, epoch, writer].every(isCanonicalId) ||
        sequence < 1 ||
        sequence > 9007199254740991 ||
        !isEventHash(previousHash) ||
        clock.value.isNegative ||
        clock.value > EventClock.maximum) {
      throw FormatFailure('Invalid action identity, clock or predecessor.');
    }
    String semanticHead = previousHash;
    EventClock? previousClock;
    int? previousSequence;
    for (final e in this.effects) {
      if (!e.isData) {
        if (this.effects.length != 1 || provenance != null) {
          throw FormatFailure('Installation metadata must be its own action.');
        }
        continue;
      }
      if (e.space != space ||
          e.author != writer ||
          e.clock > clock ||
          !historical &&
              (e.semanticHash != e.integrityHash ||
                  e.writer != writer ||
                  e.previousHash != semanticHead ||
                  previousClock != null && e.clock <= previousClock ||
                  previousSequence != null &&
                      e.sequence != previousSequence + 1)) {
        throw FormatFailure('Effect differs from its atomic action.');
      }
      semanticHead = e.integrityHash;
      previousClock = e.clock;
      previousSequence = e.sequence;
    }
    if (provenance != null) {
      _keys(provenance, {'kind', 'namespace', 'planHash', 'sourceSha256'});
      if (historical ||
          !const {
            'food.import',
            'food.purchase-import',
          }.contains(provenance['kind']) ||
          !isCanonicalId(provenance['namespace']) ||
          !isEventHash(provenance['planHash']) ||
          !isEventHash(provenance['sourceSha256']) ||
          this.effects.any(
            (e) => provenance['kind'] == 'food.import'
                ? e.food?.operation.action.name != 'add'
                : e.food == null ||
                      e.food!.operation.action == FoodAction.edit ||
                      e.food!.operation.action == FoodAction.remove ||
                      e.food!.operation.action == FoodAction.restore ||
                      e.food!.operation.action == FoodAction.undo ||
                      e.food!.operation.action == FoodAction.merge ||
                      e.food!.operation.action == FoodAction.purchaseEdit,
          )) {
        throw FormatFailure('Invalid canonical import provenance.');
      }
    }
    hash = sha256
        .convert(
          utf8.encode('tandemlog:app-action:v5\n${canonicalDataJson(_body())}'),
        )
        .toString();
    if (exceedsUtf8ByteLimit(encode(), maximumUnifiedRecordBytes)) {
      throw FormatFailure(
        'Action exceeds safe record size; nothing was written.',
      );
    }
  }
  UnifiedRecord._cached(Map<String, dynamic> value, this.effects, String raw)
    : space = value['space'] as String,
      epoch = value['epoch'] as String,
      writer = value['writer'] as String,
      sequence = value['seq'] as int,
      clock = EventClock.fromJson(value['clock']),
      previousHash = value['previousHash'] as String,
      observed = Map.unmodifiable(
        (value['observed'] as Map<String, dynamic>).map((key, value) {
          final head = value as Map;
          return MapEntry(
            key,
            UnifiedFrontier(head['seq'] as int, head['hash'] as String),
          );
        }),
      ),
      provenance = value['provenance'] == null
          ? null
          : Map<String, dynamic>.unmodifiable(value['provenance'] as Map) {
    hash = value['hash'] as String;
    _encoded = raw;
  }

  final String space, epoch, writer, previousHash;
  final int sequence;
  final EventClock clock;
  final List<UnifiedEffect> effects;
  final Map<String, UnifiedFrontier> observed;
  final Map<String, dynamic>? provenance;
  late final String hash;
  // Single-effect convenience; action consumers must iterate effects.
  UnifiedEffect get effect => effects.single;
  bool get historical => effects.every((e) => e.historical);
  // Sealed historical bodies retain original clocks while their consolidated
  // physical chain is monotonic. Live effects must follow every observed head.
  EventClock get firstClock =>
      !historical && effects.first.isData ? effects.first.clock : clock;
  String get recordId => 'app:$epoch:$writer:$sequence';
  Map<String, dynamic> _body() => {
    'v': unifiedProtocol,
    'space': space,
    'epoch': epoch,
    'writer': writer,
    'seq': sequence,
    'clock': clock.toJson(),
    'previousHash': previousHash,
    'observed': observed.map((k, v) => MapEntry(k, v.toJson())),
    'effects': effects.map((e) => e.toJson()).toList(),
    'provenance': provenance,
  };
  String? _encoded;
  String encode() => _encoded ??= canonicalDataJson({..._body(), 'hash': hash});
  factory UnifiedRecord.decode(String raw) {
    try {
      if (exceedsUtf8ByteLimit(raw, maximumUnifiedRecordBytes)) {
        throw FormatFailure('Action exceeds safe read limits.');
      }
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic> || j['v'] != unifiedProtocol) {
        throw FormatFailure(
          'Unknown app history version. Update the app; history was preserved.',
        );
      }
      _keys(j, {
        'v',
        'space',
        'epoch',
        'writer',
        'seq',
        'clock',
        'previousHash',
        'observed',
        'effects',
        'provenance',
        'hash',
      });
      final record = UnifiedRecord(
        space: j['space'] as String,
        epoch: j['epoch'] as String,
        writer: j['writer'] as String,
        sequence: j['seq'] as int,
        clock: EventClock.fromJson(j['clock']),
        previousHash: j['previousHash'] as String,
        effects: (j['effects'] as List).map((v) {
          final e = v as Map<String, dynamic>;
          _keys(e, {'kind', 'raw'});
          return UnifiedEffect(e['kind'] as String, e['raw'] as String);
        }).toList(),
        provenance: j['provenance'] as Map<String, dynamic>?,
        observed: (j['observed'] as Map<String, dynamic>).map((k, v) {
          final f = v as Map<String, dynamic>;
          _keys(f, {'seq', 'hash'});
          return MapEntry(
            k,
            UnifiedFrontier(f['seq'] as int, f['hash'] as String),
          );
        }),
      );
      if (record.hash != j['hash'] || record.encode() != raw) {
        throw FormatFailure('Action hash or canonical bytes differ.');
      }
      return record;
    } on FormatFailure {
      rethrow;
    } catch (e) {
      throw FormatFailure('Invalid atomic action: $e');
    }
  }
  static void _keys(Map<String, dynamic> value, Set<String> keys) {
    if (value.length != keys.length ||
        value.keys.any((k) => !keys.contains(k))) {
      throw FormatFailure(
        'Unknown action fields. Update the app; history was preserved.',
      );
    }
  }
}

/// Disposable, clean-close decode reuse. The receipt detects corruption/staleness;
/// it is not authentication against replacement of cache AND its profile proof.
/// Only this whole-batch verifier can construct private cached records/effects.
class UnifiedDecodedCache {
  // Bump the receipt layout for closed validation/normalization changes.
  static const generation = ValidatedActionCache.layout;
  static const maximumBytes = ValidatedActionCache.maximumBytes;

  static String encode(List<UnifiedRecord> records, String binding) =>
      jsonEncode({
        'generation': generation,
        'binding': binding,
        'records': [
          for (final record in records)
            [
              record.encode(),
              [
                for (final effect in record.effects)
                  if (effect.task != null)
                    [effect.kind, _task(effect.task!)]
                  else if (effect.food != null)
                    [effect.kind, _food(effect.food!)]
                  else
                    null,
              ],
            ],
        ],
      });

  static List<Object?> _task(LogEvent event) => [
    event.space,
    event.writer,
    event.sequence,
    event.clock.toJson(),
    event.entity,
    event.type,
    event.data,
    event.previousHash,
    event.hash,
    event.attributedWriter,
    event.integrityHash,
    event.operationRevision,
  ];

  static List<Object?> _food(FoodRecord event) => [
    event.space,
    event.writer,
    event.sequence,
    event.clock.toJson(),
    event.operation.toJson(),
    event.previousHash,
    event.unified,
    event.attributedWriter,
    event.retainedReferenceHash,
    event.createdWith,
    event.hash,
    event.integrityHash,
  ];

  static List<UnifiedRecord> restore(
    String payload,
    String expectedDigest,
    String expectedBinding,
  ) {
    final batch = ValidatedActionCache.verify(
      payload,
      expectedDigest,
      expectedBinding,
    );
    return restoreVerifiedBatch(batch);
  }

  /// Reconstruct only from the existing opaque, deeply immutable verifier
  /// receipt. Startup may perform pure verification in a short-lived isolate;
  /// native owners, profile objects and contextual admission remain here.
  static List<UnifiedRecord> restoreVerifiedBatch(ValidatedActionCache batch) {
    final records = <UnifiedRecord>[];
    for (final action in batch.records) {
      final value = action.value;
      UnifiedRecord._keys(value, {
        'v',
        'space',
        'epoch',
        'writer',
        'seq',
        'clock',
        'previousHash',
        'observed',
        'effects',
        'provenance',
        'hash',
      });
      if (value['v'] != unifiedProtocol) {
        throw const FormatException('Unknown cached action generation.');
      }
      final effects = <UnifiedEffect>[];
      for (final receipt in action.effects) {
        final kind = receipt.kind, raw = receipt.raw;
        if (kind == 'food' || kind == 'history.food') {
          effects.add(
            UnifiedEffect._cachedFood(
              kind,
              raw,
              FoodRecord.fromDecodedCache(receipt),
            ),
          );
          continue;
        }
        if (kind != 'task' && kind != 'history.task') {
          effects.add(UnifiedEffect(kind, raw));
          continue;
        }
        final fields = receipt.fields;
        if (receipt.layout != 3 || fields == null || fields.length != 12) {
          throw const FormatException('Invalid cached Task field mapping.');
        }
        final event = LogEvent(
          fields[0] as String,
          fields[1] as String,
          fields[2] as int,
          EventClock.fromJson(fields[3]),
          fields[4] as String,
          fields[5] as String,
          fields[6] as Map<String, dynamic>,
          previousHash: fields[7] as String?,
          hash: fields[8] as String?,
          attributedWriter: fields[9] as String?,
          integrityHash: fields[10] as String?,
          operationRevision: fields[11] as int?,
          canonicalRaw: raw,
        );
        effects.add(UnifiedEffect._cachedTask(kind, raw, event));
      }
      records.add(
        UnifiedRecord._cached(value, List.unmodifiable(effects), action.raw),
      );
    }
    return List.unmodifiable(records);
  }
}

String unifiedLogName(String writer) {
  if (!isCanonicalId(writer)) throw FormatFailure('Invalid app writer.');
  return '$writer.applog';
}

/// Syncthing receives an incoming file as `.syncthing.<name>.tmp`
/// (`~syncthing~<name>.tmp` on Windows) and renames it over `<name>` once
/// complete. Such a staging copy of a valid app history is not yet delivered
/// history; admission waits for the rename. Every other unexpected `.applog`
/// name remains a fail-closed conflict.
bool isSyncthingAppLogStagingName(String name) {
  const suffix = '.tmp';
  if (!name.endsWith(suffix)) return false;
  for (final prefix in const ['.syncthing.', '~syncthing~']) {
    if (!name.startsWith(prefix)) continue;
    final staged = name.substring(prefix.length, name.length - suffix.length);
    if (!staged.endsWith('.applog')) return false;
    final writer = staged.substring(0, staged.length - 7);
    return isCanonicalId(writer) && staged == '$writer.applog';
  }
  return false;
}
