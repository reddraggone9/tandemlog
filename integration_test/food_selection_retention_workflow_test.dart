import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/food_selection_retention_test.dart'
    show verifyFoodWideSelectionRetention;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native wide Food filter preserves captured selection until editor closes',
    verifyFoodWideSelectionRetention,
  );
}
