import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/json_path.dart';

void main() {
  group('read', () {
    final doc = {
      'token': 'abc',
      'user': {'id': 7, 'name': 'Ada'},
      'items': [
        {'sku': 'A'},
        {'sku': 'B'},
      ],
      'k with space': 'spaced',
    };

    test(r'dot member access (with and without leading $)', () {
      expect(JsonPath.read(doc, 'token'), 'abc');
      expect(JsonPath.read(doc, r'$.token'), 'abc');
      expect(JsonPath.read(doc, 'user.name'), 'Ada');
      expect(JsonPath.read(doc, r'$.user.id'), 7);
    });

    test('array index, including nested', () {
      expect(JsonPath.read(doc, 'items[0].sku'), 'A');
      expect(JsonPath.read(doc, r'$.items[1].sku'), 'B');
    });

    test('bracket-quoted keys', () {
      expect(JsonPath.read(doc, "['k with space']"), 'spaced');
      expect(JsonPath.read(doc, r'$["k with space"]'), 'spaced');
    });

    test(r'$ alone returns the whole document', () {
      expect(JsonPath.read(doc, r'$'), same(doc));
    });

    test('misses return null (never throw)', () {
      expect(JsonPath.read(doc, 'user.missing'), isNull);
      expect(JsonPath.read(doc, 'items[9].sku'), isNull);
      expect(JsonPath.read(doc, 'token.deeper'), isNull); // into a scalar
    });
  });

  group('readFromString', () {
    test('decodes then reads', () {
      expect(JsonPath.readFromString('{"a":{"b":42}}', 'a.b'), 42);
    });

    test('parse failure returns null', () {
      expect(JsonPath.readFromString('not json', 'a'), isNull);
    });
  });

  group('isValid', () {
    test('accepts supported syntax', () {
      expect(JsonPath.isValid(r'$.a.b[0]'), isTrue);
      expect(JsonPath.isValid("a['x']"), isTrue);
    });

    test('rejects malformed paths', () {
      expect(JsonPath.isValid(''), isFalse);
      expect(JsonPath.isValid('a..b'), isFalse);
      expect(JsonPath.isValid('a['), isFalse);
      expect(JsonPath.isValid('a[-1]'), isFalse);
      expect(JsonPath.isValid('a.'), isFalse);
    });
  });
}
