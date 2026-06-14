import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/request_kind.dart';

void main() {
  group('HttpRequestConfigEntity.params getter', () {
    test('returns empty list when URL has no query', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a');
      expect(config.params, isEmpty);
    });

    test('derives list from URL query', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a?a=1&b=2');
      expect(config.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '2'),
      ]);
    });

    test('preserves duplicate keys', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a?a=1&a=2');
      expect(config.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'a', value: '2'),
      ]);
    });
  });

  group('HttpRequestConfigEntity.copyWith', () {
    test('copyWith(url: ...) rewrites the URL directly', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a');
      final next = config.copyWith(url: 'https://example.com/b?c=1');
      expect(next.url, 'https://example.com/b?c=1');
      expect(next.params, [const QueryParamEntity(key: 'c', value: '1')]);
    });

    test('copyWith(params: [...]) rewrites the URL query', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a?old=1');
      final next = config.copyWith(params: const [
        QueryParamEntity(key: 'a', value: '1'),
        QueryParamEntity(key: 'b', value: '2'),
      ]);
      expect(next.url, 'https://example.com/a?a=1&b=2');
      expect(next.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '2'),
      ]);
    });

    test('copyWith(params: []) clears the query', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a?old=1');
      final next = config.copyWith(params: const []);
      expect(next.url, 'https://example.com/a');
      expect(next.params, isEmpty);
    });

    test('copyWith(url:, params:) — url wins', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a');
      final next = config.copyWith(
        url: 'https://example.com/b?kept=1',
        params: const [QueryParamEntity(key: 'ignored', value: 'x')],
      );
      expect(next.url, 'https://example.com/b?kept=1');
      expect(next.params, [const QueryParamEntity(key: 'kept', value: '1')]);
    });

    test('copyWith preserves fragment when rewriting query', () {
      const config = HttpRequestConfigEntity(id: 'x', url: 'https://example.com/a?old=1#frag');
      final next = config.copyWith(params: const [
        QueryParamEntity(key: 'new', value: '2'),
      ]);
      expect(next.url, 'https://example.com/a?new=2#frag');
    });
  });

  group('HttpRequestConfigEntity body-type fields', () {
    test('defaults: raw body type, no form fields, null file path', () {
      const config = HttpRequestConfigEntity(id: 'x');
      expect(config.bodyType, BodyType.raw);
      expect(config.formFields, isEmpty);
      expect(config.bodyFilePath, isNull);
    });

    test('copyWith sets body type + form fields', () {
      const config = HttpRequestConfigEntity(id: 'x');
      final next = config.copyWith(
        bodyType: BodyType.urlencoded,
        formFields: const [MultipartFieldEntity(name: 'a', value: '1')],
      );
      expect(next.bodyType, BodyType.urlencoded);
      expect(next.formFields, [const MultipartFieldEntity(name: 'a', value: '1')]);
    });

    test('copyWith clears bodyFilePath via the sentinel', () {
      const config = HttpRequestConfigEntity(id: 'x', bodyFilePath: '/tmp/a');
      expect(config.copyWith(bodyFilePath: null).bodyFilePath, isNull);
      // Omitting the arg keeps the existing value.
      expect(config.copyWith().bodyFilePath, '/tmp/a');
    });

    test('props include the new fields (drives dirty-tracking)', () {
      const a = HttpRequestConfigEntity(id: 'x');
      const b = HttpRequestConfigEntity(id: 'x', bodyType: BodyType.multipart);
      expect(a == b, isFalse);
    });
  });

  group('HttpRequestConfigEntity kind', () {
    test('defaults to http', () {
      expect(const HttpRequestConfigEntity(id: 'x').kind, RequestKind.http);
    });

    test('copyWith sets kind and it participates in equality', () {
      const config = HttpRequestConfigEntity(id: 'x');
      final ws = config.copyWith(kind: RequestKind.webSocket);
      expect(ws.kind, RequestKind.webSocket);
      expect(ws == config, isFalse);
    });
  });
}
