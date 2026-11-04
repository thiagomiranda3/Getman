// Regression for real Postman exports containing unused pre-request hooks.
// Fixtures are synthetic: private collection URLs and credentials stay local.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/postman/postman_collection_mapper.dart';

Map<String, dynamic> collectionWithEvents(String level, dynamic events) {
  final request = <String, dynamic>{
    'method': 'POST',
    'url': 'https://example.com/items',
    'body': {'mode': 'raw', 'raw': '{"example":true}'},
  };
  final item = <String, dynamic>{'name': 'Request', 'request': request};
  final folder = <String, dynamic>{
    'name': 'Folder',
    'item': [item],
  };
  final root = <String, dynamic>{
    'info': {'name': 'Collection', 'schema': 'v2.1'},
    'item': [folder],
  };
  (switch (level) {
    'collection' => root,
    'folder' => folder,
    'item' => item,
    _ => request,
  })['event'] = events;
  return root;
}

void main() {
  for (final level in ['collection', 'folder', 'item', 'request']) {
    group('Postman events at $level', () {
      final emptyEvents = <String, dynamic>{
        'absent': null,
        'empty array': <dynamic>[],
        'missing script': [
          {'listen': 'prerequest'},
        ],
        for (final exec in <dynamic>[
          null,
          '',
          ' \n\t',
          <String>[],
          [''],
          [' ', '\t'],
        ])
          'empty source ${jsonEncode(exec)}': [
            {
              'listen': 'prerequest',
              'script': {'type': 'text/javascript', 'exec': exec},
            },
          ],
      };
      for (final fixture in emptyEvents.entries) {
        test('imports ${fixture.key} without losing the request', () {
          final root = PostmanCollectionMapper.fromJson(
            jsonEncode(collectionWithEvents(level, fixture.value)),
          );
          expect(root.name, 'Collection');
          final folder = root.children.single;
          expect(folder.name, 'Folder');
          final item = folder.children.single;
          expect(item.name, 'Request');
          expect(item.config!.url, 'https://example.com/items');
          expect(item.config!.method, 'POST');
          expect(item.config!.body, '{"example":true}');
          expect(item.config!.scripts.isEmpty, isTrue);
        });
      }

      final unsupportedEvents = <String, dynamic>{
        'inline source': [
          {
            'script': {'exec': 'pm.test("example", () => {});'},
          },
        ],
        'source after blank hook': [
          {
            'script': {
              'exec': [''],
            },
          },
          {
            'script': {
              'exec': ['', 'throw 1;'],
            },
          },
        ],
        'external source': [
          {
            'script': {
              'exec': [''],
              'src': 'https://example.com/hook.js',
            },
          },
        ],
        'structured external source': [
          {
            'script': {
              'src': {'raw': 'https://example.com/hook.js'},
            },
          },
        ],
        'malformed event list': <String, dynamic>{},
        'malformed event': [42],
        'malformed script': [
          {'script': 'throw 1;'},
        ],
        'malformed source': [
          {
            'script': {'exec': 42},
          },
        ],
        'malformed source line': [
          {
            'script': {
              'exec': [null],
            },
          },
        ],
      };
      for (final fixture in unsupportedEvents.entries) {
        test('rejects ${fixture.key} before returning a collection', () {
          // scripting.md: external Postman code has no runtime compatibility;
          // only empty placeholders can be discarded without losing behavior.
          expect(
            () => PostmanCollectionMapper.fromJson(
              jsonEncode(collectionWithEvents(level, fixture.value)),
            ),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'diagnostic',
                contains('Postman scripts are not supported: Collection'),
              ),
            ),
          );
        });
      }
    });
  }
}
