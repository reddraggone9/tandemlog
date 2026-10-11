import 'package:integration_test/integration_test.dart';

import '../test/food_bulk_details_undo_review_test.dart' as review;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodBulkDetailsHostUndoReviewTests();
}

void registerFoodBulkDetailsHostUndoReviewTests() =>
    review.registerFoodBulkDetailsUndoReviewTests(
      components: false,
      actualHost: true,
    );
