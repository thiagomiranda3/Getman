// Compiled desktop entrypoint for real scripting pipeline contracts.
import 'package:integration_test/integration_test.dart';
import '../support/script_pipeline_contract.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerScriptPipelineContracts();
}
