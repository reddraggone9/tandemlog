import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import '../domain/event.dart';
import '../domain/time_zone_policy.dart';
import 'unified_record.dart';

String bytesDigest(List<int> bytes) => sha256.convert(bytes).toString();

void assertWorkspaceTaskTimeZonePolicy(
  LogEvent event,
  TimeZoneNamePolicy policy,
) {
  try {
    policy.assertTaskEventAllowed(event);
  } on FormatException catch (e) {
    throw FormatFailure(e.message.toString());
  }
}

/// Immutable normalized bootstrap. Source bytes and conversion proofs belong to
/// the offline conversion report, never to a second runtime storage backend.
class UnifiedManifest {
  UnifiedManifest(
    this.space,
    this.epoch,
    this.sourceDigest,
    Map<String, Map<String, dynamic>> owners,
    Map<String, String> referenceAuthors,
  ) : owners = Map.unmodifiable(
        owners.map((k, v) => MapEntry(k, Map<String, dynamic>.unmodifiable(v))),
      ),
      referenceAuthors = Map.unmodifiable(referenceAuthors) {
    if (!isCanonicalId(space) ||
        !isCanonicalId(epoch) ||
        !isEventHash(sourceDigest) ||
        owners.isEmpty ||
        owners.length > 256 ||
        owners.keys.any((id) => !isCanonicalId(id)) ||
        referenceAuthors.length > 512 ||
        referenceAuthors.entries.any(
          (e) => !isCanonicalId(e.key) || !owners.containsKey(e.value),
        )) {
      throw FormatFailure('Invalid normalized workspace manifest.');
    }
    for (final entry in owners.entries) {
      final p = entry.value;
      if (p.length != 3 ||
          p['count'] is! int ||
          p['count'] < 0 ||
          p['count'] > 9007199254740991 ||
          !isEventHash(p['head']) ||
          !isEventHash(p['digest']) ||
          p['count'] == 0 &&
              (p['head'] != unifiedGenesis(space, epoch, entry.key) ||
                  p['digest'] != bytesDigest(const []))) {
        throw FormatFailure('Invalid normalized bootstrap prefix.');
      }
    }
  }
  final String space, epoch, sourceDigest;
  final Map<String, Map<String, dynamic>> owners;
  final Map<String, String> referenceAuthors;
  TimeZoneNamePolicy get timeZonePolicy => TimeZoneNamePolicy.additional2026eV1;
  String get digest => bytesDigest(utf8.encode(encode()));
  String authorOfReference(String writer) =>
      referenceAuthors[writer] ??
      (throw FormatFailure('Unmapped historical reference namespace.'));
  Map<String, dynamic> toJson() => {
    'v': unifiedProtocol,
    'id': space,
    'epoch': epoch,
    'sourceDigest': sourceDigest,
    'owners': owners,
    'referenceAuthors': referenceAuthors,
  };
  String encode() => canonicalDataJson(toJson());
  factory UnifiedManifest.empty(String space, String writer) {
    final epoch = const Uuid().v4();
    return UnifiedManifest(
      space,
      epoch,
      bytesDigest(const []),
      {
        writer: {
          'count': 0,
          'head': unifiedGenesis(space, epoch, writer),
          'digest': bytesDigest(const []),
        },
      },
      {writer: writer},
    );
  }
  factory UnifiedManifest.decode(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j.length != 6 || j['v'] != unifiedProtocol) {
        throw FormatFailure(
          'Unsupported workspace. Use the coordinated offline conversion before opening it.',
        );
      }
      final m = UnifiedManifest(
        j['id'] as String,
        j['epoch'] as String,
        j['sourceDigest'] as String,
        (j['owners'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
        ),
        Map<String, String>.from(j['referenceAuthors'] as Map),
      );
      if (m.encode() != raw) {
        throw FormatFailure('Noncanonical workspace manifest.');
      }
      return m;
    } on FormatFailure {
      rethrow;
    } catch (e) {
      throw FormatFailure('Invalid normalized manifest: $e');
    }
  }
}
