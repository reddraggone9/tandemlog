import 'package:integration_test/integration_test.dart';

import '../test/food_products_ui_test.dart' as products;
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodProductsWorkflowTests();
}

void registerFoodProductsWorkflowTests() =>
    products.registerFoodProductsUiTests(
      capture: (tester, name) => pixels.capture(tester, name),
    );
