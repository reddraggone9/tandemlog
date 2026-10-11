import 'package:integration_test/integration_test.dart';
import 'text_workflow_test.dart' show registerTextWorkflowTests;
import 'food_bulk_details_host_undo_review_test.dart'
    show registerFoodBulkDetailsHostUndoReviewTests;
import 'toolbar_parity_workflow_test.dart' show registerToolbarParityTests;
import 'food_all_status_search_workflow_test.dart'
    show registerFoodAllStatusSearchTests;
import 'food_production_workflow_test.dart' show registerFoodProductionTests;
import 'civil_date_picker_workflow_test.dart'
    show registerCivilDatePickerWorkflowTests;
import 'date_time_rows_test.dart' show registerDateTimeRowTests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTextWorkflowTests();
  registerFoodBulkDetailsHostUndoReviewTests();
  registerToolbarParityTests();
  registerFoodAllStatusSearchTests();
  registerFoodProductionTests();
  registerCivilDatePickerWorkflowTests();
  registerDateTimeRowTests();
}
