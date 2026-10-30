import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/core/network/cancel_handle.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman/features/scripting/domain/repositories/script_runtime_repository.dart';
import 'package:getman/features/scripting/domain/repositories/script_trust_repository.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/tabs/domain/entities/execute_request_result.dart';
import 'package:getman/features/tabs/domain/entities/script_variable_snapshot.dart';
import 'package:getman/features/tabs/domain/logic/script_execution_registry.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/execute_request_use_case.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:mocktail/mocktail.dart';

class _Tabs extends Mock implements TabsRepository {}

class _History extends Mock implements AddToHistoryUseCase {}

class _Settings extends Mock implements GetSettingsUseCase {}

class ScriptEnvironment extends Mock implements EnvironmentsRepository {
  final values = <String, String>{};
  final ids = <String>[];
  bool deleted = false;
  bool fail = false;
  Future<void> Function()? admitted;
  @override
  Future<void> applyVariablePatch(String id, ScriptPatch patch) async {
    ids.add(id);
    await admitted?.call();
    if (fail || deleted) {
      throw StateError('Environment unavailable');
    }
    values
      ..removeWhere((key, _) => patch.unsets.contains(key))
      ..addAll(patch.sets);
  }
}

class ScriptRuntime implements ScriptRuntimeRepository {
  final inputs = <ScriptInput>[];
  Future<ScriptOutput> Function(ScriptInput)? run;
  @override
  Future<ScriptOutput> execute(
    ScriptInput input, {
    required ScriptCancellation cancellation,
    ScriptLimits limits = const ScriptLimits(),
  }) async {
    inputs.add(input);
    return run?.call(input) ?? ScriptOutput();
  }

  @override
  Future<void> close() async {}
}

class ScriptTrust implements ScriptTrustRepository {
  bool trusted = true;
  Future<bool> Function()? check;
  @override
  Future<bool> isTrusted(String configId, RequestScripts scripts) async =>
      check?.call() ?? trusted;
  @override
  Future<void> trust(String configId, RequestScripts scripts) async {}
}

class RecordingSend extends SendRequestUseCase {
  RecordingSend()
    : super(
        tabsRepository: _Tabs(),
        addToHistoryUseCase: _History(),
        getSettingsUseCase: _Settings(),
      );
  int calls = 0;
  HttpRequestConfigEntity? sent;
  HttpRequestConfigEntity? history;
  Map<String, String>? variables;
  Future<HttpResponseEntity> Function()? network;
  @override
  Future<HttpResponseEntity> call({
    required HttpRequestConfigEntity config,
    Map<String, String> envVars = const {},
    NetworkCancelHandle? cancelHandle,
    HttpRequestConfigEntity? historyConfig,
    bool Function()? canRecordHistory,
  }) async {
    calls++;
    sent = config;
    history = historyConfig;
    variables = envVars;
    return network?.call() ??
        const HttpResponseEntity(
          statusCode: 200,
          body: 'ok',
          headers: {},
          durationMs: 1,
        );
  }
}

class ScriptExecutionHarness {
  ScriptExecutionHarness() {
    execute = ExecuteRequestUseCase(
      sendRequest: network,
      runtime: runtime,
      environments: environment,
      trust: trust,
      registry: registry,
    );
  }
  final network = RecordingSend();
  final runtime = ScriptRuntime();
  final environment = ScriptEnvironment();
  final trust = ScriptTrust();
  final registry = ScriptExecutionRegistry();
  late final ExecuteRequestUseCase execute;
  int serial = 0;
  int get networkCalls => network.calls;
  Future<Map<String, String>> persistedVariables() async =>
      Map.of(environment.values);
  Future<ExecuteRequestResult> send({
    String pre = '',
    String post = '',
    String tabId = 'tab',
    ScriptCancellation? cancellation,
    ScriptVariableSnapshot? variables,
  }) => execute(
    executionId: 'run${serial++}',
    tabId: tabId,
    config: HttpRequestConfigEntity(
      id: 'config',
      url: 'https://{{host}}',
      scripts: RequestScripts(preRequest: pre, postResponse: post),
    ),
    variables:
        variables ??
        ScriptVariableSnapshot(
          environmentId: 'env',
          environmentVariables: const {'host': 'original'},
        ),
    cancellation: cancellation ?? ScriptCancellation(),
  );
}
