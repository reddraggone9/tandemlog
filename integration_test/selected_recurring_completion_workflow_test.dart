import 'package:integration_test/integration_test.dart';

import '../test/selected_recurring_completion_host_test.dart' as selection;
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  selection.registerSelectedRecurringCompletionTests(capture: pixels.capture);
}
