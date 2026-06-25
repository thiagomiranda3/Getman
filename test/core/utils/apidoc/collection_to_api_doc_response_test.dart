// test/core/utils/apidoc/collection_to_api_doc_response_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/apidoc/collection_to_api_doc.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';

void main() {
  test('no examples and no live response → default 200', () {
    const root = CollectionNodeEntity(
      id: 'r',
      name: 'API',
      children: [
        CollectionNodeEntity(
          id: 'a',
          name: 'Get',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'c',
            url: 'https://api.test.com/x',
          ),
        ),
      ],
    );
    final responses = CollectionToApiDoc.build(
      root,
    ).operations.single.responses;
    expect(responses.single.statusCode, 200);
    expect(responses.single.description, 'Successful response');
  });

  test('saved examples become per-status responses with inferred schema', () {
    final root = CollectionNodeEntity(
      id: 'r',
      name: 'API',
      children: [
        CollectionNodeEntity(
          id: 'a',
          name: 'Get',
          isFolder: false,
          config: const HttpRequestConfigEntity(
            id: 'c',
            url: 'https://api.test.com/x',
          ),
          examples: [
            SavedExampleEntity(
              id: 'e1',
              name: 'ok',
              capturedAt: DateTime(2026),
              config: const HttpRequestConfigEntity(
                id: 'ec',
                url: 'https://api.test.com/x',
                statusCode: 200,
                responseBody: '{"ok":true}',
              ),
            ),
          ],
        ),
      ],
    );
    final responses = CollectionToApiDoc.build(
      root,
    ).operations.single.responses;
    expect(responses.single.statusCode, 200);
    expect(responses.single.body!.contentType, 'application/json');
    expect(responses.single.body!.schema!.properties['ok']!.type, 'boolean');
  });

  test('live response is added when not already covered by examples', () {
    const root = CollectionNodeEntity(
      id: 'r',
      name: 'API',
      children: [
        CollectionNodeEntity(
          id: 'a',
          name: 'Get',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'c',
            url: 'https://api.test.com/x',
            statusCode: 404,
            responseBody: 'nope',
          ),
        ),
      ],
    );
    final responses = CollectionToApiDoc.build(
      root,
    ).operations.single.responses;
    expect(responses.map((r) => r.statusCode), contains(404));
  });

  test('inherit auth is mapped to none on the operation', () {
    final root = CollectionNodeEntity(
      id: 'r',
      name: 'API',
      children: [
        CollectionNodeEntity(
          id: 'a',
          name: 'Get',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'c',
            url: 'https://api.test.com/x',
            auth: const AuthConfig(type: AuthType.inherit).toMap(),
          ),
        ),
      ],
    );
    final op = CollectionToApiDoc.build(root).operations.single;
    expect(op.security.type, AuthType.none);
  });

  test('example at same status as live response suppresses the live one', () {
    final root = CollectionNodeEntity(
      id: 'r',
      name: 'API',
      children: [
        CollectionNodeEntity(
          id: 'a',
          name: 'Get',
          isFolder: false,
          config: const HttpRequestConfigEntity(
            id: 'c',
            url: 'https://api.test.com/x',
            statusCode: 200,
            responseBody: '{"live":true}',
          ),
          examples: [
            SavedExampleEntity(
              id: 'e1',
              name: 'myExample',
              capturedAt: DateTime(2026),
              config: const HttpRequestConfigEntity(
                id: 'ec',
                url: 'https://api.test.com/x',
                statusCode: 200,
                responseBody: '{"example":true}',
              ),
            ),
          ],
        ),
      ],
    );
    final responses = CollectionToApiDoc.build(
      root,
    ).operations.single.responses;
    expect(responses.where((r) => r.statusCode == 200).length, 1);
    expect(
      responses.single.description,
      'Example: myExample',
    );
  });

  test(
    'non-JSON live response body falls back to text/plain content type',
    () {
      const root = CollectionNodeEntity(
        id: 'r',
        name: 'API',
        children: [
          CollectionNodeEntity(
            id: 'a',
            name: 'Get',
            isFolder: false,
            config: HttpRequestConfigEntity(
              id: 'c',
              url: 'https://api.test.com/x',
              statusCode: 200,
              responseBody: 'not json at all',
            ),
          ),
        ],
      );
      final response = CollectionToApiDoc.build(
        root,
      ).operations.single.responses.single;
      expect(response.body!.contentType, 'text/plain');
      expect(response.body!.example, 'not json at all');
    },
  );

  test('bearer auth is carried on the operation', () {
    final root = CollectionNodeEntity(
      id: 'r',
      name: 'API',
      children: [
        CollectionNodeEntity(
          id: 'a',
          name: 'Get',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'c',
            url: 'https://api.test.com/x',
            auth: const AuthConfig(
              type: AuthType.bearer,
              token: 'secret',
            ).toMap(),
          ),
        ),
      ],
    );
    final op = CollectionToApiDoc.build(root).operations.single;
    expect(op.security.type, AuthType.bearer);
  });
}
