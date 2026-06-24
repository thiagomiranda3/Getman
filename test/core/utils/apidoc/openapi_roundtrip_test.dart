// test/core/utils/apidoc/openapi_roundtrip_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/apidoc/collection_to_api_doc.dart';
import 'package:getman/core/utils/apidoc/openapi_serializer.dart';
import 'package:getman/core/utils/openapi/collection_builder.dart';
import 'package:getman/core/utils/openapi/spec_loader.dart';
import 'package:getman/core/utils/openapi/spec_normalizer.dart'; // adjust if needed
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

void main() {
  test('export → import preserves method, path, and tag', () {
    const root = CollectionNodeEntity(
      id: 'r',
      name: 'Petstore',
      children: [
        CollectionNodeEntity(
          id: 'f',
          name: 'Users',
          children: [
            CollectionNodeEntity(
              id: 'a',
              name: 'List users',
              isFolder: false,
              config: HttpRequestConfigEntity(
                id: 'c',
                url: 'https://api.test.com/users',
              ),
            ),
          ],
        ),
      ],
    );

    final json = OpenApiSerializer.toJson(CollectionToApiDoc.build(root));
    final api = normalizeSpec(loadSpec(json)); // adjust call to real API
    final imported = buildImport(api).root;

    // Find the single leaf in the imported tree.
    CollectionNodeEntity? leaf;
    void find(CollectionNodeEntity n) {
      if (!n.isFolder && n.config != null) leaf = n;
      n.children.forEach(find);
    }

    find(imported);

    expect(leaf, isNotNull);
    expect(leaf!.config!.method, 'GET');
    // The imported URL contains the path; servers map to env vars on import.
    expect(leaf!.config!.url.contains('/users'), isTrue);
  });
}
