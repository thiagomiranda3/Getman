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
      'equality/dedup still ignores body type + form fields (CLAUDE.md §6)',
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
        // method + url + body match → dedup-equal regardless of body type.
        expect(a == b, isTrue);
        expect(a.hashCode, b.hashCode);
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
}
