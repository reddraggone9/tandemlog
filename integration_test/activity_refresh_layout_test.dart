import 'package:integration_test/integration_test.dart';
import '../test/activity_refresh_layout_test.dart'
    show activityRefreshLayoutTests;
import 'native_text_fixtures.dart' show captureNativeFixtureUi;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  activityRefreshLayoutTests(
    native: true,
    capture: (tester, name) => captureNativeFixtureUi(tester, name),
  );
}
