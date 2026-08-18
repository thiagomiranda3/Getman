import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/parked_param_entity.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/param_row_composer.dart';
import 'package:getman/core/utils/postman/postman_collection_mapper.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

void main() {
  group('PostmanCollectionMapper.toJson', () {
    test('emits v2.1 schema and collection name', () {
      const root = CollectionNodeEntity(id: 'root', name: 'My API');
      final decoded =
          jsonDecode(PostmanCollectionMapper.toJson(root))
              as Map<String, dynamic>;
      final info = decoded['info'] as Map<String, dynamic>;
      expect(info['name'], 'My API');
      expect(info['schema'], contains('v2.1'));
      expect(decoded['item'], isEmpty);
    });

    test('maps folders and request leaves', () {
      const child = CollectionNodeEntity(
        id: 'leaf',
        name: 'Get Users',
        isFolder: false,
        config: HttpRequestConfigEntity(
          id: 'cfg',
          url: 'https://api.example.com/users?page=1',
          headers: {'X-Token': 'abc', 'Accept': 'application/json'},
        ),
      );
      const root = CollectionNodeEntity(
        id: 'root',
        name: 'API',
        children: [child],
      );
      final decoded =
          jsonDecode(PostmanCollectionMapper.toJson(root))
              as Map<String, dynamic>;
      final items = decoded['item'] as List;
      expect(items, hasLength(1));
      final item = items.first as Map<String, dynamic>;
      expect(item['name'], 'Get Users');
      final request = item['request'] as Map<String, dynamic>;
      expect(request['method'], 'GET');
      final url = request['url'] as Map<String, dynamic>;
      expect(url['raw'], 'https://api.example.com/users?page=1');
      final query = url['query'] as List;
      expect(query.first, {'key': 'page', 'value': '1'});
      final headers = request['header'] as List;
      expect(
        headers.any((h) {
          final header = h as Map<String, dynamic>;
          return header['key'] == 'X-Token' && header['value'] == 'abc';
        }),
        isTrue,
      );
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
      final decoded =
          jsonDecode(PostmanCollectionMapper.toJson(leaf))
              as Map<String, dynamic>;
      final item = (decoded['item'] as List).first as Map<String, dynamic>;
      final request = item['request'] as Map<String, dynamic>;
      final url = request['url'] as Map<String, dynamic>;
      final query = url['query'] as List;
      expect(query, [
        {'key': 'a', 'value': '1'},
        {'key': 'a', 'value': '2'},
      ]);
    });

    test(
      'emits raw body with json language hint when Content-Type is json',
      () {
        const config = HttpRequestConfigEntity(
          id: 'cfg',
          method: 'POST',
          url: 'https://api.example.com/users',
          headers: {'Content-Type': 'application/json'},
          body: '{"name":"x"}',
        );
        const leaf = CollectionNodeEntity(
          id: 'leaf',
          name: 'Create',
          isFolder: false,
          config: config,
        );
        final decoded =
            jsonDecode(PostmanCollectionMapper.toJson(leaf))
                as Map<String, dynamic>;
        final item = (decoded['item'] as List).first as Map<String, dynamic>;
        final request = item['request'] as Map<String, dynamic>;
        final body = request['body'] as Map<String, dynamic>;
        expect(body['mode'], 'raw');
        expect(body['raw'], '{"name":"x"}');
        final options = body['options'] as Map<String, dynamic>;
        final raw = options['raw'] as Map<String, dynamic>;
        expect(raw['language'], 'json');
      },
    );

    test(
      'exports url.query values RAW (still percent-encoded), matching url.raw',
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
        final decoded =
            jsonDecode(PostmanCollectionMapper.toJson(leaf))
                as Map<String, dynamic>;
        final item = (decoded['item'] as List).first as Map<String, dynamic>;
        final request = item['request'] as Map<String, dynamic>;
        final url = request['url'] as Map<String, dynamic>;
        expect(url['raw'], 'https://api.com/x?v=%2520');
        final query = url['query'] as List;
        expect(
          query.single,
          {'key': 'v', 'value': '%2520'},
          reason:
              'the decoded QueryParamEntity list would have produced '
              '"%20" here, double-decoding on the next import',
        );
      },
    );

    test('emits info.description for a folder root when non-empty', () {
      const root = CollectionNodeEntity(
        id: 'root',
        name: 'My API',
        description: 'Top-level notes.',
      );
      final decoded =
          jsonDecode(PostmanCollectionMapper.toJson(root))
              as Map<String, dynamic>;
      final info = decoded['info'] as Map<String, dynamic>;
      expect(info['description'], 'Top-level notes.');
    });

    test('wraps a single request leaf as an item', () {
      const leaf = CollectionNodeEntity(
        id: 'leaf',
        name: 'Ping',
        isFolder: false,
        config: HttpRequestConfigEntity(id: 'cfg', url: 'https://example.com'),
      );
      final decoded =
          jsonDecode(PostmanCollectionMapper.toJson(leaf))
              as Map<String, dynamic>;
      final items = decoded['item'] as List;
      expect(items, hasLength(1));
      expect((items.first as Map)['name'], 'Ping');
    });

    test(
      'exports disabled headers and parked params with disabled:true (B1)',
      () {
        const leaf = CollectionNodeEntity(
          id: 'leaf',
          name: 'Disabled rows',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'cfg',
            url: 'https://x.y?a=1&c=3',
            headers: {'Keep': 'k', 'Skip': 's'},
            disabledHeaderKeys: {'Skip'},
            disabledParams: [
              ParkedParamEntity(key: 'b', value: '2', rowIndex: 1),
            ],
          ),
        );
        final decoded =
            jsonDecode(PostmanCollectionMapper.toJson(leaf))
                as Map<String, dynamic>;
        final item = (decoded['item'] as List).first as Map<String, dynamic>;
        final request = item['request'] as Map<String, dynamic>;

        final headers = (request['header'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          headers.firstWhere((h) => h['key'] == 'Skip')['disabled'],
          isTrue,
        );
        expect(
          headers.firstWhere((h) => h['key'] == 'Keep').containsKey('disabled'),
          isFalse,
        );

        final query = (request['url'] as Map<String, dynamic>)['query'] as List;
        expect(query, [
          {'key': 'a', 'value': '1'},
          {'key': 'b', 'value': '2', 'disabled': true},
          {'key': 'c', 'value': '3'},
        ]);
      },
    );

    test(
      'a fully-disabled request round-trips through export + import (B1)',
      () {
        const leaf = CollectionNodeEntity(
          id: 'leaf',
          name: 'RT',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'cfg',
            url: 'https://x.y?a=1',
            headers: {'H': 'v'},
            disabledHeaderKeys: {'H'},
            disabledParams: [
              ParkedParamEntity(key: 'p', value: 'q', rowIndex: 0),
            ],
          ),
        );
        final back = PostmanCollectionMapper.fromJson(
          PostmanCollectionMapper.toJson(leaf),
        ).children.first.config!;
        expect(back.headers, {'H': 'v'});
        expect(back.disabledHeaderKeys, {'H'});
        expect(back.url, 'https://x.y?a=1');
        expect(back.disabledParams, [
          const ParkedParamEntity(key: 'p', value: 'q', rowIndex: 0),
        ]);
      },
    );

    test(
      'a later ENABLED duplicate header clears an earlier occurrence’s '
      'disabled flag (parked-variant-above-live Postman pattern)',
      () {
        final source = jsonEncode({
          'info': {
            'name': 'dup',
            'schema':
                'https://schema.getpostman.com/json/collection/v2.1.0/'
                'collection.json',
          },
          'item': [
            {
              'name': 'req',
              'request': {
                'method': 'GET',
                'url': {'raw': 'https://x.y/a'},
                'header': [
                  {'key': 'X-Trace', 'value': 'off', 'disabled': true},
                  {'key': 'X-Trace', 'value': 'on'},
                ],
              },
            },
          ],
        });
        final config = PostmanCollectionMapper.fromJson(
          source,
        ).children.first.config!;
        // The surviving (last) value is the enabled one — it must not
        // inherit the earlier row's disabled mark, or the header is
        // silently never sent.
        expect(config.headers, {'X-Trace': 'on'});
        expect(config.disabledHeaderKeys, isEmpty);
      },
    );

    test(
      'tied rowIndexes export in stable (non-reversed) order (Finding 1)',
      () {
        const leaf = CollectionNodeEntity(
          id: 'leaf',
          name: 'Tied',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'cfg',
            url: 'https://x.y?a=1&b=2&c=3&d=4&e=5',
            disabledParams: [
              ParkedParamEntity(key: 'p1', value: '10', rowIndex: 1),
              ParkedParamEntity(key: 'p2', value: '20', rowIndex: 1),
            ],
          ),
        );
        final decoded =
            jsonDecode(PostmanCollectionMapper.toJson(leaf))
                as Map<String, dynamic>;
        final item = (decoded['item'] as List).first as Map<String, dynamic>;
        final request = item['request'] as Map<String, dynamic>;
        final query = (request['url'] as Map<String, dynamic>)['query'] as List;
        expect(
          query.map((q) => (q as Map<String, dynamic>)['key']).toList(),
          ['a', 'p1', 'p2', 'b', 'c', 'd', 'e'],
          reason:
              'p1/p2 both tie at rowIndex 1 — they must keep their input '
              'order, not come out reversed',
        );
        expect(query[1], {'key': 'p1', 'value': '10', 'disabled': true});
        expect(query[2], {'key': 'p2', 'value': '20', 'disabled': true});
      },
    );

    test(
      'display order is round-trip lossless for tied rowIndexes '
      '(Finding 1)',
      () {
        const originalParams = [
          QueryParamEntity(key: 'a', value: '1'),
          QueryParamEntity(key: 'b', value: '2'),
          QueryParamEntity(key: 'c', value: '3'),
          QueryParamEntity(key: 'd', value: '4'),
          QueryParamEntity(key: 'e', value: '5'),
        ];
        const originalParked = [
          ParkedParamEntity(key: 'p1', value: '10', rowIndex: 1),
          ParkedParamEntity(key: 'p2', value: '20', rowIndex: 1),
        ];
        const leaf = CollectionNodeEntity(
          id: 'leaf',
          name: 'Tied',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'cfg',
            url: 'https://x.y?a=1&b=2&c=3&d=4&e=5',
            disabledParams: originalParked,
          ),
        );
        final back = PostmanCollectionMapper.fromJson(
          PostmanCollectionMapper.toJson(leaf),
        ).children.first.config!;

        final originalDisplay = ParamRowComposer.compose(
          params: originalParams,
          parked: originalParked,
        );
        final importedDisplay = ParamRowComposer.compose(
          params: back.params,
          parked: back.disabledParams,
        );

        expect(
          importedDisplay,
          originalDisplay,
          reason:
              'raw rowIndex values may legitimately differ across the '
              'round trip (1,1 -> 1,2) — display order/content is the '
              'actual invariant',
        );
      },
    );

    test(
      'duplicate key with one occurrence disabled exports and round-trips '
      'in place (Finding 1)',
      () {
        const leaf = CollectionNodeEntity(
          id: 'leaf',
          name: 'DupDisabled',
          isFolder: false,
          config: HttpRequestConfigEntity(
            id: 'cfg',
            url: 'https://x.y?a=1&a=2',
            disabledParams: [
              ParkedParamEntity(key: 'a', value: '3', rowIndex: 1),
            ],
          ),
        );
        final exportedJson = PostmanCollectionMapper.toJson(leaf);
        final decoded = jsonDecode(exportedJson) as Map<String, dynamic>;
        final item = (decoded['item'] as List).first as Map<String, dynamic>;
        final request = item['request'] as Map<String, dynamic>;
        final query = (request['url'] as Map<String, dynamic>)['query'] as List;
        expect(query, [
          {'key': 'a', 'value': '1'},
          {'key': 'a', 'value': '3', 'disabled': true},
          {'key': 'a', 'value': '2'},
        ]);

        final back = PostmanCollectionMapper.fromJson(
          exportedJson,
        ).children.first.config!;
        expect(back.params, [
          const QueryParamEntity(key: 'a', value: '1'),
          const QueryParamEntity(key: 'a', value: '2'),
        ]);
        expect(back.disabledParams, [
          const ParkedParamEntity(key: 'a', value: '3', rowIndex: 1),
        ]);
      },
    );
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

    test(
      'reconstructs a structured url (no raw) with protocol, host, port '
      'and path',
      () {
        const source = '''
{
  "info": {"name": "S", "schema": "v2.1.0"},
  "item": [
    {
      "name": "R",
      "request": {
        "method": "GET",
        "url": {
          "protocol": "https",
          "host": ["api", "example", "com"],
          "port": "8443",
          "path": ["v1", "users"]
        }
      }
    }
  ]
}
''';
        final config = PostmanCollectionMapper.fromJson(
          source,
        ).children.first.config!;
        expect(config.url, 'https://api.example.com:8443/v1/users');
      },
    );

    test('defaults to https when a structured url omits the protocol', () {
      const source = '''
{
  "info": {"name": "S", "schema": "v2.1.0"},
  "item": [
    {
      "name": "R",
      "request": {
        "method": "GET",
        "url": {"host": ["api", "example", "com"], "path": ["x"]}
      }
    }
  ]
}
''';
      final config = PostmanCollectionMapper.fromJson(
        source,
      ).children.first.config!;
      expect(config.url, 'https://api.example.com/x');
    });

    test('preserves disabled headers and query entries as disabled (B1)', () {
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
      final config = PostmanCollectionMapper.fromJson(
        source,
      ).children.first.config!;
      expect(config.headers, {'A': '1', 'B': '2'});
      expect(config.disabledHeaderKeys, {'B'});
      expect(config.url, 'https://x.y?k1=v1');
      expect(config.params, [const QueryParamEntity(key: 'k1', value: 'v1')]);
      expect(config.disabledParams, [
        const ParkedParamEntity(key: 'k2', value: 'v2', rowIndex: 1),
      ]);
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
      final config = PostmanCollectionMapper.fromJson(
        source,
      ).children.first.config!;
      expect(config.url, 'https://x.y?new=2');
      expect(
        config.params,
        [const QueryParamEntity(key: 'new', value: '2')],
      );
    });

    test(
      'imports the v2.1 string-shorthand request as a GET at that URL (F1)',
      () {
        final source = jsonEncode({
          'info': {
            'name': 'S',
            'schema':
                'https://schema.getpostman.com/json/collection/v2.1.0/'
                'collection.json',
          },
          'item': [
            {'name': 'Ping', 'request': 'https://shorthand.example.com/ping'},
          ],
        });
        final config = PostmanCollectionMapper.fromJson(
          source,
        ).children.single.config!;
        expect(
          config.url,
          'https://shorthand.example.com/ping',
          reason:
              'the string shorthand must keep its URL, not import as an '
              'empty default config',
        );
        expect(config.method, 'GET');
      },
    );

    test(
      'coerces numeric names instead of aborting the whole import (F2)',
      () {
        final source = jsonEncode({
          'info': {
            'name': 123,
            'schema':
                'https://schema.getpostman.com/json/collection/v2.1.0/'
                'collection.json',
          },
          'item': [
            {
              'name': 42,
              'request': {'method': null, 'url': 'https://x.y/a'},
            },
          ],
        });
        final node = PostmanCollectionMapper.fromJson(source);
        expect(node.name, '123');
        final leaf = node.children.single;
        expect(leaf.name, '42');
        expect(leaf.config!.method, 'GET');
        expect(leaf.config!.url, 'https://x.y/a');
      },
    );

    test(
      'reads string "true" disabled flags on headers, query, form rows '
      'and variables (F3)',
      () {
        final source = jsonEncode({
          'info': {
            'name': 'S',
            'schema':
                'https://schema.getpostman.com/json/collection/v2.1.0/'
                'collection.json',
          },
          'variable': [
            {'key': 'off', 'value': '1', 'disabled': 'true'},
            {'key': 'on', 'value': '2'},
          ],
          'item': [
            {
              'name': 'R',
              'request': {
                'method': 'POST',
                'header': [
                  {'key': 'A', 'value': '1', 'disabled': 'true'},
                  {'key': 'B', 'value': '2'},
                ],
                'url': {
                  'raw': 'https://x.y?k1=v1&k2=v2',
                  'query': [
                    {'key': 'k1', 'value': 'v1', 'disabled': 'true'},
                    {'key': 'k2', 'value': 'v2'},
                  ],
                },
                'body': {
                  'mode': 'formdata',
                  'formdata': [
                    {
                      'key': 'skip',
                      'type': 'text',
                      'value': 'x',
                      'disabled': 'true',
                    },
                    {'key': 'keep', 'type': 'text', 'value': 'y'},
                  ],
                },
              },
            },
          ],
        });
        final node = PostmanCollectionMapper.fromJson(source);
        expect(
          node.variables,
          {'on': '2'},
          reason: 'a variable disabled with the string "true" must not load',
        );
        final config = node.children.single.config!;
        expect(
          config.disabledHeaderKeys,
          {'A'},
          reason:
              'a header disabled with the string "true" must not import '
              'as enabled and get sent',
        );
        expect(config.url, 'https://x.y?k2=v2');
        expect(config.disabledParams, [
          const ParkedParamEntity(key: 'k1', value: 'v1', rowIndex: 0),
        ]);
        expect(config.formFields, [
          const MultipartFieldEntity(name: 'keep', value: 'y'),
        ]);
      },
    );

    test('throws FormatException on malformed JSON', () {
      expect(
        () => PostmanCollectionMapper.fromJson('not json'),
        throwsFormatException,
      );
    });

    test('throws FormatException on missing info.schema', () {
      expect(
        () => PostmanCollectionMapper.fromJson(
          '{"info": {"name": "x"}, "item": []}',
        ),
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

  // Round-trip coverage (export → import invariants: names, auth,
  // descriptions, form/multipart/graphql bodies, RequestKind and collection
  // variables) lives in postman_collection_mapper_roundtrip_test.dart
  // (main() here is at the function_lines_of_code metric gate).
}
