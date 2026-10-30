// Hermetic real QuickJS -> ExecuteRequest -> Dio -> Hive scripting journeys.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';

import 'mock_server.dart';
import 'script_actions.dart';

void registerScriptPipelineContracts() {
  test(
    'real login captures JWT; next SEND serializes claim '
    'and preserves history template',
    () async {
      final journey = RealScriptJourney();
      await journey.start();
      addTearDown(journey.close);
      final claims = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'session': {'id': 'session-42'},
              }),
            ),
          )
          .replaceAll('=', '');
      final token = 'eyJhbGciOiJub25lIn0.$claims.c2ln';
      final server = await MockServer.start(
        responder: (request) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              request.uri.path == '/login' ? {'token': token} : {'ok': true},
            ),
          );
        },
      );
      addTearDown(server.close);
      final login = HttpRequestConfigEntity(
        id: 'login',
        url: server.url('/login'),
        scripts: RequestScripts(
          postResponse: await loadScriptFixture('login_post.js'),
        ),
      );
      final logged = await journey.send(login);
      expect(logged.error, isNull);
      expect(
        logged.postResponse!.tests.map((test) => test.passed),
        everyElement(isTrue),
      );
      expect((await journey.variables())['access_token'], token);
      final config = HttpRequestConfigEntity(
        id: 'session',
        method: 'POST',
        url: server.url('/echo'),
        body: '{{original_template}}',
        scripts: RequestScripts(
          preRequest: await loadScriptFixture('jwt_session_pre.js'),
        ),
      );
      final result = await journey.send(config);
      expect(result.error, isNull, reason: result.error?.message);
      expect(result.response!.statusCode, 200);
      final request = server.received.last;
      expect(request.method, 'POST');
      expect(request.headers['x-session'], 'session-42');
      expect(jsonDecode(request.body), {
        'sessionId': 'session-42',
        'description': 'texto com "aspas" e acentuação',
      });
      expect(config.body, '{{original_template}}');
      final history = await di.sl<HistoryRepository>().watchHistory().first;
      expect(history.first.body, '{{original_template}}');
      expect(history.first.scripts, config.scripts);
      await journey.restart();
      expect((await journey.variables())['access_token'], token);
      final replay = await di.sl<HistoryRepository>().watchHistory().first;
      expect(replay.first.scripts, config.scripts);
      expect((await journey.send(config, approve: false)).error, isNull);
      expect(server.received.length, 3);
    },
  );

  test(
    'real pre failure blocks HTTP; post failure preserves response '
    'and tests without committing',
    () async {
      final journey = RealScriptJourney();
      await journey.start();
      addTearDown(journey.close);
      final server = await MockServer.start(json: {'ok': true});
      addTearDown(server.close);
      final pre = await journey.send(
        HttpRequestConfigEntity(
          id: 'pre',
          url: server.baseUrl,
          scripts: RequestScripts(
            preRequest: await loadScriptFixture('pre_failure.js'),
          ),
        ),
      );
      expect(pre.error?.kind, ScriptErrorKind.runtime);
      expect(pre.error?.line, 2);
      expect(pre.response, isNull);
      expect(server.received, isEmpty);
      expect(await journey.variables(), isNot(contains('must_not_persist')));
      final post = await journey.send(
        HttpRequestConfigEntity(
          id: 'post',
          url: server.baseUrl,
          scripts: RequestScripts(
            postResponse: await loadScriptFixture('post_failure.js'),
          ),
        ),
      );
      expect(post.error?.kind, ScriptErrorKind.runtime);
      expect(post.response!.statusCode, 200);
      expect(post.postResponse!.tests.single.passed, isTrue);
      expect(server.received.length, 1);
      expect(await journey.variables(), isNot(contains('must_not_persist')));
    },
  );

  test(
    'post-response tests isolate failure and execute for HTTP 400 and 500',
    () async {
      final journey = RealScriptJourney();
      await journey.start();
      addTearDown(journey.close);
      for (final status in [200, 400, 500]) {
        final server = await MockServer.start(
          responder: (request) {
            request.response
              ..statusCode = status
              ..headers.contentType = ContentType.json
              ..headers.set('X-Trace', 'trace-42')
              ..write('{"nullable":null}');
          },
        );
        addTearDown(server.close);
        final result = await journey.send(
          HttpRequestConfigEntity(
            id: 'status-$status',
            url: server.baseUrl,
            scripts: RequestScripts(
              postResponse: await loadScriptFixture('response_tests_post.js'),
            ),
          ),
        );
        expect(result.error, isNull);
        expect(result.response!.statusCode, status);
        expect(result.postResponse!.tests.length, 5);
        expect(
          result.postResponse!.tests.where((test) => test.passed).length,
          status == 200 ? 4 : 3,
        );
        expect(result.postResponse!.tests.last.passed, isTrue);
        expect(result.postResponse!.logs, isNotEmpty);
        expect(server.received.length, 1);
      }
    },
  );

  test(
    'real local trust survives restart; changed source blocks HTTP',
    () async {
      final journey = RealScriptJourney();
      await journey.start();
      addTearDown(journey.close);
      final server = await MockServer.start();
      addTearDown(server.close);
      final config = HttpRequestConfigEntity(
        id: 'persisted',
        url: server.baseUrl,
        scripts: RequestScripts(
          preRequest: await loadScriptFixture('console_limit.js'),
          postResponse: await loadScriptFixture('post_failure.js'),
          postResponseEnabled: false,
        ),
      );
      expect(
        (await journey.send(config, approve: false)).error?.kind,
        ScriptErrorKind.untrusted,
      );
      expect(server.received, isEmpty);
      await di.sl<TabsRepository>().saveTabs([
        HttpRequestTabEntity(tabId: 'saved-script-tab', config: config),
      ]);
      expect((await journey.send(config)).error, isNull);
      await journey.restart();
      final restored = (await di.sl<TabsRepository>().getTabs()).single.config;
      expect(restored.scripts, config.scripts);
      expect(restored.scripts.postResponseEnabled, isFalse);
      expect((await journey.send(restored, approve: false)).error, isNull);
      final changed = restored.copyWith(
        scripts: restored.scripts.copyWith(
          preRequest: await loadScriptFixture('pre_failure.js'),
        ),
      );
      expect(
        (await journey.send(changed, approve: false)).error?.kind,
        ScriptErrorKind.untrusted,
      );
      expect(server.received.length, 2);
      expect(await journey.variables(), isNot(contains('must_not_persist')));
    },
  );

  test(
    'real cancellation and supersession prevent old HTTP and recover',
    () async {
      final journey = RealScriptJourney();
      await journey.start();
      addTearDown(journey.close);
      final server = await MockServer.start();
      addTearDown(server.close);
      final cancellation = ScriptCancellation();
      final looping = HttpRequestConfigEntity(
        id: 'cancel',
        url: server.baseUrl,
        scripts: RequestScripts(
          preRequest: await loadScriptFixture('infinite_loop.js'),
        ),
      );
      final running = journey.send(looping, cancellation: cancellation);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      cancellation.cancel();
      expect((await running).cancelled, isTrue);
      expect(server.received, isEmpty);
      final old = journey.send(looping);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final current = await journey.send(
        HttpRequestConfigEntity(id: 'current', url: server.baseUrl),
      );
      expect(current.response!.statusCode, 200);
      expect((await old).cancelled, isTrue);
      expect(server.received.length, 1);
    },
  );

  test(
    'real regex and header capture persist and resolve into next request',
    () async {
      final journey = RealScriptJourney();
      await journey.start();
      addTearDown(journey.close);
      final server = await MockServer.start(
        responder: (request) {
          request.response.headers.set('X-Trace', 'trace-42');
          request.response.write('b=captured42');
        },
      );
      addTearDown(server.close);
      final result = await journey.send(
        HttpRequestConfigEntity(
          id: 'extract',
          url: server.baseUrl,
          scripts: RequestScripts(
            postResponse: await loadScriptFixture('extract_regex_post.js'),
          ),
        ),
      );
      expect(result.error, isNull);
      expect(await journey.variables(), {
        'capture': 'captured42',
        'trace': 'trace-42',
      });
      await journey.send(
        HttpRequestConfigEntity(
          id: 'captured',
          url: server.url('/{{capture}}'),
          headers: const {'X-Captured': '{{trace}}'},
        ),
      );
      expect(server.received.last.uri.path, '/captured42');
      expect(server.received.last.headers['x-captured'], 'trace-42');
    },
  );

  test('invalid JWT and JWE fail before real HTTP', () async {
    final journey = RealScriptJourney();
    await journey.start();
    addTearDown(journey.close);
    final server = await MockServer.start();
    addTearDown(server.close);
    for (final token in ['invalid', 'a.b.c.d.e']) {
      await journey.environments.putEnvironment(
        EnvironmentEntity(
          id: 'scripts-env',
          name: 'Scripts',
          variables: {'access_token': token},
        ),
      );
      final result = await journey.send(
        HttpRequestConfigEntity(
          id: 'jwt-invalid',
          url: server.baseUrl,
          scripts: RequestScripts(
            preRequest: await loadScriptFixture('jwt_session_pre.js'),
          ),
        ),
      );
      expect(result.error?.kind, ScriptErrorKind.runtime);
      expect(result.response, isNull);
    }
    expect(server.received, isEmpty);
  });

  test(
    'deleting captured environment during HTTP preserves response '
    'without resurrecting it',
    () async {
      final journey = RealScriptJourney();
      await journey.start();
      addTearDown(journey.close);
      final received = Completer<void>();
      final release = Completer<void>();
      final server = await MockServer.start(
        responder: (request) async {
          received.complete();
          await release.future;
          request.response.headers.set('X-Trace', 'trace-42');
          request.response.write('b=captured42');
        },
      );
      addTearDown(server.close);
      final pending = journey.send(
        HttpRequestConfigEntity(
          id: 'deleted-env',
          url: server.baseUrl,
          scripts: RequestScripts(
            postResponse: await loadScriptFixture('extract_regex_post.js'),
          ),
        ),
      );
      await received.future;
      await journey.environments.deleteEnvironment('scripts-env');
      await journey.environments.putEnvironment(
        EnvironmentEntity(id: 'new-env', name: 'Other'),
      );
      release.complete();
      final result = await pending;
      expect(result.response!.statusCode, 200);
      expect(result.error?.kind, ScriptErrorKind.persistence);
      final environments = await journey.environments.getEnvironments();
      expect(environments.single.id, 'new-env');
      expect(environments.single.variables, isEmpty);
    },
  );
}
