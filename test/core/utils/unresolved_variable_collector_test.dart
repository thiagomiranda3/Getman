// Unit tests for UnresolvedVariableCollector: every scanned source (URL,
// ENABLED header keys+values, raw/graphql bodies + graphql variables,
// form-field name+value for urlencoded/multipart, auth values), the
// never-scanned rows (parked params, disabled headers — they never ship),
// the always-flagged enabled header KEYS (send never resolves keys),
// body-type gating, resolved/dynamic exclusion, and cross-source dedup with
// first-occurrence order.

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/parked_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/unresolved_variable_collector.dart';

void main() {
  List<String> collect(
    HttpRequestConfigEntity config, [
    Map<String, String> vars = const {},
  ]) => UnresolvedVariableCollector.collect(config: config, variables: vars);

  test('scans the URL', () {
    expect(
      collect(
        const HttpRequestConfigEntity(
          id: 'c',
          url: '{{base}}/users?page={{page}}',
        ),
      ),
      ['base', 'page'],
    );
  });

  test('resolved names and dynamic built-ins are excluded', () {
    expect(
      collect(
        const HttpRequestConfigEntity(
          id: 'c',
          url: r'{{base}}/{{$guid}}/{{missing}}',
        ),
        {'base': 'https://api.dev'},
      ),
      ['missing'],
    );
  });

  test('scans header keys AND values', () {
    expect(
      collect(
        const HttpRequestConfigEntity(
          id: 'c',
          headers: {'X-{{hk}}': 'Bearer {{tok}}'},
        ),
      ),
      ['hk', 'tok'],
    );
  });

  test('IGNORES parked disabled params — they never hit the wire', () {
    expect(
      collect(
        const HttpRequestConfigEntity(
          id: 'c',
          disabledParams: [
            ParkedParamEntity(key: '{{pk}}', value: '{{pv}}', rowIndex: 0),
          ],
        ),
      ),
      isEmpty,
    );
  });

  test('IGNORES disabled header rows — send drops them before resolving', () {
    expect(
      collect(
        const HttpRequestConfigEntity(
          id: 'c',
          headers: {'X-Off': '{{off}}'},
          disabledHeaderKeys: {'X-Off'},
        ),
      ),
      isEmpty,
    );
  });

  test('flags a {{var}} in an enabled header KEY even when it is defined — '
      'send never resolves keys, so it ships literally', () {
    expect(
      collect(
        const HttpRequestConfigEntity(
          id: 'c',
          headers: {'{{auth-header}}': 'v'},
        ),
        {'auth-header': 'X-Api-Key'},
      ),
      ['auth-header'],
    );
  });

  test('scans a raw body; skips none/urlencoded/multipart/binary bodies', () {
    const body = '{"account": "{{bvar}}"}';
    expect(
      collect(const HttpRequestConfigEntity(id: 'c', body: body)),
      ['bvar'],
      reason: 'default bodyType is raw',
    );
    for (final type in [
      BodyType.none,
      BodyType.urlencoded,
      BodyType.multipart,
      BodyType.binary,
    ]) {
      expect(
        collect(
          HttpRequestConfigEntity(id: 'c', body: body, bodyType: type),
        ),
        isEmpty,
        reason: '$type body must not be scanned',
      );
    }
  });

  test('graphql scans body AND graphqlVariables', () {
    expect(
      collect(
        const HttpRequestConfigEntity(
          id: 'c',
          bodyType: BodyType.graphql,
          body: 'query { user(id: "{{uid}}") { name } }',
          graphqlVariables: '{"tenant": "{{tenant}}"}',
        ),
      ),
      ['uid', 'tenant'],
    );
  });

  test('scans auth map values', () {
    expect(
      collect(
        const HttpRequestConfigEntity(
          id: 'c',
          auth: {'type': 'bearer', 'token': '{{tok}}'},
        ),
      ),
      ['tok'],
    );
  });

  test('scans form-field names for urlencoded/multipart bodies', () {
    for (final type in [BodyType.urlencoded, BodyType.multipart]) {
      expect(
        collect(
          HttpRequestConfigEntity(
            id: 'c',
            bodyType: type,
            formFields: const [MultipartFieldEntity(name: '{{fname}}')],
          ),
        ),
        ['fname'],
        reason: '$type form-field names must be scanned',
      );
    }
  });

  test('scans form-field values for urlencoded/multipart bodies', () {
    for (final type in [BodyType.urlencoded, BodyType.multipart]) {
      expect(
        collect(
          HttpRequestConfigEntity(
            id: 'c',
            bodyType: type,
            formFields: const [
              MultipartFieldEntity(name: 'key', value: '{{fval}}'),
            ],
          ),
        ),
        ['fval'],
        reason: '$type form-field values must be scanned',
      );
    }
  });

  test(
    'form-field vars dedupe with other sources, first-occurrence order',
    () {
      expect(
        collect(
          const HttpRequestConfigEntity(
            id: 'c',
            url: '{{shared}}/x',
            bodyType: BodyType.multipart,
            formFields: [
              MultipartFieldEntity(name: '{{shared}}', value: '{{fonly}}'),
            ],
          ),
        ),
        ['shared', 'fonly'],
      );
    },
  );

  test("a binary body's bodyFilePath is never scanned (not a formField)", () {
    expect(
      collect(
        const HttpRequestConfigEntity(
          id: 'c',
          bodyType: BodyType.binary,
          bodyFilePath: '{{path}}/file.bin',
        ),
      ),
      isEmpty,
      reason: 'binary bodyFilePath is never resolved, so never scanned',
    );
  });

  test('dedupes across sources, first-occurrence order', () {
    expect(
      collect(
        const HttpRequestConfigEntity(
          id: 'c',
          url: '{{base}}/{{tok}}',
          headers: {'Authorization': 'Bearer {{tok}}'},
          auth: {'token': '{{tok}}'},
        ),
      ),
      ['base', 'tok'],
    );
  });

  test('a clean config yields an empty list', () {
    expect(
      collect(
        const HttpRequestConfigEntity(id: 'c', url: 'https://plain.dev'),
      ),
      isEmpty,
    );
  });
}
