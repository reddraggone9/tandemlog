import 'package:integration_test/integration_test.dart';
import '../test/civil_date_picker_layout_test.dart' as checks;
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerCivilDatePickerWorkflowTests();
}

void registerCivilDatePickerWorkflowTests() {
  var recordingStarted = false;
  checks.registerCivilDatePickerLayoutTests(
    input: pixels.tap,
    capture: (tester, name) async {
      await pixels.capture(tester, name);
      if (!recordingStarted && name == 'tasks-dark-2.0x') {
        recordingStarted = true;
        await pixels.startRecording(tester);
      }
    },
  );
}
