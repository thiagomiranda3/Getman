// VM execution of real QuickJS, production repositories, Hive and Dio.
import 'package:flutter_test/flutter_test.dart';
// Shared test contracts intentionally live beside the desktop harness.
import '../integration_test/support/script_pipeline_contract.dart';
import '../integration_test/support/script_runtime_contract.dart';

void main() {
  _RealHttpBinding();
  registerScriptPipelineContracts();
  registerScriptRuntimeContracts();
}

class _RealHttpBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}
