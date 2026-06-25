import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';
import 'package:getman/core/utils/apidoc/json_schema.dart';

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
}
