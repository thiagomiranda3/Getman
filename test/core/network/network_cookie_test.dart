import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/network_cookie.dart';

void main() {
  final uri = Uri.parse('https://api.example.com/v1/users');

  group('parseSetCookie', () {
    test('defaults domain/path from the request URI', () {
      final cookies = NetworkCookie.parseSetCookie(
        'sid=abc',
        requestUri: uri,
        nowEpochMs: 0,
      );
      expect(cookies.single.name, 'sid');
      expect(cookies.single.value, 'abc');
      expect(cookies.single.domain, 'api.example.com');
      expect(cookies.single.path, '/');
    });

    test('parses Path, Secure, HttpOnly and a leading-dot Domain', () {
      final c = NetworkCookie.parseSetCookie(
        'sid=abc; Path=/v1; Secure; HttpOnly; Domain=.example.com',
        requestUri: uri,
        nowEpochMs: 0,
      ).single;
      expect(c.path, '/v1');
      expect(c.secure, isTrue);
      expect(c.httpOnly, isTrue);
      expect(c.domain, 'example.com'); // leading dot stripped
    });

    test('Max-Age becomes an absolute expiry', () {
      final c = NetworkCookie.parseSetCookie(
        'a=1; Max-Age=100',
        requestUri: uri,
        nowEpochMs: 1000,
      ).single;
      expect(c.expiresEpochMs, 1000 + 100 * 1000);
    });
  });

  group('matches', () {
    test('domain suffix + path prefix', () {
      const c = NetworkCookie(
        name: 'a',
        value: '1',
        domain: 'example.com',
        path: '/v1',
      );
      expect(c.matches(Uri.parse('https://api.example.com/v1/users')), isTrue);
      expect(c.matches(Uri.parse('https://example.com/v1')), isTrue);
      expect(c.matches(Uri.parse('https://api.example.com/other')), isFalse);
      expect(c.matches(Uri.parse('https://evil.com/v1')), isFalse);
    });

    test('path matching respects the / boundary (no sibling over-match)', () {
      const c = NetworkCookie(
        name: 'a',
        value: '1',
        domain: 'example.com',
        path: '/api',
      );
      expect(c.matches(Uri.parse('https://example.com/api')), isTrue); // exact
      expect(
        c.matches(Uri.parse('https://example.com/api/users')),
        isTrue,
      ); // child
      expect(
        c.matches(Uri.parse('https://example.com/apixyz')),
        isFalse,
      ); // sibling
      expect(c.matches(Uri.parse('https://example.com/apiartisan/x')), isFalse);
    });

    test('secure cookies only match https', () {
      const c = NetworkCookie(
        name: 'a',
        value: '1',
        domain: 'example.com',
        secure: true,
      );
      expect(c.matches(Uri.parse('https://example.com/')), isTrue);
      expect(c.matches(Uri.parse('http://example.com/')), isFalse);
    });
  });

  test('isExpired honors expiresEpochMs', () {
    const session = NetworkCookie(name: 'a', value: '1', domain: 'x');
    expect(session.isExpired(99999), isFalse);
    const expiring = NetworkCookie(
      name: 'a',
      value: '1',
      domain: 'x',
      expiresEpochMs: 500,
    );
    expect(expiring.isExpired(499), isFalse);
    expect(expiring.isExpired(500), isTrue);
  });
}
