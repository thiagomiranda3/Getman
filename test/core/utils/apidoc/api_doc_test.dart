import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';
import 'package:getman/core/utils/apidoc/json_schema.dart';

// Builders return fresh (non-identical) instances so `==`/`hashCode` exercise
// the Equatable props path instead of short-circuiting on canonicalized
// consts.
ApiServer buildServer({String url = 'https://api.dev'}) =>
    ApiServer(url: url, variables: const {'region': 'eu'});

ApiParam buildParam({String name = 'id'}) => ApiParam(
  name: name,
  example: '7',
  isRequired: true,
  schema: const JsonSchema(type: 'integer'),
);

ApiBody buildBody({String contentType = 'application/json'}) => ApiBody(
  contentType: contentType,
  schema: const JsonSchema(type: 'object'),
  example: const {'id': 7},
);

ApiResponse buildResponse({int statusCode = 200}) =>
    ApiResponse(statusCode: statusCode, description: 'OK', body: buildBody());

ApiOperation buildOperation({String method = 'GET'}) => ApiOperation(
  method: method,
  path: '/users/{id}',
  summary: 'Get user',
  description: 'Returns one user.',
  tag: 'Users',
  queryParams: [buildParam(name: 'verbose')],
  headerParams: [buildParam(name: 'X-Trace')],
  pathParams: [buildParam()],
  requestBody: buildBody(),
  responses: [buildResponse()],
  security: const AuthConfig(type: AuthType.bearer),
);

ApiDoc buildDoc({String title = 'My API'}) => ApiDoc(
  title: title,
  version: '2.0.0',
  servers: [buildServer()],
  operations: [buildOperation()],
  warnings: const ['w'],
);

void main() {
  test('ApiDoc defaults: version 1.0.0, empty collections', () {
    const doc = ApiDoc(title: 'My API');
    expect(doc.version, '1.0.0');
    expect(doc.servers, isEmpty);
    expect(doc.operations, isEmpty);
    expect(doc.warnings, isEmpty);
  });

  test('ApiOperation defaults security to AuthConfig.none', () {
    const op = ApiOperation(method: 'GET', path: '/u', summary: 'List');
    expect(op.security, AuthConfig.none);
    expect(op.responses, isEmpty);
  });

  test('ApiServer value-equality with variables', () {
    expect(
      const ApiServer(url: 'a', variables: {'k': 'v'}),
      equals(const ApiServer(url: 'a', variables: {'k': 'v'})),
    );
  });

  test('value objects compare by value (Equatable)', () {
    const a = ApiParam(name: 'id', isRequired: true);
    const b = ApiParam(name: 'id', isRequired: true);
    expect(a, equals(b));
    const body1 = ApiBody(
      contentType: 'application/json',
      schema: JsonSchema(type: 'object'),
    );
    const body2 = ApiBody(
      contentType: 'application/json',
      schema: JsonSchema(type: 'object'),
    );
    expect(body1, equals(body2));
  });

  group('value equality on fresh instances (props, not identity)', () {
    test('ApiDoc', () {
      expect(buildDoc(), buildDoc());
      expect(buildDoc().hashCode, buildDoc().hashCode);
      expect(buildDoc(), isNot(equals(buildDoc(title: 'Other'))));
    });

    test('ApiServer', () {
      expect(buildServer(), buildServer());
      expect(buildServer().hashCode, buildServer().hashCode);
      expect(buildServer(), isNot(equals(buildServer(url: 'https://b.dev'))));
    });

    test('ApiParam', () {
      expect(buildParam(), buildParam());
      expect(buildParam().hashCode, buildParam().hashCode);
      expect(buildParam(), isNot(equals(buildParam(name: 'other'))));
    });

    test('ApiBody', () {
      expect(buildBody(), buildBody());
      expect(buildBody().hashCode, buildBody().hashCode);
      expect(buildBody(), isNot(equals(buildBody(contentType: 'text/csv'))));
    });

    test('ApiResponse', () {
      expect(buildResponse(), buildResponse());
      expect(buildResponse().hashCode, buildResponse().hashCode);
      expect(buildResponse(), isNot(equals(buildResponse(statusCode: 404))));
    });

    test('ApiOperation with all optional fields populated', () {
      expect(buildOperation(), buildOperation());
      expect(buildOperation().hashCode, buildOperation().hashCode);
      expect(buildOperation(), isNot(equals(buildOperation(method: 'PUT'))));
    });
  });
}
