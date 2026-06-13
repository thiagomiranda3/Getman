import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/cookie_parser.dart';

void main() {
  group('CookieParser.parse', () {
    test('null / empty returns no cookies', () {
      expect(CookieParser.parse(null), isEmpty);
      expect(CookieParser.parse('   '), isEmpty);
    });

    test('parses a single cookie with attributes', () {
      final cookies = CookieParser.parse('sid=abc123; Path=/; HttpOnly');
      expect(cookies, [
        const ParsedCookie(name: 'sid', value: 'abc123', attributes: 'Path=/; HttpOnly'),
      ]);
    });

    test('splits multiple cookies joined with ", "', () {
      final cookies = CookieParser.parse('a=1; Path=/, b=2; Secure');
      expect(cookies.map((c) => c.name), ['a', 'b']);
      expect(cookies.map((c) => c.value), ['1', '2']);
    });

    test('does not split on the comma inside an Expires date', () {
      final cookies = CookieParser.parse(
        'sid=abc; Expires=Wed, 21 Oct 2025 07:28:00 GMT; Path=/, other=2',
      );
      expect(cookies, hasLength(2));
      expect(cookies[0].name, 'sid');
      expect(cookies[0].value, 'abc');
      expect(cookies[0].attributes, contains('Expires=Wed, 21 Oct 2025 07:28:00 GMT'));
      expect(cookies[1].name, 'other');
      expect(cookies[1].value, '2');
    });

    test('skips chunks without a name=value pair', () {
      final cookies = CookieParser.parse('justaflag; Path=/');
      expect(cookies, isEmpty);
    });

    test('handles a value containing "="', () {
      final cookies = CookieParser.parse('token=a=b=c; Path=/');
      expect(cookies.single.name, 'token');
      expect(cookies.single.value, 'a=b=c');
    });
  });
}
