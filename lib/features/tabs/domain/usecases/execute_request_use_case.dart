// Coordinates trusted pre-script, HTTP and post-script with guarded commits.
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/cancel_handle.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/scripting/domain/entities/script_error.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/entities/script_response.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman/features/scripting/domain/repositories/script_runtime_repository.dart';
import 'package:getman/features/scripting/domain/repositories/script_trust_repository.dart';
import 'package:getman/features/tabs/domain/entities/execute_request_result.dart';
import 'package:getman/features/tabs/domain/entities/script_variable_snapshot.dart';
import 'package:getman/features/tabs/domain/logic/script_execution_registry.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';

class ExecuteRequestUseCase {
  ExecuteRequestUseCase({
    required this.sendRequest,
    required this.runtime,
    required this.environments,
    required this.trust,
    required this.registry,
  });
  final SendRequestUseCase sendRequest;
  final ScriptRuntimeRepository runtime;
  final EnvironmentsRepository environments;
  final ScriptTrustRepository trust;
  final ScriptExecutionRegistry registry;
  Future<ExecuteRequestResult> call({
    required String executionId,
    required String tabId,
    required HttpRequestConfigEntity config,
    required ScriptVariableSnapshot variables,
    required ScriptCancellation cancellation,
    NetworkCancelHandle? cancelHandle,
    void Function(ScriptExecutionPhase phase)? onPhase,
    void Function(ExecuteRequestResult result)? onProgress,
  }) async {
    registry.register(tabId, executionId);
    bool current() =>
        registry.isCurrent(tabId, executionId) &&
        !cancellation.isCancelled &&
        !(cancelHandle?.isCancelled ?? false);
    ScriptOutput? pre;
    ScriptOutput? post;
    HttpResponseEntity? response;
    var effective = config;
    final env = Map<String, String>.of(variables.environmentVariables);
    var temporary = <String, String>{};
    final secrets = <String>{
      for (final key in variables.secretKeys) ...[
        if (variables.environmentVariables[key]?.isNotEmpty ?? false)
          variables.environmentVariables[key]!,
        if (variables.collectionVariables[key]?.isNotEmpty ?? false)
          variables.collectionVariables[key]!,
      ],
    };
    void captureSecrets(ScriptOutput output) {
      secrets.addAll(output.secretValues);
      for (final key in variables.secretKeys) {
        for (final value in [
          output.environmentPatch.sets[key],
          output.temporaryVariables[key],
        ]) {
          if (value != null && value.isNotEmpty) secrets.add(value);
        }
      }
    }

    var phase = ScriptPhase.preRequest;
    ExecuteRequestResult result([ScriptError? error]) => ExecuteRequestResult(
      response: response,
      preRequest: pre,
      postResponse: post,
      error: error,
      secretValues: Set.unmodifiable(secrets),
    );
    Future<void> commit(ScriptOutput output) async {
      final patch = output.environmentPatch;
      if (patch.isEmpty) return;
      final id = variables.environmentId;
      if (id == null) {
        throw StateError('Select an environment before changing variables');
      }
      if (!current()) return;
      await environments.applyVariablePatch(id, patch);
      if (!current()) return;
      patch.unsets.forEach(env.remove);
      env.addAll(patch.sets);
    }

    Future<ScriptOutput> run(String source, ScriptPhase stage) =>
        runtime.execute(
          ScriptInput(
            executionId: executionId,
            tabId: tabId,
            source: source,
            phase: stage,
            config: effective,
            environmentId: variables.environmentId,
            secretKeys: variables.secretKeys,
            environmentVariables: env,
            collectionVariables: variables.collectionVariables,
            temporaryVariables: temporary,
            response: response == null
                ? null
                : ScriptResponse(
                    status: response.statusCode,
                    text: response.body,
                    headers: response.headers,
                    durationMs: response.durationMs,
                  ),
          ),
          cancellation: cancellation,
        );
    try {
      if (!current()) return const ExecuteRequestResult.cancelled();
      final scripts = config.scripts;
      if (scripts.hasEnabledScripts) {
        if (scripts.apiVersion != 1) {
          return result(
            const ScriptError(
              kind: ScriptErrorKind.unsupportedApi,
              message: 'Unsupported script API version',
              phase: ScriptPhase.preRequest,
            ),
          );
        }
        final trusted = await trust.isTrusted(config.id, scripts);
        if (!current()) return const ExecuteRequestResult.cancelled();
        if (!trusted) {
          return result(
            const ScriptError(
              kind: ScriptErrorKind.untrusted,
              message: 'Review and trust these scripts before sending',
              phase: ScriptPhase.preRequest,
            ),
          );
        }
      }
      if (scripts.preRequestEnabled && scripts.preRequest.trim().isNotEmpty) {
        onPhase?.call(ScriptExecutionPhase.preRequest);
        pre = await run(scripts.preRequest, phase);
        if (!current()) return const ExecuteRequestResult.cancelled();
        captureSecrets(pre);
        onProgress?.call(result());
        if (!pre.succeeded) return result(pre.error);
        if (pre.tests.any((test) => !test.passed)) {
          return result(
            const ScriptError(
              kind: ScriptErrorKind.runtime,
              message: 'Pre-request tests failed; HTTP was not sent',
              phase: ScriptPhase.preRequest,
            ),
          );
        }
        await commit(pre);
        if (!current()) return const ExecuteRequestResult.cancelled();
        temporary = Map.of(pre.temporaryVariables);
        final patch = pre.requestPatch;
        final headers = Map<String, String>.of(config.headers);
        for (final entry in patch.headerSets.entries) {
          headers.removeWhere(
            (name, _) => name.toLowerCase() == entry.key.toLowerCase(),
          );
          headers[entry.key] = entry.value;
        }
        final disabledHeaders = Set<String>.of(config.disabledHeaderKeys)
          ..removeWhere(
            (name) => patch.headerSets.keys.any(
              (key) => key.toLowerCase() == name.toLowerCase(),
            ),
          );
        for (final key in patch.headerUnsets) {
          headers.removeWhere(
            (name, _) => name.toLowerCase() == key.toLowerCase(),
          );
        }
        effective = config.copyWith(
          url: patch.url ?? config.url,
          method: patch.method ?? config.method,
          body: patch.body ?? config.body,
          headers: headers,
          disabledHeaderKeys: disabledHeaders,
        );
      }
      if (!current()) return const ExecuteRequestResult.cancelled();
      onPhase?.call(ScriptExecutionPhase.network);
      try {
        response = await sendRequest(
          config: effective,
          historyConfig: config,
          canRecordHistory: current,
          envVars: {...variables.collectionVariables, ...env, ...temporary},
          cancelHandle: cancelHandle,
        );
      } on NetworkFailure catch (f) {
        if (!current() || f.type == NetworkFailureType.cancelled) {
          return const ExecuteRequestResult.cancelled();
        }
        if (f.statusCode == null || f.statusCode == 0) rethrow;
        response = HttpResponseEntity(
          statusCode: f.statusCode!,
          body: f.message,
          headers: const {},
          durationMs: 0,
        );
      }
      if (!current()) return const ExecuteRequestResult.cancelled();
      onProgress?.call(result());
      phase = ScriptPhase.postResponse;
      if (scripts.postResponseEnabled &&
          scripts.postResponse.trim().isNotEmpty) {
        onPhase?.call(ScriptExecutionPhase.postResponse);
        post = await run(scripts.postResponse, phase);
        if (!current()) return const ExecuteRequestResult.cancelled();
        captureSecrets(post);
        onProgress?.call(result());
        if (!post.succeeded) return result(post.error);
        await commit(post);
        if (!current()) return const ExecuteRequestResult.cancelled();
      }
      return result();
    } on NetworkFailure {
      rethrow;
    } on Object catch (error) {
      if (!current()) return const ExecuteRequestResult.cancelled();
      return result(
        ScriptError(
          kind: ScriptErrorKind.persistence,
          message: 'Unable to commit script variables: $error',
          phase: phase,
        ),
      );
    } finally {
      registry.finish(tabId, executionId);
    }
  }
}
