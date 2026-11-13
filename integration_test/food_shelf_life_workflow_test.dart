import 'package:integration_test/integration_test.dart';

import '../test/food_shelf_life_ui_test.dart' as shelf_life;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodShelfLifeWorkflowTests();
}

void registerFoodShelfLifeWorkflowTests() =>
    shelf_life.registerFoodShelfLifeUiTests();
