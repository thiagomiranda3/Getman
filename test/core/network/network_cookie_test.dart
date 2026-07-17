import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/network_cookie.dart';

void main() {
  final uri = Uri.parse('https://api.example.com/v1/users');

  group('parseSetCookie', () {
    test('defaults domain/path from the request URI', () {
      final cookies = NetworkCookie.parseSetCookie(
        'sid=abc',
        requestUri: uri, // https://api.example.com/v1/users
        nowEpochMs: 0,
      );
      expect(cookies.single.name, 'sid');
      expect(cookies.single.value, 'abc');
      expect(cookies.single.domain, 'api.example.com');
      // RFC 6265 §5.1.4 default-path: the directory of the request URI.
      expect(cookies.single.path, '/v1');
      // Absent Domain → host-only.
      expect(cookies.single.hostOnly, isTrue);
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

    test(
      'rejects a Domain that does not cover the request host '
      '(RFC 6265 §5.3.6 — no cross-domain cookie planting)',
      () {
        // evil.com trying to plant a cookie for bank.com.
        final planted = NetworkCookie.parseSetCookie(
          'stolen=1; Domain=bank.com',
          requestUri: Uri.parse('https://evil.com/'),
          nowEpochMs: 0,
        );
        expect(planted, isEmpty);

        // A subdomain trying to set a cookie for a sibling.
        final sibling = NetworkCookie.parseSetCookie(
          'x=1; Domain=other.example.com',
          requestUri: uri,
          nowEpochMs: 0,
        );
        expect(sibling, isEmpty);
      },
    );

    test('rejects a bare public-suffix Domain (e.g. Domain=com)', () {
      final cookies = NetworkCookie.parseSetCookie(
        'x=1; Domain=com',
        requestUri: Uri.parse('https://evil.com/'),
        nowEpochMs: 0,
      );
      expect(cookies, isEmpty);
    });

    test('accepts a parent-domain Domain from a subdomain', () {
      final c = NetworkCookie.parseSetCookie(
        'sid=abc; Domain=example.com',
        requestUri: uri, // api.example.com
        nowEpochMs: 0,
      ).single;
      expect(c.domain, 'example.com');
    });

    test('accepts Domain equal to a single-label request host', () {
      final c = NetworkCookie.parseSetCookie(
        'sid=abc; Domain=localhost',
        requestUri: Uri.parse('http://localhost:8080/'),
        nowEpochMs: 0,
      ).single;
      expect(c.domain, 'localhost');
    });
  });

  group('host-only semantics (RFC 6265 §5.1.3)', () {
    test('no Domain attribute → host-only: exact host match only', () {
      final c = NetworkCookie.parseSetCookie(
        'sid=abc',
        requestUri: Uri.parse('https://example.com/'),
        nowEpochMs: 0,
      ).single;
      expect(c.hostOnly, isTrue);
      expect(c.matches(Uri.parse('https://example.com/')), isTrue);
      expect(c.matches(Uri.parse('https://api.example.com/')), isFalse);
    });

    test('explicit Domain=example.com → not host-only: subdomains match', () {
      final c = NetworkCookie.parseSetCookie(
        'sid=abc; Domain=example.com',
        requestUri: Uri.parse('https://example.com/'),
        nowEpochMs: 0,
      ).single;
      expect(c.hostOnly, isFalse);
      expect(c.matches(Uri.parse('https://example.com/')), isTrue);
      expect(c.matches(Uri.parse('https://api.example.com/')), isTrue);
    });

    test('a legacy cookie (hostOnly false default) keeps suffix matching', () {
      const c = NetworkCookie(name: 'a', value: '1', domain: 'example.com');
      expect(c.hostOnly, isFalse);
      expect(c.matches(Uri.parse('https://api.example.com/')), isTrue);
    });
  });

  group('default path (RFC 6265 §5.1.4)', () {
    test('no Path attribute → directory of the request URI', () {
      final c = NetworkCookie.parseSetCookie(
        'sid=abc',
        requestUri: Uri.parse('https://example.com/app1/login'),
        nowEpochMs: 0,
      ).single;
      expect(c.path, '/app1');
      expect(c.matches(Uri.parse('https://example.com/app1/x')), isTrue);
      expect(c.matches(Uri.parse('https://example.com/app2/x')), isFalse);
    });

    test('a Path value not starting with / falls back to the default', () {
      final c = NetworkCookie.parseSetCookie(
        'sid=abc; Path=relative',
        requestUri: Uri.parse('https://example.com/app1/login'),
        nowEpochMs: 0,
      ).single;
      expect(c.path, '/app1');
    });

    test('a rootless request path defaults to /', () {
      final c = NetworkCookie.parseSetCookie(
        'sid=abc',
        requestUri: Uri.parse('https://example.com/'),
        nowEpochMs: 0,
      ).single;
      expect(c.path, '/');
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
