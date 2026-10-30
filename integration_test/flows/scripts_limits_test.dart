// Compiled desktop entrypoint for public runtime corpus.
import 'package:integration_test/integration_test.dart';
import '../support/script_runtime_contract.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerScriptRuntimeContracts();
}
