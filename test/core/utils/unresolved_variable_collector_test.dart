// Unit tests for UnresolvedVariableCollector: every scanned source (URL,
// header keys+values, parked disabled params, raw/graphql bodies + graphql
// variables, auth values), body-type gating, resolved/dynamic exclusion,
// and cross-source dedup with first-occurrence order.

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
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

  test('scans parked disabled params (key + value)', () {
    expect(
      collect(
        const HttpRequestConfigEntity(
          id: 'c',
          disabledParams: [
            ParkedParamEntity(key: '{{pk}}', value: '{{pv}}', rowIndex: 0),
          ],
        ),
      ),
      ['pk', 'pv'],
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
