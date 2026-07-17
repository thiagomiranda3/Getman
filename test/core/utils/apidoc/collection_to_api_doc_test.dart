// test/core/utils/apidoc/collection_to_api_doc_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/apidoc/collection_to_api_doc.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

CollectionNodeEntity _leaf(String id, String name, String method, String url) =>
    CollectionNodeEntity(
      id: id,
      name: name,
      isFolder: false,
      config: HttpRequestConfigEntity(id: '$id-cfg', method: method, url: url),
    );

void main() {
  group('CollectionToApiDoc.build (structure)', () {
    test('root name becomes the title', () {
      const root = CollectionNodeEntity(id: 'r', name: 'Petstore');
      final doc = CollectionToApiDoc.build(root);
      expect(doc.title, 'Petstore');
      expect(doc.operations, isEmpty);
    });

    test('leaves become operations; folder name becomes the tag', () {
      final root = CollectionNodeEntity(
        id: 'r',
        name: 'API',
        children: [
          CollectionNodeEntity(
            id: 'f',
            name: 'Users',
            children: [_leaf('a', 'List', 'GET', 'https://api.test.com/users')],
          ),
        ],
      );
      final doc = CollectionToApiDoc.build(root);
      expect(doc.operations, hasLength(1));
      final op = doc.operations.single;
      expect(op.method, 'GET');
      expect(op.path, '/users');
      expect(op.tag, 'Users');
      expect(doc.servers.single.url, 'https://api.test.com');
    });

    test(
      'env-resolved base URL becomes the server; {{id}} becomes a path param',
      () {
        final env = EnvironmentEntity(
          name: 'prod',
          variables: const {'baseUrl': 'https://api.prod.com'},
        );
        final root = CollectionNodeEntity(
          id: 'r',
          name: 'API',
          children: [_leaf('a', 'Get', 'GET', '{{baseUrl}}/users/{{id}}?q=x')],
        );
        final doc = CollectionToApiDoc.build(root, env: env);
        final op = doc.operations.single;
        expect(doc.servers.single.url, 'https://api.prod.com');
        expect(op.path, '/users/{id}');
        expect(op.pathParams.map((p) => p.name), ['id']);
        expect(op.pathParams.single.isRequired, isTrue);
        expect(op.queryParams.single.name, 'q');
      },
    );

    test('unresolvable base URL falls back to "/" and warns', () {
      final root = CollectionNodeEntity(
        id: 'r',
        name: 'API',
        children: [_leaf('a', 'Get', 'GET', '{{baseUrl}}/ping')],
      );
      final doc = CollectionToApiDoc.build(root); // no env
      final op = doc.operations.single;
      expect(op.path, '/ping');
      expect(doc.servers.single.url, '{baseUrl}');
      expect(doc.servers.single.variables.containsKey('baseUrl'), isTrue);
    });

    test('a leaf root (not a folder) exports as its own single operation', () {
      final root = _leaf('a', 'Ping', 'GET', 'https://api.test.com/ping');
      final doc = CollectionToApiDoc.build(root);
      expect(
        doc.operations,
        hasLength(1),
        reason:
            'a request leaf used as the export root must not silently '
            'produce an empty document (root.children is empty for a leaf)',
      );
      final op = doc.operations.single;
      expect(op.method, 'GET');
      expect(op.path, '/ping');
      expect(op.summary, 'Ping');
      expect(doc.servers.single.url, 'https://api.test.com');
    });

    test(
      'bare path with no scheme and no var falls back to server "/" with warning',
      () {
        const root = CollectionNodeEntity(
          id: 'r',
          name: 'API',
          children: [
            CollectionNodeEntity(
              id: 'a',
              name: 'Orphan',
              isFolder: false,
              config: HttpRequestConfigEntity(
                id: 'c',
                url: 'orphan/path',
              ),
            ),
          ],
        );
        final doc = CollectionToApiDoc.build(root); // no env
        expect(doc.servers.single.url, '/');
        expect(doc.warnings, hasLength(1));
        expect(doc.warnings.single, contains('Could not determine'));
        expect(doc.operations.single.path, '/orphan/path');
      },
    );
  });
}
