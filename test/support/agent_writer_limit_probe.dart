// Synthetic admission probe; no filesystem, profile, or canonical writes.
import 'dart:convert';
import 'dart:io';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:tandemlog/storage/unified_record.dart';

const space = '11111111-1111-4111-8111-111111111111';
const epoch = '22222222-2222-4222-8222-222222222222';
String identity(int index) =>
    '${index.toRadixString(16).padLeft(8, '0')}-3333-4333-8333-444444444444';
void main() {
  final results = <String, Object?>{};
  for (final count in [256, 257]) {
    final owners = {
      for (var i = 1; i <= count; i++)
        identity(i): {
          'count': 0,
          'head': unifiedGenesis(space, epoch, identity(i)),
          'digest': bytesDigest([]),
        },
    };
    try {
      final manifest = UnifiedManifest(space, epoch, bytesDigest([]), owners, {
        identity(1): identity(1),
      });
      final encoded = manifest.encode();
      UnifiedManifest.decode(encoded);
      results['manifest$count'] = {
        'accepted': true,
        'bytes': utf8.encode(encoded).length,
      };
    } on FormatFailure catch (e) {
      results['manifest$count'] = {'accepted': false, 'error': e.message};
    }
    final observed = {
      for (var i = 1; i <= count; i++)
        identity(i): UnifiedFrontier(
          0,
          unifiedGenesis(space, epoch, identity(i)),
        ),
    };
    try {
      final action = UnifiedRecord(
        space: space,
        epoch: epoch,
        writer: identity(1),
        sequence: 1,
        clock: EventClock(BigInt.one),
        previousHash: unifiedGenesis(space, epoch, identity(1)),
        effect: UnifiedEffect.joined(),
        observed: observed,
      );
      final encoded = action.encode();
      UnifiedRecord.decode(encoded);
      results['action$count'] = {
        'accepted': true,
        'bytes': utf8.encode(encoded).length,
      };
    } on FormatFailure catch (e) {
      results['action$count'] = {'accepted': false, 'error': e.message};
    }
  }
  stdout.writeln(jsonEncode(results));
  if ((results['manifest256'] as Map)['accepted'] != true ||
      (results['action256'] as Map)['accepted'] != true ||
      (results['manifest257'] as Map)['accepted'] != false ||
      (results['action257'] as Map)['accepted'] != false) {
    throw StateError('Unexpected inherited writer-limit behavior');
  }
}
