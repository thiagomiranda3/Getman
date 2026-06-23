// test/core/utils/apidoc/collection_to_api_doc_body_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/apidoc/collection_to_api_doc.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

CollectionNodeEntity _rootWith(HttpRequestConfigEntity config) =>
    CollectionNodeEntity(
      id: 'r',
      name: 'API',
      children: [
        CollectionNodeEntity(
          id: 'a',
          name: 'Req',
          isFolder: false,
          config: config,
        ),
      ],
    );

void main() {
  test('raw JSON body infers schema + keeps example', () {
    final doc = CollectionToApiDoc.build(
      _rootWith(
        const HttpRequestConfigEntity(
          id: 'c',
          method: 'POST',
          url: 'https://api.test.com/users',
          body: '{"name":"ada","age":36}',
        ),
      ),
    );
    final body = doc.operations.single.requestBody!;
    expect(body.contentType, 'application/json');
    expect(body.schema!.type, 'object');
    expect(body.schema!.properties['name']!.type, 'string');
    expect(body.schema!.properties['age']!.type, 'integer');
    expect(body.example, {'name': 'ada', 'age': 36});
  });

  test('invalid raw JSON falls back to text/plain + warning', () {
    final doc = CollectionToApiDoc.build(
      _rootWith(
        const HttpRequestConfigEntity(
          id: 'c',
          method: 'POST',
          url: 'https://api.test.com/x',
          body: 'not json',
        ),
      ),
    );
    expect(doc.operations.single.requestBody!.contentType, 'text/plain');
    expect(doc.warnings.any((w) => w.contains('not valid JSON')), isTrue);
  });

  test('binary body → octet-stream string/binary schema', () {
    final doc = CollectionToApiDoc.build(
      _rootWith(
        const HttpRequestConfigEntity(
          id: 'c',
          method: 'PUT',
          url: 'https://api.test.com/blob',
          bodyType: BodyType.binary,
        ),
      ),
    );
    final body = doc.operations.single.requestBody!;
    expect(body.contentType, 'application/octet-stream');
    expect(body.schema!.format, 'binary');
  });

  test('multipart body → form-data object; file field is binary', () {
    final doc = CollectionToApiDoc.build(
      _rootWith(
        const HttpRequestConfigEntity(
          id: 'c',
          method: 'POST',
          url: 'https://api.test.com/upload',
          bodyType: BodyType.multipart,
          formFields: [
            MultipartFieldEntity(name: 'title', value: 'hi'),
            MultipartFieldEntity(
              name: 'file',
              isFile: true,
              filePath: '/x.png',
            ),
          ],
        ),
      ),
    );
    final body = doc.operations.single.requestBody!;
    expect(body.contentType, 'multipart/form-data');
    expect(body.schema!.properties['title']!.type, 'string');
    expect(body.schema!.properties['file']!.format, 'binary');
    expect(body.example, {'title': 'hi'});
  });

  test('graphql body → application/json {query,variables}', () {
    final doc = CollectionToApiDoc.build(
      _rootWith(
        const HttpRequestConfigEntity(
          id: 'c',
          method: 'POST',
          url: 'https://api.test.com/graphql',
          bodyType: BodyType.graphql,
          body: 'query { me }',
          graphqlVariables: '{"x":1}',
        ),
      ),
    );
    final body = doc.operations.single.requestBody!;
    expect(body.contentType, 'application/json');
    expect((body.example! as Map)['query'], 'query { me }');
    expect((body.example! as Map)['variables'], {'x': 1});
  });

  test('graphql null variables fall back to empty object', () {
    final doc = CollectionToApiDoc.build(
      _rootWith(
        const HttpRequestConfigEntity(
          id: 'c',
          method: 'POST',
          url: 'https://api.test.com/graphql',
          bodyType: BodyType.graphql,
          body: 'query { me }',
          graphqlVariables: 'null', // valid JSON null
        ),
      ),
    );
    expect(
      (doc.operations.single.requestBody!.example! as Map)['variables'],
      <String, dynamic>{},
    );
  });

  test('Content-Type and Accept are excluded from header params', () {
    final doc = CollectionToApiDoc.build(
      _rootWith(
        const HttpRequestConfigEntity(
          id: 'c',
          url: 'https://api.test.com/x',
          headers: {'Content-Type': 'application/json', 'X-Trace': 'abc'},
        ),
      ),
    );
    final names = doc.operations.single.headerParams
        .map((p) => p.name)
        .toList();
    expect(names, ['X-Trace']);
  });
}
