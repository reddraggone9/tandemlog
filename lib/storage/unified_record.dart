import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/event.dart';
import '../food/food_record.dart';

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
  final String kind, raw;
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
  String get key => '${task == null ? 'food:' : 'task:'}$space:$id';
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
          provenance['kind'] != 'food.import' ||
          !isCanonicalId(provenance['namespace']) ||
          !isEventHash(provenance['planHash']) ||
          !isEventHash(provenance['sourceSha256']) ||
          this.effects.any((e) => e.food?.operation.action.name != 'add')) {
        throw FormatFailure('Invalid canonical import provenance.');
      }
    }
    hash = sha256
        .convert(
          utf8.encode('tandemlog:app-action:v5\n${canonicalDataJson(_body())}'),
        )
        .toString();
    if (utf8.encode(encode()).length > maximumUnifiedRecordBytes) {
      throw FormatFailure(
        'Action exceeds safe record size; nothing was written.',
      );
    }
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
  String encode() => canonicalDataJson({..._body(), 'hash': hash});
  factory UnifiedRecord.decode(String raw) {
    try {
      if (utf8.encode(raw).length > maximumUnifiedRecordBytes) {
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

String unifiedLogName(String writer) {
  if (!isCanonicalId(writer)) throw FormatFailure('Invalid app writer.');
  return '$writer.applog';
}
