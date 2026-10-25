import 'dart:convert';

/// Same predicate as `utf8.encode(value).length > maximumBytes`.
/// A UTF16 code unit needs at most three UTF8 bytes, including replacement of
/// unpaired surrogates. Small inputs therefore need no temporary byte buffer.
/// Keep the original exact conversion elsewhere; scalar validation is separate.
bool exceedsUtf8ByteLimit(String value, int maximumBytes) {
  if (maximumBytes >= 0 && value.length <= maximumBytes ~/ 3) return false;
  return utf8.encode(value).length > maximumBytes;
}
