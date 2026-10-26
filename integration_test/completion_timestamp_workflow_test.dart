import 'package:integration_test/integration_test.dart';
import 'completion_actions_test.dart';
import 'completion_confirmation_progress_test.dart';
import 'historical_checklist_recompletion_test.dart';
import 'completion_focus_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerCompletionActionTests();
  registerCompletionConfirmationProgressTests();
  registerHistoricalChecklistRecompletionTests();
  registerCompletionFocusTests();
}
