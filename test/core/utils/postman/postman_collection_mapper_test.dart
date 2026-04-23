import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/postman/postman_collection_mapper.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

void main() {
  group('PostmanCollectionMapper.toJson', () {
    test('emits v2.1 schema and collection name', () {
      const root = CollectionNodeEntity(id: 'root', name: 'My API', children: []);
      final decoded = jsonDecode(PostmanCollectionMapper.toJson(root)) as Map<String, dynamic>;
      expect(decoded['info']['name'], 'My API');
      expect(decoded['info']['schema'], contains('v2.1'));
      expect(decoded['item'], isEmpty);
    });

    test('maps folders and request leaves', () {
      const child = CollectionNodeEntity(
        id: 'leaf',
        name: 'Get Users',
        isFolder: false,
        config: HttpRequestConfigEntity(
          id: 'cfg',
          method: 'GET',
          url: 'https://api.example.com/users?page=1',
          headers: {'X-Token': 'abc', 'Accept': 'application/json'},
          body: '',
        ),
      );
      const root = CollectionNodeEntity(
        id: 'root',
        name: 'API',
        children: [child],
      );
      final decoded = jsonDecode(PostmanCollectionMapper.toJson(root)) as Map<String, dynamic>;
      final items = decoded['item'] as List;
      expect(items, hasLength(1));
      final item = items.first as Map<String, dynamic>;
      expect(item['name'], 'Get Users');
      final request = item['request'] as Map<String, dynamic>;
      expect(request['method'], 'GET');
      expect(request['url']['raw'], 'https://api.example.com/users?page=1');
      final query = request['url']['query'] as List;
      expect(query.first, {'key': 'page', 'value': '1'});
      final headers = request['header'] as List;
      expect(headers.any((h) => h['key'] == 'X-Token' && h['value'] == 'abc'), isTrue);
    });

    test('preserves duplicate query keys on export', () {
      const leaf = CollectionNodeEntity(
        id: 'leaf',
        name: 'Dup',
        isFolder: false,
        config: HttpRequestConfigEntity(
          id: 'cfg',
          url: 'https://x.y?a=1&a=2',
        ),
      );
      final decoded = jsonDecode(PostmanCollectionMapper.toJson(leaf)) as Map<String, dynamic>;
      final item = (decoded['item'] as List).first as Map<String, dynamic>;
      final query = item['request']['url']['query'] as List;
      expect(query, [
        {'key': 'a', 'value': '1'},
        {'key': 'a', 'value': '2'},
      ]);
    });

    test('emits raw body with json language hint when Content-Type is json', () {
      final config = const HttpRequestConfigEntity(
        id: 'cfg',
        method: 'POST',
        url: 'https://api.example.com/users',
        headers: {'Content-Type': 'application/json'},
        body: '{"name":"x"}',
      );
      final leaf = CollectionNodeEntity(
        id: 'leaf',
        name: 'Create',
        isFolder: false,
        config: config,
      );
      final decoded = jsonDecode(PostmanCollectionMapper.toJson(leaf)) as Map<String, dynamic>;
      final item = (decoded['item'] as List).first as Map<String, dynamic>;
      final body = item['request']['body'] as Map<String, dynamic>;
      expect(body['mode'], 'raw');
      expect(body['raw'], '{"name":"x"}');
      expect(body['options']['raw']['language'], 'json');
    });

    test('wraps a single request leaf as an item', () {
      const leaf = CollectionNodeEntity(
        id: 'leaf',
        name: 'Ping',
        isFolder: false,
        config: HttpRequestConfigEntity(id: 'cfg', url: 'https://example.com'),
      );
      final decoded = jsonDecode(PostmanCollectionMapper.toJson(leaf)) as Map<String, dynamic>;
      final items = decoded['item'] as List;
      expect(items, hasLength(1));
      expect((items.first as Map)['name'], 'Ping');
    });
  });

  group('PostmanCollectionMapper.fromJson', () {
    test('parses a basic v2.1 collection', () {
      const source = '''
{
  "info": {
    "name": "Sample",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "Folder A",
      "item": [
        {
          "name": "GET Root",
          "request": {
            "method": "GET",
            "header": [
              {"key": "X-Test", "value": "y"}
            ],
            "url": {
              "raw": "https://example.com/a?x=1",
              "query": [{"key": "x", "value": "1"}]
            }
          }
        }
      ]
    }
  ]
}
''';
      final node = PostmanCollectionMapper.fromJson(source);
      expect(node.isFolder, isTrue);
      expect(node.name, 'Sample');
      expect(node.children, hasLength(1));
      final folderA = node.children.first;
      expect(folderA.name, 'Folder A');
      expect(folderA.isFolder, isTrue);
      expect(folderA.children, hasLength(1));
      final leaf = folderA.children.first;
      expect(leaf.isFolder, isFalse);
      expect(leaf.config!.method, 'GET');
      expect(leaf.config!.url, 'https://example.com/a?x=1');
      expect(leaf.config!.headers['X-Test'], 'y');
      expect(
        leaf.config!.params,
        [const QueryParamEntity(key: 'x', value: '1')],
      );
    });

    test('accepts url as plain string', () {
      const source = '''
{
  "info": {"name": "S", "schema": "v2.1.0"},
  "item": [
    {"name": "R", "request": {"method": "POST", "url": "https://plain.example.com"}}
  ]
}
''';
      final node = PostmanCollectionMapper.fromJson(source);
      expect(node.children.first.config!.url, 'https://plain.example.com');
      expect(node.children.first.config!.method, 'POST');
    });

    test('skips disabled headers and query entries', () {
      const source = '''
{
  "info": {"name": "S", "schema": "v2.1.0"},
  "item": [
    {
      "name": "R",
      "request": {
        "method": "GET",
        "header": [
          {"key": "A", "value": "1"},
          {"key": "B", "value": "2", "disabled": true}
        ],
        "url": {
          "raw": "https://x.y",
          "query": [
            {"key": "k1", "value": "v1"},
            {"key": "k2", "value": "v2", "disabled": true}
          ]
        }
      }
    }
  ]
}
''';
      final config = PostmanCollectionMapper.fromJson(source).children.first.config!;
      expect(config.headers, {'A': '1'});
      expect(config.url, 'https://x.y?k1=v1');
      expect(
        config.params,
        [const QueryParamEntity(key: 'k1', value: 'v1')],
      );
    });

    test('structured url.query takes precedence over url.raw query', () {
      const source = '''
{
  "info": {"name": "S", "schema": "v2.1.0"},
  "item": [
    {
      "name": "R",
      "request": {
        "method": "GET",
        "url": {
          "raw": "https://x.y?old=1",
          "query": [{"key": "new", "value": "2"}]
        }
      }
    }
  ]
}
''';
      final config = PostmanCollectionMapper.fromJson(source).children.first.config!;
      expect(config.url, 'https://x.y?new=2');
      expect(
        config.params,
        [const QueryParamEntity(key: 'new', value: '2')],
      );
    });

    test('throws FormatException on malformed JSON', () {
      expect(() => PostmanCollectionMapper.fromJson('not json'), throwsFormatException);
    });

    test('throws FormatException on missing info.schema', () {
      expect(
        () => PostmanCollectionMapper.fromJson('{"info": {"name": "x"}, "item": []}'),
        throwsFormatException,
      );
    });

    test('throws FormatException on non-v2.1 schema', () {
      expect(
        () => PostmanCollectionMapper.fromJson(
          '{"info": {"name": "x", "schema": "v1.0.0"}, "item": []}',
        ),
        throwsFormatException,
      );
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
  });
}
