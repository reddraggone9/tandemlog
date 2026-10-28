import 'package:integration_test/integration_test.dart';
import '../test/selection_layout_parity_test.dart' as parity;
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerSelectionLayoutParityWorkflowTests();
}

void registerSelectionLayoutParityWorkflowTests() {
  parity.registerSelectionLayoutParityTests(capture: pixels.capture);
}
