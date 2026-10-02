/// Keep application/domain messages and partial progress intact without a
/// Dart framework prefix. Folder adapters already translate provider failures.
String failureMessage(Object failure) =>
    failure is StateError ? failure.message : failure.toString();
