import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/food_selection_retention_test.dart'
    show verifyFoodWideSelectionRetention;
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native wide Food filter preserves captured selection until editor closes',
    (tester) => verifyFoodWideSelectionRetention(
      tester,
      capture: (name) => pixels.capture(tester, name),
    ),
  );
}
