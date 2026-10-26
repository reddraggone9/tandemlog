import 'dart:convert';
import '../domain/current_operation.dart';
import '../domain/validated_action_cache.dart';
import '../domain/utf8_byte_limit.dart';

import 'package:uuid/uuid.dart';
import '../domain/event.dart';
import 'inventory.dart';

const foodRecordHashDomain = 'tandemlog:food-record:v1\n';
const foodUndoRecordHashDomain = 'tandemlog:food-record:v2\n';
const unifiedFoodRecordHashDomain = 'tandemlog:food-record:v3\n';
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
    this.unified = true,
    this.attributedWriter,
    this.retainedReferenceHash,
    Map<String, String> createdWith = const {},
  }) : createdWith = Map.unmodifiable(createdWith),
       _cachedIntegrityHash = null,
       _cachedRaw = null {
    if (!isCanonicalId(space) ||
        !isCanonicalId(writer) ||
        sequence < 1 ||
        sequence > 9007199254740991 ||
        clock.value.isNegative ||
        clock.value > EventClock.maximum ||
        !isEventHash(previousHash) ||
        (!unified &&
            sequence == 1 &&
            previousHash != eventGenesisHash(space, writer)) ||
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
    hash = retainedReferenceHash ?? currentOperation.contentHash;
    if (!isEventHash(hash) || !isCanonicalId(author)) {
      throw const FormatException(
        'Invalid Food operation reference or author.',
      );
    }
    if (exceedsUtf8ByteLimit(encode(), maximumFoodRecordBytes)) {
      throw const FormatException('Food record is too large.');
    }
  }
  FoodRecord._cached({
    required this.space,
    required this.writer,
    required this.sequence,
    required this.clock,
    required this.operation,
    required this.previousHash,
    required this.unified,
    required this.attributedWriter,
    required this.retainedReferenceHash,
    required Map<String, String> createdWith,
    required String referenceHash,
    required String integrity,
    required String raw,
  }) : createdWith = Map.unmodifiable(createdWith),
       _cachedIntegrityHash = integrity,
       _cachedRaw = raw {
    hash = referenceHash;
  }

  /// A per-effect receipt is minted only by the immutable whole-batch verifier;
  /// arbitrary DTOs or caller-supplied successful callbacks are not accepted.
  factory FoodRecord.fromDecodedCache(ValidatedActionEffect receipt) {
    final fields = receipt.fields;
    if (receipt.layout != 3 ||
        !const {'food', 'history.food'}.contains(receipt.kind) ||
        fields == null ||
        fields.length != 12) {
      throw const FormatException('Unsupported cached Food layout.');
    }
    final unified = fields[6] as bool;
    final result = FoodRecord._cached(
      space: fields[0] as String,
      writer: fields[1] as String,
      sequence: fields[2] as int,
      clock: EventClock.fromJson(fields[3]),
      operation: FoodOperation.fromJson(
        fields[4] as Map<String, dynamic>,
        unified: unified,
      ),
      previousHash: fields[5] as String,
      unified: unified,
      attributedWriter: fields[7] as String?,
      retainedReferenceHash: fields[8] as String?,
      createdWith: Map<String, String>.from(fields[9] as Map),
      referenceHash: fields[10] as String,
      integrity: fields[11] as String,
      raw: receipt.raw,
    );
    if (result.operation.id != result.id ||
        result.operation.order != result.clock.value.toInt() ||
        !isEventHash(result.hash) ||
        !isEventHash(result.integrityHash)) {
      throw const FormatException('Invalid cached Food identity.');
    }
    return result;
  }

  final String? _cachedIntegrityHash, _cachedRaw;
  final bool unified;
  final String? attributedWriter, retainedReferenceHash;
  String get author => attributedWriter ?? writer;
  String get integrityHash =>
      _cachedIntegrityHash ?? currentOperation.contentHash;
  final String space, writer, previousHash;
  final int sequence;
  final EventClock clock;
  final FoodOperation operation;
  final Map<String, String> createdWith;
  late final String hash;
  late final String _id = '$writer:$sequence';
  String get id => _id;
  int get version => currentOperationFormat;
  late final CurrentOperation currentOperation = _buildCurrentOperation();

  CurrentOperation _buildCurrentOperation() {
    final values = operation.toJson()
      ..remove('id')
      ..remove('order')
      ..remove('action');
    return CurrentOperation(
      module: 'food',
      space: space,
      author: author,
      writer: writer,
      sequence: sequence,
      clock: clock.toJson(),
      subject: space,
      family: 'container.${operation.action.name}',
      revision: 1,
      value: {'values': values, 'creationBasis': createdWith},
      predecessor: previousHash,
      referenceHash: retainedReferenceHash,
    );
  }

  Map<String, dynamic> toJson() => _cachedRaw == null
      ? currentOperation.toJson()
      : jsonDecode(_cachedRaw) as Map<String, dynamic>;
  String encode() => _cachedRaw ?? currentOperation.encode();

  factory FoodRecord.decode(String raw) {
    try {
      final current = CurrentOperation.decode(raw, module: 'food');
      final actions = FoodAction.values
          .where((action) => current.family == 'container.${action.name}')
          .toList();
      if (actions.length != 1 ||
          current.revision != 1 ||
          current.subject != current.space ||
          current.value.length != 2 ||
          !current.value.containsKey('values') ||
          !current.value.containsKey('creationBasis')) {
        throw const FormatException(
          'Unknown Food operation. Update the app; history was preserved.',
        );
      }
      final values = Map<String, dynamic>.from(current.value['values'] as Map);
      if (values.keys.any((key) => {'action', 'id', 'order'}.contains(key))) {
        throw const FormatException(
          'Food payload cannot override its identity.',
        );
      }
      return FoodRecord(
        unified: true,
        space: current.space,
        writer: current.writer,
        sequence: current.sequence,
        clock: EventClock.fromJson(current.clock),
        previousHash: current.predecessor,
        attributedWriter: current.author,
        retainedReferenceHash: current.referenceHash,
        createdWith: Map<String, String>.from(
          current.value['creationBasis'] as Map,
        ),
        operation: FoodOperation.fromJson({
          ...values,
          'action': actions.single.name,
          'id': '${current.writer}:${current.sequence}',
          'order': current.clock,
        }, unified: true),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Malformed current Food operation.');
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
