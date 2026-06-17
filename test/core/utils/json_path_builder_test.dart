import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/json_path.dart';
import 'package:getman/core/utils/json_path_builder.dart';

void main() {
  group('JsonPathBuilder', () {
    test('root is the whole-document selector', () {
      expect(JsonPathBuilder.root, r'$');
    });

    test('appends a simple identifier key with dot notation', () {
      expect(JsonPathBuilder.appendKey(r'$', 'user'), r'$.user');
      expect(JsonPathBuilder.appendKey(r'$.user', 'id'), r'$.user.id');
    });

    test('appends an array index with bracket notation', () {
      expect(JsonPathBuilder.appendIndex(r'$.items', 0), r'$.items[0]');
      expect(JsonPathBuilder.appendIndex(r'$', 2), r'$[2]');
    });

    test('bracket-quotes keys with spaces or dots', () {
      expect(
        JsonPathBuilder.appendKey(r'$', 'k with space'),
        r'$["k with space"]',
      );
      expect(
        JsonPathBuilder.appendKey(r'$', 'k.with.dots'),
        r'$["k.with.dots"]',
      );
    });

    test('single-quotes keys that contain a double quote', () {
      expect(JsonPathBuilder.appendKey(r'$', 'a"b'), '\$[\'a"b\']');
    });

    group('round-trips through JsonPath.read against real data', () {
      final doc = {
        'token': 'abc',
        'user': {
          'id': 7,
          'roles': ['admin', 'editor'],
          'k with space': 'spaced',
          'k.with.dots': 'dotted',
        },
        'items': [
          {'sku': 'A1'},
          {'sku': 'B2'},
        ],
      };

      void roundTrip(String path, Object? expected) {
        expect(JsonPath.isValid(path), isTrue, reason: 'invalid path: $path');
        expect(JsonPath.read(doc, path), expected, reason: 'path: $path');
      }

      test('top-level key', () {
        roundTrip(
          JsonPathBuilder.appendKey(JsonPathBuilder.root, 'token'),
          'abc',
        );
      });

      test('nested object key', () {
        final p = JsonPathBuilder.appendKey(
          JsonPathBuilder.appendKey(JsonPathBuilder.root, 'user'),
          'id',
        );
        roundTrip(p, 7);
      });

      test('array element field', () {
        final items = JsonPathBuilder.appendKey(JsonPathBuilder.root, 'items');
        final first = JsonPathBuilder.appendIndex(items, 0);
        final sku = JsonPathBuilder.appendKey(first, 'sku');
        roundTrip(sku, 'A1');
      });

      test('array primitive element', () {
        final user = JsonPathBuilder.appendKey(JsonPathBuilder.root, 'user');
        final roles = JsonPathBuilder.appendKey(user, 'roles');
        roundTrip(JsonPathBuilder.appendIndex(roles, 1), 'editor');
      });

      test('key with spaces', () {
        final user = JsonPathBuilder.appendKey(JsonPathBuilder.root, 'user');
        roundTrip(JsonPathBuilder.appendKey(user, 'k with space'), 'spaced');
      });

      test('key with dots', () {
        final user = JsonPathBuilder.appendKey(JsonPathBuilder.root, 'user');
        roundTrip(JsonPathBuilder.appendKey(user, 'k.with.dots'), 'dotted');
      });
    });
  });
}
