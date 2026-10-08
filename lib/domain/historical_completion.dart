import 'event.dart';

/// This completion retains an existing scalar-initialized child. It supplies
/// no successor creation/text contribution. Missing source is a transport
/// dependency; a known wrong source is invalid, never a replacement seed.
bool verifyHistoricalCompletion(LogEvent completion, LogEvent? source) {
  if (completion.type != 'task.completedKeepingSuccessor') {
    throw ArgumentError('Historical completion record required.');
  }
  if (source == null) return false;
  final retained = completion.data['retainedSuccessor'] as Map;
  if (source.id != retained['completion'] ||
      source.hash != retained['hash'] ||
      source.space != completion.space ||
      source.entity != completion.entity ||
      !isScalarSuccessorInitialization(source) ||
      source.clock >= completion.clock ||
      (source.data['successor'] as Map?)?['id'] != retained['id']) {
    throw FormatFailure(
      'Invalid retained historical initialization in ${completion.id}.',
    );
  }
  return true;
}
