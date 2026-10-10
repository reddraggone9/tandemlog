import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../domain/event.dart';
import 'inventory.dart';

const foodRecordHashDomain = 'tandemlog:food-record:v1\n';
const foodWriterName = 'tandemlog:food:v1';
const maximumFoodRecordBytes = 256 * 1024;

String foodWriter(String installationWriter) {
  if (!isCanonicalId(installationWriter)) {
    throw const FormatException('Invalid installation writer.');
  }
  return const Uuid().v5(installationWriter, foodWriterName);
}

String foodLogName(String writer) {
  if (!isCanonicalId(writer)) {
    throw const FormatException('Invalid food writer.');
  }
  return 'food-$writer.foodlog';
}

/// Food has its own module/version/hash domain, outside task v3 discovery.
/// Identity and order are constructed from the envelope, never payload hints.
class FoodRecord {
  FoodRecord({
    required this.space,
    required this.writer,
    required this.sequence,
    required this.clock,
    required this.operation,
    required this.previousHash,
    Map<String, String> createdWith = const {},
  }) : createdWith = Map.unmodifiable(createdWith) {
    if (!isCanonicalId(space) ||
        !isCanonicalId(writer) ||
        sequence < 1 ||
        sequence > 9007199254740991 ||
        clock.value.isNegative ||
        clock.value > EventClock.maximum ||
        !isEventHash(previousHash) ||
        (sequence == 1 && previousHash != eventGenesisHash(space, writer)) ||
        operation.id != '$writer:$sequence' ||
        operation.order != clock.value.toInt()) {
      throw const FormatException(
        'Invalid food record identity, clock or chain.',
      );
    }
    operation.validate();
    if (operation.action == FoodAction.add) {
      if (this.createdWith.isNotEmpty) {
        throw const FormatException(
          'Creation cannot inherit a container basis.',
        );
      }
    } else if (this.createdWith.length != operation.targets.length ||
        this.createdWith.keys.any((id) => !operation.targets.contains(id))) {
      throw const FormatException(
        'Each target needs its observed creation basis.',
      );
    }
    for (final ref in this.createdWith.values) {
      validateFoodReference(ref);
      final parts = ref.split(':');
      if (parts.first == writer && int.parse(parts.last) >= sequence) {
        throw const FormatException('Food creation basis is not causal.');
      }
    }
    hash = sha256
        .convert(
          utf8.encode('$foodRecordHashDomain${canonicalDataJson(_body())}'),
        )
        .toString();
    if (utf8.encode(encode()).length > maximumFoodRecordBytes) {
      throw const FormatException('Food record is too large.');
    }
  }
  final String space, writer, previousHash;
  final int sequence;
  final EventClock clock;
  final FoodOperation operation;
  final Map<String, String> createdWith;
  late final String hash;
  String get id => '$writer:$sequence';

  Map<String, dynamic> _body() {
    final payload = operation.toJson()
      ..remove('id')
      ..remove('order');
    return {
      'v': 1,
      'module': 'food',
      'space': space,
      'writer': writer,
      'seq': sequence,
      'clock': clock.toJson(),
      'operation': payload,
      'createdWith': createdWith,
      'previousHash': previousHash,
    };
  }

  String encode() => canonicalDataJson({..._body(), 'hash': hash});

  factory FoodRecord.decode(String raw) {
    try {
      if (raw.length > maximumFoodRecordBytes ||
          utf8.encode(raw).length > maximumFoodRecordBytes) {
        throw const FormatException('Food record is too large.');
      }
      final j = jsonDecode(raw) as Map<String, dynamic>;
      const keys = {
        'v',
        'module',
        'space',
        'writer',
        'seq',
        'clock',
        'operation',
        'createdWith',
        'previousHash',
        'hash',
      };
      if (j.length != keys.length ||
          !j.keys.every(keys.contains) ||
          j['v'] != 1 ||
          j['module'] != 'food' ||
          j['clock'] is! String ||
          (j['clock'] as String).length > 19) {
        throw const FormatException('Unsupported or malformed food record.');
      }
      final clock = EventClock.fromJson(j['clock']);
      final payload = j['operation'] as Map<String, dynamic>;
      if (payload.containsKey('id') || payload.containsKey('order')) {
        throw const FormatException('Food payload cannot override identity.');
      }
      final record = FoodRecord(
        space: j['space'] as String,
        writer: j['writer'] as String,
        sequence: j['seq'] as int,
        clock: clock,
        previousHash: j['previousHash'] as String,
        createdWith: (j['createdWith'] as Map<String, dynamic>)
            .cast<String, String>(),
        operation: FoodOperation.fromJson({
          ...payload,
          'id': '${j['writer']}:${j['seq']}',
          'order': clock.toJson(),
        }),
      );
      if (j['hash'] != record.hash || raw != record.encode()) {
        throw const FormatException(
          'Food record hash or canonical bytes differ.',
        );
      }
      return record;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid food record.');
    }
  }
}

void validateFoodReference(String ref) {
  final parts = ref.split(':');
  if (parts.length != 2 ||
      !isCanonicalId(parts.first) ||
      !RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(parts.last) ||
      int.parse(parts.last) > 9007199254740991) {
    throw const FormatException('Invalid food operation reference.');
  }
}
