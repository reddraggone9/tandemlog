import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/utf8_byte_limit.dart';

void check(String value, Iterable<int> limits) {
  final bytes = utf8.encode(value).length;
  for (final limit in limits.toSet()) {
    expect(
      exceedsUtf8ByteLimit(value, limit),
      bytes > limit,
      reason: '${value.length} code units/$bytes bytes/$limit limit',
    );
  }
}

void main() {
  test(
    'UTF8 budget matches original encoder for every scalar and malformed UTF16',
    () {
      final scalars = String.fromCharCodes([
        for (var c = 0; c <= 0x10ffff; c++)
          if (c < 0xd800 || c > 0xdfff) c,
      ]);
      final bytes = utf8.encode(scalars).length;
      check(scalars, [bytes - 1, bytes, bytes + 1]);
      for (final value in [
        '',
        'plain',
        '\u00e9',
        '\u20ac',
        '\u{1f642}',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdfff),
        String.fromCharCodes([0xd800, 0xdc00, 0xd800, 0xdc00, 0xdfff]),
      ]) {
        check(value, [-1, 0, 1, 2, 3, 4, utf8.encode(value).length]);
      }
    },
  );

  test(
    'randomized budget classifications match the independent byte count',
    () {
      final random = Random(1320);
      for (var sample = 0; sample < 3000; sample++) {
        final value = String.fromCharCodes([
          for (var i = 0; i < sample % 65; i++)
            i % 5 == 0
                ? 0xd800 + random.nextInt(0x800)
                : random.nextInt(0x110000),
        ]);
        final n = utf8.encode(value).length;
        check(value, [
          0,
          1,
          n - 1,
          n,
          n + 1,
          value.length * 3 - 1,
          value.length * 3,
        ]);
      }
    },
  );

  test(
    'exact format limits retain ASCII multibyte and one-third boundaries',
    () {
      for (final budget in [256 * 1024, 1024 * 1024, 16 * 1024 * 1024]) {
        for (final (unit, width) in [
          ('a', 1),
          ('\u00e9', 2),
          ('\u20ac', 3),
          ('\u{1f642}', 4),
          (String.fromCharCode(0xd800), 3),
        ]) {
          for (final count in {
            budget ~/ width - 1,
            budget ~/ width,
            budget ~/ width + 1,
            budget ~/ 3 - 1,
            budget ~/ 3,
            budget ~/ 3 + 1,
          }) {
            check(unit * count, [budget]);
          }
        }
      }
    },
  );
}
