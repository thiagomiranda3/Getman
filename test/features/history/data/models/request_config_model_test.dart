import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/tabs/data/models/multipart_field_model.dart';

void main() {
  group('HttpRequestConfig.toEntity() legacy-params migration', () {
    test('merges legacy params map into URL when non-empty', () {
      final model = HttpRequestConfig(
        id: 'id',
        url: 'https://x.y/path',
        params: {'a': '1', 'b': '2'},
      );
      final entity = model.toEntity();
      expect(entity.url, 'https://x.y/path?a=1&b=2');
      expect(entity.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '2'),
      ]);
    });

    test(
      'replaces existing URL query with legacy params when both present',
      () {
        // Pre-migration data shouldn't have both, but be lenient: legacy map
        // wins to restore user intent (they had explicit params rows before).
        final model = HttpRequestConfig(
          id: 'id',
          url: 'https://x.y/path?stale=1',
          params: {'fresh': '2'},
        );
        final entity = model.toEntity();
        expect(entity.url, 'https://x.y/path?fresh=2');
      },
    );

    test('passes URL through when legacy params is empty', () {
      final model = HttpRequestConfig(
        id: 'id',
        url: 'https://x.y/path?already=here',
        params: const {},
      );
      final entity = model.toEntity();
      expect(entity.url, 'https://x.y/path?already=here');
    });

    test('fromEntity writes an empty legacy params map', () {
      const entity = HttpRequestConfigEntity(
        id: 'id',
        url: 'https://x.y/path?a=1',
      );
      final model = HttpRequestConfig.fromEntity(entity);
      expect(model.params, isEmpty);
      expect(model.url, 'https://x.y/path?a=1');
    });
  });

  group('body-type fields', () {
    test('a model built without body-type args reads as raw/empty/null '
        '(matches a pre-migration record)', () {
      final model = HttpRequestConfig(id: 'id');
      final entity = model.toEntity();
      expect(entity.bodyType, BodyType.raw);
      expect(entity.formFields, isEmpty);
      expect(entity.bodyFilePath, isNull);
    });

    test('round-trips body type + form fields + binary path', () {
      const entity = HttpRequestConfigEntity(
        id: 'id',
        bodyType: BodyType.multipart,
        formFields: [
          MultipartFieldEntity(name: 'field', value: 'v'),
          MultipartFieldEntity(
            name: 'doc',
            isFile: true,
            filePath: '/tmp/a.txt',
          ),
        ],
        bodyFilePath: '/tmp/raw.bin',
      );
      final back = HttpRequestConfig.fromEntity(entity).toEntity();
      expect(back.bodyType, BodyType.multipart);
      expect(back.formFields, entity.formFields);
      expect(back.bodyFilePath, '/tmp/raw.bin');
    });

    test(
      'equality/dedup distinguishes body type + form fields (I2): two '
      'requests with matching method+url+body but different body shape are '
      'NOT deduped',
      () {
        final a = HttpRequestConfig(
          id: 'a',
          method: 'POST',
          url: 'https://x.y',
          body: 'b',
        );
        final b = HttpRequestConfig(
          id: 'b',
          method: 'POST',
          url: 'https://x.y',
          body: 'b',
          bodyType: 'multipart',
          formFields: [MultipartFieldModel(name: 'x')],
        );
        // method + url + body match, but body type + form fields differ →
        // distinct requests, so history keeps both.
        expect(a == b, isFalse);
      },
    );
  });

  group('request kind', () {
    test('a model built without kind reads as http (pre-migration record)', () {
      expect(HttpRequestConfig(id: 'id').toEntity().kind, RequestKind.http);
    });

    test('round-trips the kind', () {
      const entity = HttpRequestConfigEntity(
        id: 'id',
        url: 'wss://x',
        kind: RequestKind.webSocket,
      );
      expect(
        HttpRequestConfig.fromEntity(entity).toEntity().kind,
        RequestKind.webSocket,
      );
    });

    test('dedup ignores kind (method+url+body only)', () {
      final http = HttpRequestConfig(id: 'a', url: 'wss://x');
      final ws = HttpRequestConfig(id: 'b', url: 'wss://x', kind: 1);
      expect(http == ws, isTrue);
    });
  });

  group('graphql body', () {
    test('graphqlVariables survives entity -> model -> entity', () {
      const entity = HttpRequestConfigEntity(
        id: 'x',
        bodyType: BodyType.graphql,
        body: 'query { x }',
        graphqlVariables: '{"a":1}',
      );
      final back = HttpRequestConfig.fromEntity(entity).toEntity();
      expect(back.bodyType, BodyType.graphql);
      expect(back.graphqlVariables, '{"a":1}');
    });
  });

  group('dedup signature widening (I2)', () {
    test('same GraphQL query with different variables is NOT equal', () {
      final a = HttpRequestConfig(
        id: 'a',
        method: 'POST',
        url: 'https://api.example.com/graphql',
        body: 'query { me { id } }',
        bodyType: 'graphql',
        graphqlVariables: '{"page":1}',
      );
      final b = HttpRequestConfig(
        id: 'b',
        method: 'POST',
        url: 'https://api.example.com/graphql',
        body: 'query { me { id } }',
        bodyType: 'graphql',
        graphqlVariables: '{"page":2}',
      );
      expect(a == b, isFalse);
    });

    test('two binary uploads with different file paths are NOT equal', () {
      final a = HttpRequestConfig(
        id: 'a',
        method: 'POST',
        url: 'https://api.example.com/upload',
        bodyType: 'binary',
        bodyFilePath: '/tmp/one.bin',
      );
      final b = HttpRequestConfig(
        id: 'b',
        method: 'POST',
        url: 'https://api.example.com/upload',
        bodyType: 'binary',
        bodyFilePath: '/tmp/two.bin',
      );
      expect(a == b, isFalse);
    });

    test(
      'multipart requests with different form field values are NOT equal',
      () {
        final a = HttpRequestConfig(
          id: 'a',
          method: 'POST',
          url: 'https://api.example.com/form',
          bodyType: 'multipart',
          formFields: [MultipartFieldModel(name: 'file', value: 'a')],
        );
        final b = HttpRequestConfig(
          id: 'b',
          method: 'POST',
          url: 'https://api.example.com/form',
          bodyType: 'multipart',
          formFields: [MultipartFieldModel(name: 'file', value: 'b')],
        );
        expect(a == b, isFalse);
      },
    );

    test(
      'bodyType alone distinguishes otherwise-identical requests',
      () {
        final raw = HttpRequestConfig(
          id: 'a',
          method: 'POST',
          url: 'https://api.example.com/x',
          body: '{"k":1}',
        );
        final gql = HttpRequestConfig(
          id: 'b',
          method: 'POST',
          url: 'https://api.example.com/x',
          body: '{"k":1}',
          bodyType: 'graphql',
        );
        expect(raw == gql, isFalse);
      },
    );

    test(
      'identical multipart requests still dedupe (value equality on the '
      'form-field rows, not identity)',
      () {
        HttpRequestConfig make(String id) => HttpRequestConfig(
          id: id,
          method: 'POST',
          url: 'https://api.example.com/form',
          bodyType: 'multipart',
          formFields: [
            MultipartFieldModel(
              name: 'file',
              value: 'v',
              isFile: true,
              filePath: '/p',
            ),
            MultipartFieldModel(name: 'note', value: 'hi'),
          ],
        );
        final a = make('a');
        final b = make('b');
        expect(a == b, isTrue);
        expect(a.hashCode, b.hashCode);
      },
    );

    test('plain raw requests with an identical signature still dedupe', () {
      final a = HttpRequestConfig(
        id: 'a',
        method: 'POST',
        url: 'https://api.example.com/x',
        body: '{"k":1}',
      );
      final b = HttpRequestConfig(
        id: 'b',
        method: 'POST',
        url: 'https://api.example.com/x',
        body: '{"k":1}',
      );
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });
  });
}
