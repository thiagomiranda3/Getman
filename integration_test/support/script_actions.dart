// Real scripting pipeline fixture: isolated Hive profile, production DI,
// production QuickJS bridge and Dio against a loopback HTTP server.
import 'dart:convert';
import 'dart:io';

import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman/features/scripting/domain/repositories/script_trust_repository.dart';
import 'package:getman/features/tabs/domain/entities/execute_request_result.dart';
import 'package:getman/features/tabs/domain/entities/script_variable_snapshot.dart';
import 'package:getman/features/tabs/domain/usecases/execute_request_use_case.dart';

Future<String> loadScriptFixture(String name) async {
  const base = String.fromEnvironment('SCRIPT_FIXTURE_BASE_URL');
  if (base.isNotEmpty) {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$base/fixtures/$name'));
      final response = await request.close();
      if (response.statusCode != 200) throw StateError('Missing fixture $name');
      return await utf8.decoder.bind(response).join();
    } finally {
      client.close(force: true);
    }
  }
  const configured = String.fromEnvironment('SCRIPT_FIXTURE_DIRECTORY');
  if (configured.isNotEmpty) return File('$configured/$name').readAsString();
  var directory = Directory.current;
  for (var attempt = 0; attempt < 20; attempt++) {
    final file = File(
      '${directory.path}/integration_test/fixtures/scripts/$name',
    );
    if (file.existsSync()) return file.readAsString();
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  directory = File(Platform.resolvedExecutable).parent;
  for (var attempt = 0; attempt < 20; attempt++) {
    final file = File(
      '${directory.path}/integration_test/fixtures/scripts/$name',
    );
    if (file.existsSync()) return file.readAsString();
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError('Cannot locate script corpus; set SCRIPT_FIXTURE_DIRECTORY');
}

class RealScriptJourney {
  late Directory profile;
  int _serial = 0;
  EnvironmentsRepository get environments => di.sl<EnvironmentsRepository>();
  Future<void> start() async {
    profile = await Directory.systemTemp.createTemp('getman_scripts_');
    await di.init(storageDirectoryOverride: profile.path);
    await environments.putEnvironment(
      EnvironmentEntity(id: 'scripts-env', name: 'Scripts'),
    );
  }

  Future<Map<String, String>> variables() async =>
      (await environments.getEnvironments()).single.variables;

  Future<ExecuteRequestResult> send(
    HttpRequestConfigEntity config, {
    bool approve = true,
    ScriptCancellation? cancellation,
  }) async {
    if (approve) {
      await di.sl<ScriptTrustRepository>().trust(config.id, config.scripts);
    }
    return di.sl<ExecuteRequestUseCase>()(
      executionId: 'journey-${_serial++}',
      tabId: 'journey-tab',
      config: config,
      variables: ScriptVariableSnapshot(
        environmentId: 'scripts-env',
        environmentVariables: await variables(),
      ),
      cancellation: cancellation ?? ScriptCancellation(),
    );
  }

  Future<void> restart() async {
    await di.reset();
    await di.init(storageDirectoryOverride: profile.path);
  }

  Future<void> close() async {
    await di.reset();
    await profile.delete(recursive: true);
  }
}
