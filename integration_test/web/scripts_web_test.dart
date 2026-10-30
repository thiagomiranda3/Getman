// Browser E2E: actual Worker/QuickJS, production Dio and IndexedDB-backed Hive.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/scripting/data/repositories/script_runtime_repository_impl.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman/features/scripting/domain/repositories/script_trust_repository.dart';
import 'package:getman/features/tabs/domain/entities/execute_request_result.dart';
import 'package:getman/features/tabs/domain/entities/script_variable_snapshot.dart';
import 'package:getman/features/tabs/domain/usecases/execute_request_use_case.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('web real login JWT request and Hive commit', (tester) async {
    const base = String.fromEnvironment('SCRIPT_FIXTURE_BASE_URL');
    expect(base, isNotEmpty);
    await di.init();
    addTearDown(di.reset);
    final environments = di.sl<EnvironmentsRepository>();
    await environments.putEnvironment(
      EnvironmentEntity(id: 'web-script-env', name: 'Web test'),
    );
    final http = Dio();
    addTearDown(() => http.close(force: true));
    Future<String> fixture(String name) async => (await http.get<String>(
      '$base/fixtures/$name',
      options: Options(responseType: ResponseType.plain),
    )).data!;
    var serial = 0;
    Future<ExecuteRequestResult> send(HttpRequestConfigEntity config) async {
      await di.sl<ScriptTrustRepository>().trust(config.id, config.scripts);
      final env = (await environments.getEnvironments()).firstWhere(
        (e) => e.id == 'web-script-env',
      );
      return di.sl<ExecuteRequestUseCase>()(
        executionId: 'web-${serial++}',
        tabId: 'web',
        config: config,
        variables: ScriptVariableSnapshot(
          environmentId: env.id,
          environmentVariables: env.variables,
        ),
        cancellation: ScriptCancellation(),
      );
    }

    final login = await send(
      HttpRequestConfigEntity(
        id: 'web-login',
        url: '$base/login',
        scripts: RequestScripts(postResponse: await fixture('login_post.js')),
      ),
    );
    expect(login.error, isNull);
    final config = HttpRequestConfigEntity(
      id: 'web-echo',
      method: 'POST',
      url: '$base/echo',
      body: '{{template}}',
      scripts: RequestScripts(preRequest: await fixture('jwt_session_pre.js')),
    );
    final result = await send(config);
    expect(result.error, isNull);
    final body = jsonDecode(result.response!.body) as Map<String, dynamic>;
    expect(body['session'], 'sessao-web-42');
    expect(body['body'], {
      'sessionId': 'sessao-web-42',
      'description': 'texto com "aspas" e acentuação',
    });
    expect(config.body, '{{template}}');
    expect(
      (await environments.getEnvironments())
          .firstWhere((e) => e.id == 'web-script-env')
          .variables,
      contains('access_token'),
    );
  });

  testWidgets(
    'web real corpus interrupts quotas and cancellation then recovers',
    (tester) async {
      const base = String.fromEnvironment('SCRIPT_FIXTURE_BASE_URL');
      final http = Dio();
      addTearDown(() => http.close(force: true));
      Future<String> fixture(String name) async => (await http.get<String>(
        '$base/fixtures/$name',
        options: Options(responseType: ResponseType.plain),
      )).data!;
      final runtime = ScriptRuntimeRepositoryImpl();
      addTearDown(runtime.close);
      ScriptInput input(String source) => ScriptInput(
        executionId: 'web-limits',
        tabId: 'limits',
        source: source,
        phase: ScriptPhase.preRequest,
        config: const HttpRequestConfigEntity(id: 'limits'),
      );
      for (final file in [
        'infinite_loop.js',
        'pending_promise.js',
        'memory_limit.js',
      ]) {
        final result = await runtime.execute(
          input(await fixture(file)),
          cancellation: ScriptCancellation(),
          limits: ScriptLimits(
            timeout: Duration(
              milliseconds: file == 'memory_limit.js' ? 3000 : 200,
            ),
            memoryBytes: 2 * 1024 * 1024,
          ),
        );
        expect(
          result.error?.kind,
          file == 'memory_limit.js'
              ? ScriptErrorKind.memoryLimit
              : ScriptErrorKind.timeout,
          reason: '$file: ${result.error?.message}',
        );
      }
      final cancellation = ScriptCancellation();
      final pending = runtime.execute(
        input(await fixture('infinite_loop.js')),
        cancellation: cancellation,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cancellation.cancel();
      expect((await pending).error?.kind, ScriptErrorKind.cancelled);
      final recovered = await runtime.execute(
        input(await fixture('console_limit.js')),
        cancellation: ScriptCancellation(),
      );
      expect(recovered.error, isNull);
      expect(recovered.logs.length, lessThanOrEqualTo(200));
    },
  );
}
