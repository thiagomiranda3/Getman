import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';

void main() {
  group('AuthConfig.fromMap', () {
    test('empty map decodes to none (legacy records)', () {
      expect(AuthConfig.fromMap(const {}).type, AuthType.none);
      expect(AuthConfig.fromMap(const {}), AuthConfig.none);
    });

    test('unknown type falls back to none', () {
      expect(
        AuthConfig.fromMap(const {'type': 'spaceship'}).type,
        AuthType.none,
      );
    });

    test('decodes bearer', () {
      final a = AuthConfig.fromMap(const {'type': 'bearer', 'token': 'abc'});
      expect(a.type, AuthType.bearer);
      expect(a.token, 'abc');
    });

    test('decodes basic', () {
      final a = AuthConfig.fromMap(
        const {'type': 'basic', 'username': 'u', 'password': 'p'},
      );
      expect(a.type, AuthType.basic);
      expect(a.username, 'u');
      expect(a.password, 'p');
    });

    test('decodes apikey with header/query location', () {
      final header = AuthConfig.fromMap(
        const {
          'type': 'apikey',
          'key': 'X-Key',
          'value': 'v',
          'addTo': 'header',
        },
      );
      expect(header.type, AuthType.apiKey);
      expect(header.apiKeyName, 'X-Key');
      expect(header.apiKeyValue, 'v');
      expect(header.apiKeyLocation, ApiKeyLocation.header);

      final query = AuthConfig.fromMap(
        const {'type': 'apikey', 'key': 'k', 'value': 'v', 'addTo': 'query'},
      );
      expect(query.apiKeyLocation, ApiKeyLocation.query);
    });

    test('apikey defaults to header location when addTo missing/unknown', () {
      expect(
        AuthConfig.fromMap(const {'type': 'apikey', 'key': 'k'}).apiKeyLocation,
        ApiKeyLocation.header,
      );
    });
  });

  group('AuthConfig.toMap', () {
    test('none serializes to an empty map (dedup-stable)', () {
      expect(AuthConfig.none.toMap(), isEmpty);
    });

    test('round-trips every scheme through fromMap/toMap', () {
      final cases = [
        const AuthConfig(type: AuthType.inherit),
        const AuthConfig(type: AuthType.bearer, token: 't'),
        const AuthConfig(type: AuthType.basic, username: 'u', password: 'p'),
        const AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: 'k',
          apiKeyValue: 'v',
          apiKeyLocation: ApiKeyLocation.query,
        ),
      ];
      for (final c in cases) {
        expect(AuthConfig.fromMap(c.toMap()), c, reason: '${c.type}');
      }
    });
  });

  group('AuthConfig', () {
    test('copyWith overrides only the provided fields', () {
      const base = AuthConfig(type: AuthType.bearer, token: 'a');
      final next = base.copyWith(token: 'b');
      expect(next.type, AuthType.bearer);
      expect(next.token, 'b');
    });

    test('equality is value-based', () {
      expect(
        const AuthConfig(type: AuthType.bearer, token: 't'),
        const AuthConfig(type: AuthType.bearer, token: 't'),
      );
      expect(
        const AuthConfig(type: AuthType.bearer, token: 't'),
        isNot(const AuthConfig(type: AuthType.bearer, token: 'other')),
      );
    });

    test('basic credentials base64 as username:password', () {
      // Documents the exact wire encoding the serializer relies on.
      expect(
        base64.encode(utf8.encode('aladdin:opensesame')),
        'YWxhZGRpbjpvcGVuc2VzYW1l',
      );
    });
  });
}
