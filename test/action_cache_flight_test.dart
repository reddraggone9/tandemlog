import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/validated_action_cache.dart';

void main() {
  String payload(String binding) => jsonEncode({
    'generation': ValidatedActionCache.layout,
    'binding': binding,
    'records': [],
  });
  String digest(String value) => sha256.convert(utf8.encode(value)).toString();
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
