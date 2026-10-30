// Single app build for real script pipeline, quotas, persistence and UI flows.
import 'package:integration_test/integration_test.dart';
import 'flows/scripts_jwt_test.dart' as journey;
import 'flows/scripts_limits_test.dart' as limits;
import 'flows/scripts_ui_test.dart' as ui;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  journey.main();
  limits.main();
  ui.main();
}
