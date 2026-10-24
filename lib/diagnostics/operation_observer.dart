/// Optional synchronous interval observation. Implementations must not perform
/// application work or alter state. Owners catch observer failures so results,
/// original errors and operation ordering are preserved.
abstract interface class OperationDiagnosticObserver {
  Object? start(String operation);
  void finish(Object token, bool succeeded);
}
