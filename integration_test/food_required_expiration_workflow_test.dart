import 'package:integration_test/integration_test.dart';
import '../test/food_required_expiration_test.dart' as scenarios;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodRequiredExpirationTests();
}

void registerFoodRequiredExpirationTests() =>
    scenarios.registerFoodRequiredExpirationTests();
