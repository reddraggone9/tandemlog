import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/validated_action_cache.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/unified_record.dart';

void main() {
  String payload(String binding) => jsonEncode({
    'generation': ValidatedActionCache.layout,
    'binding': binding,
    'records': [],
  });
  String digest(String value) => sha256.convert(utf8.encode(value)).toString();
  test('worker seal keeps exact existing UTF-8 payload and checksum', () async {
    const space = '11111111-1111-4111-8111-111111111111';
    const epoch = '22222222-2222-4222-8222-222222222222';
    const writer = '33333333-3333-4333-8333-333333333333';
    final genesis = unifiedGenesis(space, epoch, writer);
    final records = [
      UnifiedRecord(
        space: space,
        epoch: epoch,
        writer: writer,
        sequence: 1,
        clock: EventClock(BigInt.one),
        previousHash: genesis,
        effect: UnifiedEffect.named('Café 🌾'),
        observed: {writer: UnifiedFrontier(0, genesis)},
      ),
    ];
    final result = (await UnifiedDecodedCache.prepareOffThread(
      records,
      'scope',
    ))!;
    expect(result.payload, UnifiedDecodedCache.encodeUtf8(records, 'scope'));
    expect(result.digest, sha256.convert(result.payload).toString());
    final restored = UnifiedDecodedCache.restore(
      utf8.decode(result.payload),
      result.digest,
      'scope',
    );
    expect(restored.single.encode(), records.single.encode());
  });

  test(
    'only exact in-flight payload, digest and binding share a receipt',
    () async {
      final raw = payload('scope');
      final first = ValidatedActionCache.verifyOffThread(
        raw,
        digest(raw),
        'scope',
      );
      final same = ValidatedActionCache.verifyOffThread(
        raw,
        digest(raw),
        'scope',
      );
      expect(identical(first, same), true);
      final wrongDigest = ValidatedActionCache.verifyOffThread(
        raw,
        'wrong',
        'scope',
      );
      final wrongScope = ValidatedActionCache.verifyOffThread(
        raw,
        digest(raw),
        'other',
      );
      final changed = '$raw ';
      final wrongPayload = ValidatedActionCache.verifyOffThread(
        changed,
        digest(raw),
        'scope',
      );
      await Future.wait([
        expectLater(first, completes),
        expectLater(wrongDigest, throwsFormatException),
        expectLater(wrongScope, throwsFormatException),
        expectLater(wrongPayload, throwsFormatException),
      ]);
      // Completed/failed flights are not retained as process-local authority.
      final again = ValidatedActionCache.verifyOffThread(
        raw,
        digest(raw),
        'scope',
      );
      expect(identical(first, again), false);
      expect((await again).records, isEmpty);
    },
  );
}
