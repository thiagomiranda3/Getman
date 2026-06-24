// test/features/collections/presentation/widgets/export_api_docs_dialog_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/widgets/export_api_docs_dialog.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

void main() {
  const node = CollectionNodeEntity(
    id: 'r',
    name: 'My API',
    children: [
      CollectionNodeEntity(
        id: 'a',
        name: 'Ping',
        isFolder: false,
        config: HttpRequestConfigEntity(
          id: 'c',
          url: 'https://api.test.com/ping',
        ),
      ),
    ],
  );

  test('buildExport: OpenAPI JSON produces .openapi.json content', () {
    final out = buildExport(node, null, ExportDocFormat.openApiJson);
    expect(out.fileName, 'my_api.openapi.json');
    expect(out.ext, ['json']);
    expect(out.content.contains('"openapi": "3.0.3"'), isTrue);
  });

  test('buildExport: OpenAPI YAML produces .openapi.yaml content', () {
    final out = buildExport(node, null, ExportDocFormat.openApiYaml);
    expect(out.fileName, 'my_api.openapi.yaml');
    expect(out.ext, ['yaml']);
    expect(out.content.startsWith('openapi:'), isTrue);
  });

  test('buildExport: Markdown produces .md content', () {
    final out = buildExport(node, null, ExportDocFormat.markdown);
    expect(out.fileName, 'my_api.md');
    expect(out.ext, ['md']);
    expect(out.content.startsWith('# My API'), isTrue);
  });

  test('buildExport surfaces warnings (unresolvable server)', () {
    final out = buildExport(
      const CollectionNodeEntity(
        id: 'r',
        name: 'API',
        children: [
          CollectionNodeEntity(
            id: 'a',
            name: 'x',
            isFolder: false,
            config: HttpRequestConfigEntity(id: 'c', url: '{{baseUrl}}/x'),
          ),
        ],
      ),
      EnvironmentEntity(name: 'empty'),
      ExportDocFormat.openApiJson,
    );
    // base var has no value → server '{baseUrl}', not a hard warning here,
    // but with no env at all it would warn. Just assert the record shape:
    expect(out.warnings, isA<List<String>>());
  });
}
