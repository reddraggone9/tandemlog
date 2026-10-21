import '../domain/event.dart';

/// Current-session uncertain append, not persisted restart-recovery authority.
class WriterGuardFailure extends FormatFailure {
  WriterGuardFailure(super.message);
  WriterGuardFailure.unresolvedAppend()
    : super(
        'An earlier Save in this session has an uncertain result. Retry it before saving again.',
      );
}
