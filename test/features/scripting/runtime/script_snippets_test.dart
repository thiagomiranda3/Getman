import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/scripting/data/repositories/script_runtime_repository_impl.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_response.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman/features/scripting/domain/logic/script_snippets.dart';

import '../support/runtime_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'every shipped snippet executes on the public QuickJS runtime',
    () async {
      final runtime = ScriptRuntimeRepositoryImpl(
        assetBundle: ScriptRuntimeTestAssets(),
      );
      addTearDown(runtime.close);
      final payload = base64Url
          .encode(utf8.encode('{"session":{"id":"session-42"}}'))
          .replaceAll('=', '');
      final token = 'eyJhbGciOiJIUzI1NiJ9.$payload.c2ln';
      for (final snippet in ScriptSnippets.all) {
        final result = await runtime.execute(
          ScriptInput(
            executionId: 'snippet',
            tabId: 'tab',
            source: snippet.source,
            phase: snippet.phase,
            environmentId: 'env',
            environmentVariables: {'access_token': token},
            config: const HttpRequestConfigEntity(id: 'request'),
            response: ScriptResponse(
              status: 200,
              text: jsonEncode({'token': token}),
              headers: const {'X-Trace': 'trace-42'},
            ),
          ),
          cancellation: ScriptCancellation(),
        );
        expect(result.error, isNull, reason: snippet.title);
        expect(
          result.tests.every((test) => test.passed),
          isTrue,
          reason: snippet.title,
        );
        switch (snippet.id) {
          case 'jwt-session':
            expect(result.temporaryVariables['session_id'], 'session-42');
          case 'capture-token':
            expect(result.environmentPatch.sets['access_token'], token);
          case 'response-tests':
            expect(result.tests, hasLength(2));
          case 'capture-header':
            expect(result.environmentPatch.sets['trace'], 'trace-42');
        }
      }
    },
  );
}
