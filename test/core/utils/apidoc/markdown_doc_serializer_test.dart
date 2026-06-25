import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';
import 'package:getman/core/utils/apidoc/json_schema.dart';
import 'package:getman/core/utils/apidoc/markdown_doc_serializer.dart';

void main() {
  test('renders title, group heading, and an operation header', () {
    const doc = ApiDoc(
      title: 'Petstore',
      servers: [ApiServer(url: 'https://api.test.com')],
      operations: [
        ApiOperation(
          method: 'GET',
          path: '/users/{id}',
          summary: 'Get user',
          tag: 'Users',
          pathParams: [ApiParam(name: 'id', isRequired: true, example: '7')],
          security: AuthConfig(type: AuthType.bearer),
          requestBody: ApiBody(
            contentType: 'application/json',
            schema: JsonSchema(type: 'object'),
            example: {'q': 1},
          ),
          responses: [ApiResponse(statusCode: 200, description: 'OK')],
        ),
      ],
    );
    final md = MarkdownDocSerializer.toMarkdown(doc);
    expect(md, startsWith('# Petstore'));
    expect(md, contains('https://api.test.com'));
    expect(md, contains('## Users'));
    expect(md, contains('### GET /users/{id}'));
    expect(md, contains('| id | path | yes | 7 |'));
    expect(md, contains('**Auth:** Bearer'));
    expect(md, contains('```json'));
    expect(md, contains('`200` — OK'));
  });

  test('response body example renders as fenced json block', () {
    const doc = ApiDoc(
      title: 'API',
      operations: [
        ApiOperation(
          method: 'GET',
          path: '/items',
          summary: 'List items',
          responses: [
            ApiResponse(
              statusCode: 200,
              description: 'OK',
              body: ApiBody(
                contentType: 'application/json',
                example: {'id': 1},
              ),
            ),
          ],
        ),
      ],
    );
    final md = MarkdownDocSerializer.toMarkdown(doc);
    expect(md, contains('`200` — OK'));
    expect(md, contains('```json'));
    expect(md, contains('"id": 1'));
  });

  test('untagged operations fall under General', () {
    const doc = ApiDoc(
      title: 'API',
      operations: [
        ApiOperation(method: 'GET', path: '/ping', summary: 'Ping'),
      ],
    );
    expect(MarkdownDocSerializer.toMarkdown(doc), contains('## General'));
  });
}
