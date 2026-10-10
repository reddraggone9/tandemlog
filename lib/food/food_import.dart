import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../domain/event.dart' show isCanonicalId;
import '../domain/event_chain.dart' show canonicalDataJson;
import 'inventory.dart';

/// Reviewed staging only: source extraction and its provenance remain private.
final class FoodImportContainer {
  FoodImportContainer({
    required this.sourceId,
    required this.ordinal,
    required FoodDetails details,
    required Contents contents,
    required this.createdAt,
  }) : details = FoodDetails.fromJson(details.toJson()),
       contents = Contents.fromJson(contents.toJson());
  final String sourceId, createdAt;
  final int ordinal;
  final FoodDetails details;
  final Contents contents;
  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'ordinal': ordinal,
    'details': details.toJson(),
    'contents': contents.toJson(),
    'createdAt': createdAt,
  };
  factory FoodImportContainer.fromJson(Map<String, dynamic> j) {
    _keys(j, {'sourceId', 'ordinal', 'details', 'contents', 'createdAt'});
    if (j['sourceId'] is! String ||
        j['ordinal'] is! int ||
        j['createdAt'] is! String ||
        j['details'] is! Map<String, dynamic> ||
        j['contents'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid import container.');
    }
    final value = FoodImportContainer(
      sourceId: j['sourceId'],
      ordinal: j['ordinal'],
      details: FoodDetails.fromJson(j['details']),
      contents: Contents.fromJson(j['contents']),
      createdAt: j['createdAt'],
    );
    value.validate();
    return value;
  }
  void validate() {
    if (sourceId.isEmpty ||
        utf8.encode(sourceId).length > 512 ||
        ordinal < 1 ||
        ordinal > 100000 ||
        createdAt.length > 40 ||
        !RegExp(
          r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?(?:Z|[+-]\d\d:\d\d)$',
        ).hasMatch(createdAt)) {
      throw const FormatException('Invalid import identity or timestamp.');
    }
    // DateTime.parse normalizes overflow. Reject invalid calendar/time input.
    final parsed = DateTime.tryParse(createdAt);
    final calendar = DateTime.tryParse(createdAt.substring(0, 19));
    if (parsed == null ||
        calendar == null ||
        calendar.toIso8601String().substring(0, 19) !=
            createdAt.substring(0, 19) ||
        (createdAt.endsWith('Z') == false &&
            (int.parse(
                      createdAt.substring(
                        createdAt.length - 5,
                        createdAt.length - 3,
                      ),
                    ) >
                    23 ||
                int.parse(createdAt.substring(createdAt.length - 2)) > 59))) {
      throw const FormatException('Invalid import timestamp.');
    }
    details.validate();
    contents.validate();
  }

  String targetId(String importId) => const Uuid().v5(
    importId,
    'tandemlog:food-import:v1:${canonicalDataJson([sourceId, ordinal])}',
  );
}

final class FoodImportPlan {
  FoodImportPlan({
    required this.space,
    required this.importId,
    required this.sourceSha256,
    required List<FoodImportContainer> containers,
  }) : containers = List.unmodifiable(containers) {
    validate();
  }
  final String space, importId, sourceSha256;
  final List<FoodImportContainer> containers;
  static const maximumContainers = 1000, maximumBytes = 4 * 1024 * 1024;
  Map<String, dynamic> toJson() => {
    'v': 1,
    'space': space,
    'importId': importId,
    'sourceSha256': sourceSha256,
    'containers': containers.map((v) => v.toJson()).toList(),
  };
  String get canonicalJson => canonicalDataJson(toJson());
  String get planHash => sha256
      .convert(utf8.encode('tandemlog:food-import-plan:v1\n$canonicalJson'))
      .toString();
  List<String> get targetIds =>
      List.unmodifiable(containers.map((c) => c.targetId(importId)));
  factory FoodImportPlan.decode(String encoded) {
    if (utf8.encode(encoded).length > maximumBytes) {
      throw const FormatException('Import plan exceeds staging limit.');
    }
    final j = jsonDecode(encoded);
    if (j is! Map<String, dynamic>) {
      throw const FormatException('Invalid import plan.');
    }
    _keys(j, {'v', 'space', 'importId', 'sourceSha256', 'containers'});
    if (j['v'] is! int ||
        j['v'] != 1 ||
        j['space'] is! String ||
        j['importId'] is! String ||
        j['sourceSha256'] is! String ||
        j['containers'] is! List ||
        (j['containers'] as List).length > maximumContainers) {
      throw const FormatException('Invalid import plan.');
    }
    return FoodImportPlan(
      space: j['space'],
      importId: j['importId'],
      sourceSha256: j['sourceSha256'],
      containers: (j['containers'] as List).map((c) {
        if (c is! Map<String, dynamic>) {
          throw const FormatException('Invalid import container.');
        }
        return FoodImportContainer.fromJson(c);
      }).toList(),
    );
  }
  void validate() {
    if (!isCanonicalId(space) ||
        !isCanonicalId(importId) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceSha256) ||
        containers.isEmpty ||
        containers.length > maximumContainers) {
      throw const FormatException('Invalid import plan identity or count.');
    }
    final ids = <String>{};
    for (final c in containers) {
      c.validate();
      if (!ids.add(c.targetId(importId))) {
        throw const FormatException('Duplicate physical import identity.');
      }
    }
    if (utf8.encode(canonicalJson).length > maximumBytes) {
      throw const FormatException('Import plan exceeds staging limit.');
    }
  }
}

enum FoodImportStatus { ready, pendingRecovery, committed }

class FoodImportReport {
  FoodImportReport(
    this.status,
    this.planHash,
    this.writer,
    List<String> targets,
    List<String> recordIds,
  ) : targetIds = List.unmodifiable(targets),
      recordIds = List.unmodifiable(recordIds);
  final FoodImportStatus status;
  final String planHash, writer;
  final List<String> targetIds, recordIds;
}

void _keys(Map<String, dynamic> j, Set<String> expected) {
  if (j.length != expected.length || !expected.every(j.containsKey)) {
    throw const FormatException('Unexpected import fields.');
  }
}
