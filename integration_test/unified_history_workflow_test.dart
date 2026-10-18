import 'dart:io';
import 'package:integration_test/integration_test.dart';
import '../test/unified_host_test.dart' as host;

/// Reuse the full host workflows with the real Linux runner, native text engine,
/// SQLite and real files. Android provider/lifecycle acceptance is separate.
void registerUnifiedHistoryWorkflowTests() {
  if (Platform.isLinux) host.main();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerUnifiedHistoryWorkflowTests();
}
