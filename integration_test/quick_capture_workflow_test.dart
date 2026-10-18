import 'package:integration_test/integration_test.dart';
import 'header_search_test.dart' show registerHeaderSearchTests;
import 'task_input_mode_workflow_test.dart' show registerTaskInputModeTests;
import 'task_input_mode_retry_test.dart' show registerTaskInputModeRetryTests;

/// Focused native acceptance of capture geometry, keyboard/IME and exact Retry.
/// These workflows also remain registered in the full task-flow aggregate.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerHeaderSearchTests();
  registerTaskInputModeTests();
  registerTaskInputModeRetryTests();
}
