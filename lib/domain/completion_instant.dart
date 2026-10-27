/// Required revision-3 completion time: one UTC instant, at device-clock
/// microsecond precision. This is not a causal clock or a scheduling date.
String encodeCompletionInstant(DateTime value) {
  final utc = value.toUtc();
  if (utc.year < 1 || utc.year > 9999) {
    throw const FormatException(
      'Completion instant is outside supported years.',
    );
  }
  final iso = utc.toIso8601String();
  return '${iso.substring(0, 23)}${utc.microsecond.toString().padLeft(3, '0')}Z';
}

DateTime decodeCompletionInstant(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$',
      ).hasMatch(value)) {
    throw const FormatException('Completion requires a canonical UTC instant.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || encodeCompletionInstant(parsed) != value) {
    throw const FormatException('Invalid completion instant.');
  }
  return parsed;
}
