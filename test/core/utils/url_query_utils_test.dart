import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/utils/url_query_utils.dart';

void main() {
  group('UrlQueryUtils.parse', () {
    test('splits base, empty query, no fragment', () {
      final parts = UrlQueryUtils.parse('https://example.com/path');
      expect(parts.base, 'https://example.com/path');
      expect(parts.params, isEmpty);
      expect(parts.fragment, isNull);
    });

    test('single key/value', () {
      final parts = UrlQueryUtils.parse('https://x/a?a=1');
      expect(parts.base, 'https://x/a');
      expect(parts.params, [const QueryParamEntity(key: 'a', value: '1')]);
    });

    test('preserves duplicate keys in order', () {
      final parts = UrlQueryUtils.parse('https://x/a?a=1&a=2');
      expect(parts.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'a', value: '2'),
      ]);
    });

    test('extracts fragment after query', () {
      final parts = UrlQueryUtils.parse('https://x/a?a=1#frag');
      expect(parts.base, 'https://x/a');
      expect(parts.params, [const QueryParamEntity(key: 'a', value: '1')]);
      expect(parts.fragment, 'frag');
    });

    test('extracts fragment when no query', () {
      final parts = UrlQueryUtils.parse('https://x/a#frag');
      expect(parts.base, 'https://x/a');
      expect(parts.params, isEmpty);
      expect(parts.fragment, 'frag');
    });

    test('missing equals sign yields empty value', () {
      final parts = UrlQueryUtils.parse('https://x/a?flag');
      expect(parts.params, [const QueryParamEntity(key: 'flag', value: '')]);
    });

    test('trailing equals yields empty value', () {
      final parts = UrlQueryUtils.parse('https://x/a?flag=');
      expect(parts.params, [const QueryParamEntity(key: 'flag', value: '')]);
    });

    test('empty keys are skipped', () {
      final parts = UrlQueryUtils.parse('https://x/a?&a=1&=2&b=3');
      expect(parts.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '3'),
      ]);
    });

    test('percent-decodes values', () {
      final parts = UrlQueryUtils.parse('https://x/a?q=hello%20world');
      expect(parts.params, [const QueryParamEntity(key: 'q', value: 'hello world')]);
    });

    test('percent-decodes special characters in values', () {
      final parts = UrlQueryUtils.parse('https://x/a?q=foo%26bar%3Dbaz');
      expect(parts.params, [const QueryParamEntity(key: 'q', value: 'foo&bar=baz')]);
    });

    test('preserves {{var}} tokens verbatim on parse', () {
      final parts = UrlQueryUtils.parse('https://x/a?id={{userId}}');
      expect(parts.params, [const QueryParamEntity(key: 'id', value: '{{userId}}')]);
    });

    test('only splits on the first ? and first # after it', () {
      final parts = UrlQueryUtils.parse('https://x/a?a=1&b=?=2#frag#tail');
      expect(parts.base, 'https://x/a');
      expect(parts.params, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '?=2'),
      ]);
      expect(parts.fragment, 'frag#tail');
    });
  });

  group('UrlQueryUtils.parseQuery', () {
    test('returns params list directly', () {
      final list = UrlQueryUtils.parseQuery('https://x/a?a=1&b=2');
      expect(list, [
        const QueryParamEntity(key: 'a', value: '1'),
        const QueryParamEntity(key: 'b', value: '2'),
      ]);
    });
  });

  group('UrlQueryUtils.build', () {
    test('reassembles base with no query', () {
      final url = UrlQueryUtils.build(base: 'https://x/a');
      expect(url, 'https://x/a');
    });

    test('emits ordered query', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [
          QueryParamEntity(key: 'a', value: '1'),
          QueryParamEntity(key: 'b', value: '2'),
        ],
      );
      expect(url, 'https://x/a?a=1&b=2');
    });

    test('preserves duplicate keys in order', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [
          QueryParamEntity(key: 'a', value: '1'),
          QueryParamEntity(key: 'a', value: '2'),
        ],
      );
      expect(url, 'https://x/a?a=1&a=2');
    });

    test('appends fragment', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [QueryParamEntity(key: 'a', value: '1')],
        fragment: 'frag',
      );
      expect(url, 'https://x/a?a=1#frag');
    });

    test('skips rows with empty keys', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [
          QueryParamEntity(key: '', value: '1'),
          QueryParamEntity(key: 'b', value: '2'),
        ],
      );
      expect(url, 'https://x/a?b=2');
    });

    test('percent-encodes values', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [QueryParamEntity(key: 'q', value: 'hello world')],
      );
      expect(url, 'https://x/a?q=hello%20world');
    });

    test('percent-encodes ampersand and equals in values', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [QueryParamEntity(key: 'q', value: 'foo&bar=baz')],
      );
      expect(url, 'https://x/a?q=foo%26bar%3Dbaz');
    });

    test('preserves {{var}} tokens literally on build', () {
      final url = UrlQueryUtils.build(
        base: 'https://x/a',
        params: const [QueryParamEntity(key: 'id', value: '{{userId}}')],
      );
      expect(url, 'https://x/a?id={{userId}}');
    });
  });

  group('UrlQueryUtils.replaceQuery', () {
    test('replaces existing query with new params, preserves fragment', () {
      final url = UrlQueryUtils.replaceQuery(
        'https://x/a?old=1#frag',
        const [QueryParamEntity(key: 'new', value: '2')],
      );
      expect(url, 'https://x/a?new=2#frag');
    });

    test('clears query when params is empty', () {
      final url = UrlQueryUtils.replaceQuery(
        'https://x/a?old=1',
        const [],
      );
      expect(url, 'https://x/a');
    });

    test('adds query to a URL that had none', () {
      final url = UrlQueryUtils.replaceQuery(
        'https://x/a',
        const [QueryParamEntity(key: 'a', value: '1')],
      );
      expect(url, 'https://x/a?a=1');
    });
  });

  group('round-trip', () {
    test('build(parse(url)) is idempotent on canonical input', () {
      const url = 'https://x/a?a=1&b=hello%20world&a=2#frag';
      final parts = UrlQueryUtils.parse(url);
      final rebuilt = UrlQueryUtils.build(
        base: parts.base,
        params: parts.params,
        fragment: parts.fragment,
      );
      expect(rebuilt, url);
    });
  });
}
