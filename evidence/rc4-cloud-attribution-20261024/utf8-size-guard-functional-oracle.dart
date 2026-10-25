import 'dart:convert';
import 'dart:math';

// Scratch functional prototype only. Not imported by the application or gates.
bool candidate(String value, int maximumBytes) {
  if (value.length > maximumBytes) return true;
  if (value.length <= maximumBytes ~/ 3) return false;
  return utf8.encode(value).length > maximumBytes;
}

void main() {
  var checks = 0;
  final branches = <String, int>{};
  void check(String value, Iterable<int> limits) {
    final exactBytes = utf8.encode(value).length;
    for (final limit in limits.toSet()) {
      if (candidate(value, limit) != (exactBytes > limit)) {
        throw StateError('Byte-budget mismatch: ${value.length}/$exactBytes/$limit');
      }
      final branch = value.length > limit
          ? 'lower-bound rejection'
          : value.length <= limit ~/ 3
          ? 'upper-bound acceptance'
          : 'original exact fallback';
      branches[branch] = (branches[branch] ?? 0) + 1;
      checks++;
    }
  }

  final budgets = [256 * 1024, 1024 * 1024, 16 * 1024 * 1024];
  for (final value in ['', 'plain', '\u00e9', '\u20ac', '\u{1f642}',
    String.fromCharCode(0xd800), String.fromCharCode(0xdfff),
    String.fromCharCodes([0xd800, 0xdc00, 0xd800, 0xdc00, 0xdfff])]) {
    final n = utf8.encode(value).length;
    check(value, [-1, 0, 1, 2, 3, n - 1, n, n + 1, ...budgets]);
  }

  final random = Random(1320);
  for (var sample = 0; sample < 30000; sample++) {
    final value = String.fromCharCodes([
      for (var i = 0; i < sample % 65; i++)
        switch ((sample + i) % 7) {
          0 => random.nextInt(128),
          1 => 128 + random.nextInt(0x800 - 128),
          2 => 0xd800 + random.nextInt(0x800),
          _ => random.nextInt(0x110000),
        },
    ]);
    final bytes = utf8.encode(value).length;
    check(value, [0, 1, bytes - 1, bytes, bytes + 1, value.length,
      value.length * 3 - 1, value.length * 3, ...budgets]);
  }

  // Every Unicode scalar plus explicit malformed UTF16 was tested separately.
  final scalars = String.fromCharCodes([
    for (var scalar = 0; scalar <= 0x10ffff; scalar++)
      if (scalar < 0xd800 || scalar > 0xdfff) scalar,
  ]);
  final scalarBytes = utf8.encode(scalars).length;
  check(scalars, [scalarBytes - 1, scalarBytes, scalarBytes + 1, ...budgets]);

  // Large exact-byte and one-third code-unit boundaries; no timing is recorded.
  for (final budget in budgets) {
    for (final (unit, width) in [
      ('a', 1), ('\u00e9', 2), ('\u20ac', 3), ('\u{1f642}', 4),
      (String.fromCharCode(0xd800), 3),
    ]) {
      final counts = {budget ~/ width - 1, budget ~/ width, budget ~/ width + 1,
        budget ~/ 3 - 1, budget ~/ 3, budget ~/ 3 + 1};
      for (final count in counts) {
        if (count < 0) continue;
        final value = unit * count;
        final bytes = utf8.encode(value).length;
        check(value, [budget, bytes - 1, bytes, bytes + 1]);
      }
    }
  }
  print(jsonEncode({'functionalOraclePassed': true, 'comparisons': checks,
    'randomStrings': 30000, 'fullUnicodeScalarCorpus': true,
    'malformedUtf16AndExactBudgetBoundaries': true, 'branches': branches,
    'performanceMeasured': false, 'productIntegrated': false,
    'reference': 'Original Dart utf8.encode(value).length > maximumBytes'}));
}
