import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/event.dart';
import '../food/food_record.dart';

const unifiedProtocol = 4;
const maximumUnifiedFileBytes = 32 * 1024 * 1024;
const maximumUnifiedWorkspaceBytes = 256 * 1024 * 1024;
const maximumUnifiedRecordBytes = 4 * 1024 * 1024;

String unifiedGenesis(String space, String epoch, String writer) => sha256
    .convert(utf8.encode('tandemlog:app-genesis:v4\n$space\n$epoch\n$writer'))
    .toString();

/// An immutable semantic event. Historical bytes are evidence, never a second
/// active writer or allocator. Physical positions and semantic IDs are distinct.
class UnifiedEffect {
  UnifiedEffect(this.kind, this.raw) {
    if (!{
      'legacy.task',
      'legacy.food',
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
      if (_food!.unified == historical) {
        throw FormatFailure(
          'Food event format differs from its app history epoch.',
        );
      }
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
  bool get historical => kind.startsWith('legacy.');
  String get space => task?.space ?? food!.space;
  String get writer => task?.writer ?? food!.writer;
  int get sequence => task?.sequence ?? food!.sequence;
  EventClock get clock => task?.clock ?? food!.clock;
  String get id => task?.id ?? food!.id;
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
    required this.effect,
    required this.transactionStart,
    required this.transactionCount,
    required this.transactionIndex,
    Map<String, UnifiedFrontier> observed = const {},
  }) : observed = Map.unmodifiable(observed) {
    if (observed.length > 256 ||
        observed.entries.any(
          (e) =>
              !isCanonicalId(e.key) ||
              e.value.sequence < 0 ||
              e.value.sequence > 9007199254740991 ||
              !isEventHash(e.value.hash),
        ) ||
        (effect.historical && observed.isNotEmpty) ||
        (!effect.historical &&
            (observed[writer]?.sequence != transactionStart - 1 ||
                transactionIndex == 0 &&
                    observed[writer]?.hash != previousHash))) {
      throw FormatFailure('Invalid app command observed history.');
    }
    if (![space, epoch, writer].every(isCanonicalId) ||
        sequence < 1 ||
        sequence > 9007199254740991 ||
        !isEventHash(previousHash) ||
        clock.value.isNegative ||
        clock.value > EventClock.maximum ||
        transactionStart < 1 ||
        transactionCount < 1 ||
        transactionCount > 10000 ||
        transactionIndex < 0 ||
        transactionIndex >= transactionCount ||
        transactionStart + transactionIndex != sequence ||
        (effect.isData && effect.space != space)) {
      throw FormatFailure('Invalid unified identity, clock or transaction.');
    }
    if (effect.isData &&
        !effect.historical &&
        (effect.writer != writer ||
            effect.sequence != sequence ||
            effect.clock != clock ||
            effect.previousHash != previousHash)) {
      throw FormatFailure(
        'App event differs from its common writer reservation.',
      );
    }
    hash = sha256
        .convert(
          utf8.encode('tandemlog:app-record:v4\n${canonicalDataJson(_body())}'),
        )
        .toString();
    if (utf8.encode(encode()).length > maximumUnifiedRecordBytes) {
      throw FormatFailure('Unified event exceeds safe read limits.');
    }
  }
  final String space, epoch, writer, previousHash;
  final int sequence, transactionStart, transactionCount, transactionIndex;
  final EventClock clock;
  final UnifiedEffect effect;
  final Map<String, UnifiedFrontier> observed;
  late final String hash;
  String get recordId => 'app:$epoch:$writer:$sequence';
  bool get completesTransaction => transactionIndex + 1 == transactionCount;

  Map<String, dynamic> _body() => {
    'v': unifiedProtocol,
    'space': space,
    'epoch': epoch,
    'writer': writer,
    'seq': sequence,
    'clock': clock.toJson(),
    'previousHash': previousHash,
    'transaction': {
      'start': transactionStart,
      'count': transactionCount,
      'index': transactionIndex,
    },
    'observed': observed.map((k, v) => MapEntry(k, v.toJson())),
    'effect': effect.toJson(),
  };
  String encode() => canonicalDataJson({..._body(), 'hash': hash});

  factory UnifiedRecord.decode(String raw) {
    try {
      if (utf8.encode(raw).length > maximumUnifiedRecordBytes) {
        throw FormatFailure('Unified record exceeds safe read limits.');
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
        'transaction',
        'effect',
        'observed',
        'hash',
      });
      final t = j['transaction'] as Map<String, dynamic>,
          e = j['effect'] as Map<String, dynamic>;
      _keys(t, {'start', 'count', 'index'});
      _keys(e, {'kind', 'raw'});
      final record = UnifiedRecord(
        space: j['space'] as String,
        epoch: j['epoch'] as String,
        writer: j['writer'] as String,
        sequence: j['seq'] as int,
        clock: EventClock.fromJson(j['clock']),
        previousHash: j['previousHash'] as String,
        effect: UnifiedEffect(e['kind'] as String, e['raw'] as String),
        transactionStart: t['start'] as int,
        transactionCount: t['count'] as int,
        transactionIndex: t['index'] as int,
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
        throw FormatFailure('Unified record hash or canonical bytes differ.');
      }
      return record;
    } on FormatFailure {
      rethrow;
    } catch (e) {
      throw FormatFailure('Invalid unified event: $e');
    }
  }

  static void _keys(Map<String, dynamic> value, Set<String> keys) {
    if (value.length != keys.length ||
        value.keys.any((key) => !keys.contains(key))) {
      throw FormatFailure(
        'Unknown app fields. Update the app; history was preserved.',
      );
    }
  }
}

String unifiedLogName(String writer) {
  if (!isCanonicalId(writer)) throw FormatFailure('Invalid app writer.');
  return '$writer.applog';
}
