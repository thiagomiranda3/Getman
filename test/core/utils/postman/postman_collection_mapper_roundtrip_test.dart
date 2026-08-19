// Round-trip (export → import) coverage for PostmanCollectionMapper —
// collection variables, request details/auth/descriptions/bodies/RequestKind
// and the graphql body — split out of postman_collection_mapper_test.dart to
// keep that file's main() under the function_lines_of_code metric gate.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/utils/postman/postman_collection_mapper.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

void main() {
  group('collection variables', () {
    test('round-trips folder + nested variables, masking secrets', () {
      const inner = CollectionNodeEntity(
        id: 'f2',
        name: 'inner',
        variables: {'token': 'sk-secret', 'page': '2'},
        secretKeys: {'token'},
      );
      const root = CollectionNodeEntity(
        id: 'f1',
        name: 'API',
        variables: {'base': 'https://api.example.com'},
        children: [inner],
      );

      final json = PostmanCollectionMapper.toJson(root);
      expect(json, contains('"variable"'));

      final restored = PostmanCollectionMapper.fromJson(json);

      // Root collection vars land on the imported root folder.
      expect(restored.variables['base'], 'https://api.example.com');

      final restoredInner = restored.children.firstWhere(
        (c) => c.name == 'inner',
      );
      expect(restoredInner.variables['page'], '2');
      // secret value is masked on export -> empty on import, key still secret.
      expect(restoredInner.variables['token'], '');
      expect(restoredInner.secretKeys, contains('token'));
    });
  });

  group('round-trip', () {
    test('export then import preserves names and request details', () {
      const originalLeaf = CollectionNodeEntity(
        id: 'leaf',
        name: 'Create Thing',
        isFolder: false,
        config: HttpRequestConfigEntity(
          id: 'cfg',
          method: 'POST',
          url: 'https://api.example.com/things?dry=true',
          headers: {'Content-Type': 'application/json', 'X-Key': 'k'},
          body: '{"a":1}',
        ),
      );
      const original = CollectionNodeEntity(
        id: 'root',
        name: 'My API',
        children: [
          CollectionNodeEntity(
            id: 'folder',
            name: 'Things',
            children: [originalLeaf],
          ),
        ],
      );

      final exported = PostmanCollectionMapper.toJson(original);
      final reimported = PostmanCollectionMapper.fromJson(exported);

      expect(reimported.name, 'My API');
      expect(reimported.isFolder, isTrue);
      expect(reimported.children, hasLength(1));
      final folder = reimported.children.first;
      expect(folder.name, 'Things');
      expect(folder.isFolder, isTrue);
      expect(folder.children, hasLength(1));
      final leaf = folder.children.first;
      expect(leaf.name, 'Create Thing');
      expect(leaf.config!.method, 'POST');
      expect(leaf.config!.url, 'https://api.example.com/things?dry=true');
      expect(leaf.config!.headers['Content-Type'], 'application/json');
      expect(leaf.config!.headers['X-Key'], 'k');
      expect(
        leaf.config!.params,
        [const QueryParamEntity(key: 'dry', value: 'true')],
      );
      expect(leaf.config!.body, '{"a":1}');
    });

    test('export then import preserves auth (bearer / basic / api-key)', () {
      CollectionNodeEntity leafWith(Map<String, String> auth) =>
          CollectionNodeEntity(
            id: 'leaf',
            name: 'R',
            isFolder: false,
            config: HttpRequestConfigEntity(
              id: 'cfg',
              url: 'https://api.dev/x',
              auth: auth,
            ),
          );

      HttpRequestConfigEntity roundTrip(Map<String, String> auth) =>
          PostmanCollectionMapper.fromJson(
            PostmanCollectionMapper.toJson(leafWith(auth)),
          ).children.single.config!;

      expect(
        roundTrip(const {'type': 'bearer', 'token': 'tok-1'}).auth,
        {'type': 'bearer', 'token': 'tok-1'},
        reason:
            'auth silently dropped means the request sends '
            'unauthenticated after a Postman round trip',
      );
      expect(
        roundTrip(const {
          'type': 'basic',
          'username': 'u',
          'password': 'p',
        }).auth,
        {'type': 'basic', 'username': 'u', 'password': 'p'},
      );
      expect(
        roundTrip(const {
          'type': 'apikey',
          'key': 'X-Api-Key',
          'value': 'v1',
          'addTo': 'query',
        }).auth,
        {'type': 'apikey', 'key': 'X-Api-Key', 'value': 'v1', 'addTo': 'query'},
      );
    });

    test('export then import preserves folder and request descriptions', () {
      const original = CollectionNodeEntity(
        id: 'root',
        name: 'My API',
        children: [
          CollectionNodeEntity(
            id: 'folder',
            name: 'Things',
            description: 'All the things.',
            children: [
              CollectionNodeEntity(
                id: 'leaf',
                name: 'Get Thing',
                isFolder: false,
                description: 'Fetches one thing by id.',
                config: HttpRequestConfigEntity(id: 'cfg'),
              ),
            ],
          ),
        ],
      );
      final reimported = PostmanCollectionMapper.fromJson(
        PostmanCollectionMapper.toJson(original),
      );
      final folder = reimported.children.single;
      expect(folder.description, 'All the things.');
      expect(folder.children.single.description, 'Fetches one thing by id.');
    });

    test(
      'export then import preserves a double-percent-encoded query value '
      '(no query-value double-decode round trip)',
      () {
        const leaf = CollectionNodeEntity(
          id: 'leaf',
          name: 'Search',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'cfg',
            url: 'https://api.com/x?v=%2520',
          ),
        );
        final reimported = PostmanCollectionMapper.fromJson(
          PostmanCollectionMapper.toJson(leaf),
        );
        expect(
          reimported.children.first.config!.url,
          'https://api.com/x?v=%2520',
          reason:
              'export must carry the raw (still-encoded) query value so '
              "the importer's single decode step restores the original "
              'instead of decoding it twice into a literal space',
        );
      },
    );

    test('export then import preserves the root collection description', () {
      const original = CollectionNodeEntity(
        id: 'root',
        name: 'My API',
        description: 'Top-level notes.',
      );
      final reimported = PostmanCollectionMapper.fromJson(
        PostmanCollectionMapper.toJson(original),
      );
      expect(reimported.description, 'Top-level notes.');
    });

    test('import decodes percent-encoded structured query values', () {
      // Real Postman exports carry `url.query` values exactly as they appear
      // in url.raw — still percent-encoded.
      const postmanJson = '''
      {
        "info": {"name": "C", "schema":
          "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
        "item": [
          {"name": "Search", "request": {
            "method": "GET",
            "header": [],
            "url": {
              "raw": "https://api.com/x?q=hello%20world",
              "query": [{"key": "q", "value": "hello%20world"}]
            }
          }}
        ]
      }''';
      final imported = PostmanCollectionMapper.fromJson(postmanJson);
      final url = imported.children.single.config!.url;
      expect(
        url,
        'https://api.com/x?q=hello%20world',
        reason: 'the value must not be double-encoded to hello%2520world',
      );
    });

    test('export then import preserves a urlencoded form body', () {
      const leaf = CollectionNodeEntity(
        id: 'leaf',
        name: 'Login',
        isFolder: false,
        config: HttpRequestConfigEntity(
          id: 'cfg',
          method: 'POST',
          url: 'https://api.example.com/login',
          bodyType: BodyType.urlencoded,
          formFields: [
            MultipartFieldEntity(name: 'user', value: 'alice'),
            MultipartFieldEntity(name: 'pass', value: 'secret'),
          ],
        ),
      );

      final reimported = PostmanCollectionMapper.fromJson(
        PostmanCollectionMapper.toJson(leaf),
      );
      final config = reimported.children.first.config!;

      expect(config.bodyType, BodyType.urlencoded);
      expect(config.formFields, const [
        MultipartFieldEntity(name: 'user', value: 'alice'),
        MultipartFieldEntity(name: 'pass', value: 'secret'),
      ]);
    });

    test(
      'export then import preserves a multipart form body (text + file)',
      () {
        const leaf = CollectionNodeEntity(
          id: 'leaf',
          name: 'Upload',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'cfg',
            method: 'POST',
            url: 'https://api.example.com/upload',
            bodyType: BodyType.multipart,
            formFields: [
              MultipartFieldEntity(name: 'caption', value: 'hi'),
              MultipartFieldEntity(
                name: 'file',
                isFile: true,
                filePath: '/tmp/a.png',
              ),
            ],
          ),
        );

        final reimported = PostmanCollectionMapper.fromJson(
          PostmanCollectionMapper.toJson(leaf),
        );
        final config = reimported.children.first.config!;

        expect(config.bodyType, BodyType.multipart);
        expect(config.formFields, const [
          MultipartFieldEntity(name: 'caption', value: 'hi'),
          MultipartFieldEntity(
            name: 'file',
            isFile: true,
            filePath: '/tmp/a.png',
          ),
        ]);
      },
    );

    test('round-trips RequestKind via the _getman_kind vendor key (F4)', () {
      const leaf = CollectionNodeEntity(
        id: 'leaf',
        name: 'Socket',
        isFolder: false,
        config: HttpRequestConfigEntity(
          id: 'cfg',
          url: 'wss://x.y/socket',
          kind: RequestKind.webSocket,
        ),
      );
      final exported = PostmanCollectionMapper.toJson(leaf);
      final decoded = jsonDecode(exported) as Map<String, dynamic>;
      final item = (decoded['item'] as List).first as Map<String, dynamic>;
      final request = item['request'] as Map<String, dynamic>;
      expect(request['_getman_kind'], 'webSocket');

      final back = PostmanCollectionMapper.fromJson(
        exported,
      ).children.single.config!;
      expect(
        back.kind,
        RequestKind.webSocket,
        reason:
            'a WS request must not silently come back as HTTP after an '
            'export + import round trip',
      );
    });

    test(
      'http requests emit no _getman_kind; unknown values read as http (F4)',
      () {
        const leaf = CollectionNodeEntity(
          id: 'leaf',
          name: 'Plain',
          isFolder: false,
          config: HttpRequestConfigEntity(id: 'cfg', url: 'https://x.y'),
        );
        final decoded =
            jsonDecode(PostmanCollectionMapper.toJson(leaf))
                as Map<String, dynamic>;
        final item = (decoded['item'] as List).first as Map<String, dynamic>;
        final request = item['request'] as Map<String, dynamic>;
        expect(
          request.containsKey('_getman_kind'),
          isFalse,
          reason: 'the vendor key stays inert for plain HTTP exports',
        );

        final source = jsonEncode({
          'info': {
            'name': 'S',
            'schema':
                'https://schema.getpostman.com/json/collection/v2.1.0/'
                'collection.json',
          },
          'item': [
            {
              'name': 'A',
              'request': {
                'method': 'GET',
                'url': 'https://x.y',
                '_getman_kind': 'quantum',
              },
            },
            {
              'name': 'B',
              'request': {
                'method': 'GET',
                'url': 'https://x.y',
                '_getman_kind': 'MCP',
              },
            },
          ],
        });
        final node = PostmanCollectionMapper.fromJson(source);
        expect(node.children[0].config!.kind, RequestKind.http);
        expect(
          node.children[1].config!.kind,
          RequestKind.mcp,
          reason: 'kind parsing is case-lenient',
        );
      },
    );

    test('round-trips multipart contentType both ways (F5)', () {
      const leaf = CollectionNodeEntity(
        id: 'leaf',
        name: 'Upload',
        isFolder: false,
        config: HttpRequestConfigEntity(
          id: 'cfg',
          method: 'POST',
          url: 'https://api.example.com/upload',
          bodyType: BodyType.multipart,
          formFields: [
            MultipartFieldEntity(
              name: 'meta',
              value: '{"a":1}',
              contentType: 'application/json',
            ),
            MultipartFieldEntity(
              name: 'file',
              isFile: true,
              filePath: '/tmp/a.bin',
              contentType: 'application/octet-stream',
            ),
            MultipartFieldEntity(name: 'plain', value: 'x'),
          ],
        ),
      );

      final exported = PostmanCollectionMapper.toJson(leaf);
      final decoded = jsonDecode(exported) as Map<String, dynamic>;
      final item = (decoded['item'] as List).first as Map<String, dynamic>;
      final request = item['request'] as Map<String, dynamic>;
      final formdata =
          ((request['body'] as Map<String, dynamic>)['formdata'] as List)
              .cast<Map<String, dynamic>>();
      expect(
        formdata.firstWhere((f) => f['key'] == 'meta')['contentType'],
        'application/json',
      );
      expect(
        formdata.firstWhere((f) => f['key'] == 'file')['contentType'],
        'application/octet-stream',
      );
      expect(
        formdata
            .firstWhere((f) => f['key'] == 'plain')
            .containsKey('contentType'),
        isFalse,
        reason: 'rows without a contentType must not emit the key',
      );

      final back = PostmanCollectionMapper.fromJson(
        exported,
      ).children.single.config!;
      expect(back.formFields, const [
        MultipartFieldEntity(
          name: 'meta',
          value: '{"a":1}',
          contentType: 'application/json',
        ),
        MultipartFieldEntity(
          name: 'file',
          isFile: true,
          filePath: '/tmp/a.bin',
          contentType: 'application/octet-stream',
        ),
        MultipartFieldEntity(name: 'plain', value: 'x'),
      ]);
    });
  });

  group('graphql body round-trip', () {
    test('export -> import preserves query + variables + body type', () {
      const leaf = CollectionNodeEntity(
        id: 'leaf',
        name: 'GQL',
        isFolder: false,
        config: HttpRequestConfigEntity(
          id: 'cfg',
          method: 'POST',
          url: 'https://api.example.com/graphql',
          bodyType: BodyType.graphql,
          body: 'query { me { id } }',
          graphqlVariables: '{"limit":5}',
        ),
      );
      const root = CollectionNodeEntity(
        id: 'root',
        name: 'Coll',
        children: [leaf],
      );

      final imported = PostmanCollectionMapper.fromJson(
        PostmanCollectionMapper.toJson(root),
      );
      final reLeaf = imported.children.single;
      expect(reLeaf.isFolder, isFalse);
      expect(reLeaf.config!.bodyType, BodyType.graphql);
      expect(reLeaf.config!.body, 'query { me { id } }');
      expect(reLeaf.config!.graphqlVariables, '{"limit":5}');
    });
  });
}
