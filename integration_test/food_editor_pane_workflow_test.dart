import 'package:integration_test/integration_test.dart';

import '../test/food_editor_pane_test.dart' show registerFoodEditorPaneTests;

void registerFoodEditorPaneWorkflowTests() => registerFoodEditorPaneTests();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodEditorPaneWorkflowTests();
}
