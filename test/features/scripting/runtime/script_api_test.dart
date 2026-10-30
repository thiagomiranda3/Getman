import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/scripting/data/repositories/script_runtime_repository_impl.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/entities/script_response.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';

import '../support/runtime_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ScriptRuntimeRepositoryImpl runtime;
  // The browser test server exposes checked-in assets through test/ symlinks.
  // Its platform asset channel is absent; fetch the actual bytes over HTTP.
  setUp(
    () => runtime = ScriptRuntimeRepositoryImpl(
      assetBundle: ScriptRuntimeTestAssets(),
    ),
  );
  tearDown(() async => runtime.close());

  Future<ScriptOutput> run(
    String source, {
    ScriptPhase phase = ScriptPhase.preRequest,
    String? environmentId = 'env',
    Map<String, String> variables = const {},
    ScriptResponse? response,
    BodyType bodyType = BodyType.raw,
  }) => runtime.execute(
    ScriptInput(
      executionId: 'run',
      tabId: 'tab',
      source: source,
      phase: phase,
      config: HttpRequestConfigEntity(
        id: 'request',
        url: 'https://example.test',
        headers: const {'X-Key': 'initial'},
        body: '{}',
        bodyType: bodyType,
      ),
      environmentId: environmentId,
      environmentVariables: variables,
      collectionVariables: const {'base': 'collection', 'fallback': 'lower'},
      temporaryVariables: const {'fallback': 'upper'},
      response: response,
    ),
    cancellation: ScriptCancellation(),
  );

  test(
    'JWT Unicode session claim becomes temporary payload variable',
    () async {
      final payload = base64Url
          .encode(utf8.encode('{"session":{"id":"sessão-42"}}'))
          .replaceAll('=', '');
      final result = await run(
        '''
      const claims = gm.jwt.decode(gm.variables.get('token'));
      gm.variables.set('session_id', claims.session.id);
      gm.request.setBody(JSON.stringify({session: claims.session.id}));
    ''',
        variables: {'token': 'eyJhbGciOiJIUzI1NiJ9.$payload.c2ln'},
      );
      expect(result.error, isNull);
      expect(result.temporaryVariables['session_id'], 'sessão-42');
      expect(result.requestPatch.body, '{"session":"sessão-42"}');
      expect(result.environmentPatch.isEmpty, isTrue);
    },
  );

  test(
    'layered variables preserve missing, JSON null and prototype-like names',
    () async {
      final result = await run(
        '''
      if (gm.variables.get('base') !== 'environment') throw Error('precedence');
      if (gm.variables.get('missing') !== undefined || gm.variables.has('missing')) throw Error('missing');
      gm.variables.unset('fallback');
      if (gm.variables.get('fallback') !== 'lower') throw Error('unset');
      gm.variables.set('__proto__', {session: 42});
      gm.variables.set('nil', null);
      gm.environment.set('persist', [1, true]);
      if (gm.environment.get('persist') !== '[1,true]') throw Error('pending');
      gm.environment.unset('old');
    ''',
        variables: const {'base': 'environment', 'old': 'value'},
      );
      expect(result.error, isNull);
      expect(result.temporaryVariables, {
        '__proto__': '{"session":42}',
        'nil': 'null',
      });
      expect(result.environmentPatch.sets, {'persist': '[1,true]'});
      expect(result.environmentPatch.unsets, {'old'});
    },
  );

  for (final expression in [
    'undefined',
    'NaN',
    'Infinity',
    '1n',
    '() => 1',
    'Symbol("x")',
    '({nested: undefined})',
    '({toJSON: () => 1})',
    '(() => { const a = {}; a.self = a; return a; })()',
  ]) {
    test('variables reject non-JSON value $expression', () async {
      final result = await run("gm.variables.set('bad', $expression);");
      expect(result.error, isNotNull);
      expect(result.temporaryVariables.containsKey('bad'), isFalse);
    });
  }

  test(
    'request patch uses case-insensitive headers and validated method',
    () async {
      final result = await run('''
      if (gm.request.headers.get('x-key') !== 'initial') throw Error('header');
      gm.request.headers.set('x-key', 'updated');
      gm.request.headers.unset('X-KEY');
      gm.request.headers.set('X-Other', 'value');
      gm.request.setUrl('https://example.test/changed');
      gm.request.setMethod('POST');
    ''');
      expect(result.error, isNull);
      expect(result.requestPatch.url, 'https://example.test/changed');
      expect(result.requestPatch.method, 'POST');
      expect(result.requestPatch.headerSets, {'X-Other': 'value'});
      expect(
        result.requestPatch.headerUnsets.map((key) => key.toLowerCase()),
        contains('x-key'),
      );
    },
  );

  test('response exposes headers, JSONPath null and escaped keys', () async {
    final result = await run(
      r'''
      if (gm.response.status !== 400 || gm.response.durationMs !== 12) throw Error('status');
      if (gm.response.header('content-TYPE') !== 'application/json') throw Error('headers');
      if (!gm.response.lookup("$.items[0]['a.b']").found || gm.response.lookup("$.items[0]['a.b']").value !== null) throw Error('null');
      if (gm.response.lookup('$.absent').found) throw Error('missing');
      if (gm.response.lookup('$').value.items.length !== 1) throw Error('root');
      gm.variables.set('status', gm.response.status);
    ''',
      phase: ScriptPhase.postResponse,
      response: ScriptResponse(
        status: 400,
        durationMs: 12,
        text: '{"items":[{"a.b":null}]}',
        headers: const {'Content-Type': 'application/json'},
      ),
    );
    expect(result.error, isNull);
    expect(result.temporaryVariables['status'], '400');
  });

  test('helpers round-trip UTF8 and URL-safe padding', () async {
    final result = await run('''
      const text = 'sessão 🚀';
      if (gm.base64.decode(gm.base64.encode(text)) !== text) throw Error('base64');
      if (gm.base64url.decode(gm.base64url.encode(text)) !== text) throw Error('url');
      if (gm.base64url.decode('YQ==') !== 'a') throw Error('padding');
    ''');
    expect(result.error, isNull);
  });

  for (final source in [
    "gm.jwt.decode('a.b.c.d.e');",
    "gm.jwt.decode('x.@@.x');",
    "gm.jwt.decode('x.bnVsbA.x');",
    "gm.base64.decode('a');",
    "gm.base64.decode('YQ=');",
    "gm.base64.decode('/w==');",
    "gm.request.setMethod('INVALID');",
  ]) {
    test('malformed input fails explicitly: $source', () async {
      expect((await run(source)).error, isNotNull);
    });
  }

  test('environment mutations without selected environment fail', () async {
    expect(
      (await run("gm.environment.set('x', '1');", environmentId: null)).error,
      isNotNull,
    );
  });
  test('multipart body mutation fails', () async {
    expect(
      (await run(
        "gm.request.setBody('{}');",
        bodyType: BodyType.multipart,
      )).error,
      isNotNull,
    );
  });
  test(
    'post stage cannot mutate request and user return cannot forge output',
    () async {
      expect(
        (await run(
          "gm.request.setUrl('/bad');",
          phase: ScriptPhase.postResponse,
          response: ScriptResponse(status: 200),
        )).error,
        isNotNull,
      );
      final result = await run(
        "return {temporaryVariables:{forged:'yes'}, "
        "environmentPatch:{sets:{forged:'yes'}}};",
      );
      expect(result.error, isNull);
      expect(result.temporaryVariables.containsKey('forged'), isFalse);
      expect(result.environmentPatch.isEmpty, isTrue);
    },
  );
  test('input maps preserve literal prototype-like variable names', () async {
    final result = await run(
      "gm.variables.set('copied', gm.environment.get('__proto__'));",
      variables: const {'__proto__': 'literal'},
    );
    expect(result.error, isNull);
    expect(result.temporaryVariables['copied'], 'literal');
  });
  test('uncaught errors report the original user source line', () async {
    final result = await run('const n=1;\nthrow new Error("broken");');
    expect(result.error?.message, contains('broken'));
    expect(result.error?.line, 2);
  });
}
