import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/workspace/workspace_collection_serializer.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';

void main() {
  group('request node', () {
    const leaf = CollectionNodeEntity(
      id: 'node-1',
      name: 'Get User',
      isFolder: false,
      isFavorite: true,
      config: HttpRequestConfigEntity(
        id: 'cfg-1',
        method: 'POST',
        url: 'https://api.dev/users?id=1',
        headers: {'Content-Type': 'application/json'},
        body: '{"a":1}',
        bodyType: BodyType.multipart,
        auth: {'type': 'bearer', 'token': '{{tok}}'},
        formFields: [MultipartFieldEntity(name: 'f', value: 'v')],
        // Response cache fields that must NOT be written to disk:
        responseBody: 'SECRET',
        statusCode: 200,
        durationMs: 42,
      ),
    );

    test('omits response cache fields', () {
      final json = WorkspaceCollectionSerializer.requestToJson(leaf);
      final request = json['request'] as Map<String, dynamic>;
      expect(request.containsKey('responseBody'), isFalse);
      expect(request.containsKey('statusCode'), isFalse);
      expect(request.containsKey('durationMs'), isFalse);
      expect(json.toString(), isNot(contains('SECRET')));
    });

    test('round-trips node + config fields (response reads back null)', () {
      final json = WorkspaceCollectionSerializer.requestToJson(leaf);
      final back = WorkspaceCollectionSerializer.requestFromJson(json);

      expect(back.id, 'node-1');
      expect(back.name, 'Get User');
      expect(back.isFolder, isFalse);
      expect(back.isFavorite, isTrue);
      final c = back.config!;
      expect(c.id, 'cfg-1');
      expect(c.method, 'POST');
      expect(c.url, 'https://api.dev/users?id=1');
      expect(c.headers, {'Content-Type': 'application/json'});
      expect(c.body, '{"a":1}');
      expect(c.bodyType, BodyType.multipart);
      expect(c.auth, {'type': 'bearer', 'token': '{{tok}}'});
      expect(c.formFields, [const MultipartFieldEntity(name: 'f', value: 'v')]);
      // Dropped on disk → null after reload.
      expect(c.responseBody, isNull);
      expect(c.statusCode, isNull);
    });

    test('omits saved examples (local-only, not git-tracked)', () {
      final withExamples = leaf.copyWith(
        examples: [
          SavedExampleEntity(
            id: 'e1',
            name: '200 OK',
            capturedAt: DateTime.utc(2026, 6, 14),
            config: const HttpRequestConfigEntity(
              id: 'cfg-1',
              responseBody: 'SECRET-EXAMPLE',
            ),
          ),
        ],
      );
      final json = WorkspaceCollectionSerializer.requestToJson(withExamples);
      expect(json.containsKey('examples'), isFalse);
      expect(json.toString(), isNot(contains('SECRET-EXAMPLE')));

      final back = WorkspaceCollectionSerializer.requestFromJson(json);
      expect(back.examples, isEmpty);
    });
  });

  group('folder + manifest', () {
    test('folder round-trips with childOrder', () {
      const folder = CollectionNodeEntity(
        id: 'f1',
        name: 'Auth',
        isFavorite: true,
      );
      final json = WorkspaceCollectionSerializer.folderToJson(folder, [
        'a',
        'b',
      ]);
      expect(WorkspaceCollectionSerializer.childOrder(json), ['a', 'b']);

      final back = WorkspaceCollectionSerializer.folderFromJson(json, const []);
      expect(back.id, 'f1');
      expect(back.name, 'Auth');
      expect(back.isFolder, isTrue);
      expect(back.isFavorite, isTrue);
    });

    test('manifest round-trips rootOrder', () {
      final json = WorkspaceCollectionSerializer.manifestToJson(['x', 'y']);
      expect(json['version'], WorkspaceCollectionSerializer.version);
      expect(WorkspaceCollectionSerializer.rootOrder(json), ['x', 'y']);
    });
  });

  group('folder variables', () {
    test('round-trips variables; masks secret values', () {
      const folder = CollectionNodeEntity(
        id: 'f1',
        name: 'API',
        variables: {'base': 'https://api.example.com', 'token': 'sk-secret'},
        secretKeys: {'token'},
      );

      final json = WorkspaceCollectionSerializer.folderToJson(folder, const []);
      final restored = WorkspaceCollectionSerializer.folderFromJson(
        json,
        const [],
      );

      expect(restored.variables['base'], 'https://api.example.com');
      expect(restored.variables['token'], ''); // secret masked
      expect(restored.secretKeys, contains('token'));
    });
  });
}
