import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/auth_application.dart';
import 'package:getman/core/domain/entities/auth_config.dart';

void main() {
  String identity(String v) => v;
  AuthApplication apply(
    AuthConfig auth, {
    Map<String, String>? headers,
    String Function(String)? resolve,
  }) => resolveAuthApplication(
    auth: auth,
    currentHeaders: headers ?? <String, String>{},
    resolve: resolve ?? identity,
  );

  group('none / inherit', () {
    test('produce no effect', () {
      for (final t in [AuthType.none, AuthType.inherit]) {
        final app = apply(AuthConfig(type: t));
        expect(app.headers, isEmpty);
        expect(app.queryParam, isNull);
      }
    });
  });

  group('bearer', () {
    test('sets the Authorization header', () {
      final app = apply(const AuthConfig(type: AuthType.bearer, token: 'abc'));
      expect(app.headers, {'Authorization': 'Bearer abc'});
    });

    test('runs the token through resolve', () {
      final app = apply(
        const AuthConfig(type: AuthType.bearer, token: '{{tok}}'),
        resolve: (v) => v == '{{tok}}' ? 'real' : v,
      );
      expect(app.headers, {'Authorization': 'Bearer real'});
    });

    test('skips when the token resolves empty', () {
      expect(apply(const AuthConfig(type: AuthType.bearer)).headers, isEmpty);
    });

    test('skips when an Authorization header is already set (any casing)', () {
      final app = apply(
        const AuthConfig(type: AuthType.bearer, token: 'abc'),
        headers: {'authorization': 'existing'},
      );
      expect(app.headers, isEmpty);
    });
  });

  group('basic', () {
    test('base64-encodes user:pass', () {
      final app = apply(
        const AuthConfig(type: AuthType.basic, username: 'u', password: 'p'),
      );
      final value = app.headers['Authorization']!;
      expect(value.startsWith('Basic '), isTrue);
      expect(
        utf8.decode(base64.decode(value.substring('Basic '.length))),
        'u:p',
      );
    });

    test('skips when an Authorization header is already set', () {
      final app = apply(
        const AuthConfig(type: AuthType.basic, username: 'u', password: 'p'),
        headers: {'Authorization': 'x'},
      );
      expect(app.headers, isEmpty);
    });

    test(
      'skips the header when both username and password resolve empty (L1)',
      () {
        expect(apply(const AuthConfig(type: AuthType.basic)).headers, isEmpty);
      },
    );

    test('still sets the header when only the username is present', () {
      final app = apply(const AuthConfig(type: AuthType.basic, username: 'u'));
      expect(app.headers.containsKey('Authorization'), isTrue);
    });
  });

  group('apiKey', () {
    test('header location adds the named header', () {
      final app = apply(
        const AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: 'X-Key',
          apiKeyValue: 'secret',
        ),
      );
      expect(app.headers, {'X-Key': 'secret'});
      expect(app.queryParam, isNull);
    });

    test('header location skips when that header already exists', () {
      final app = apply(
        const AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: 'X-Key',
          apiKeyValue: 'secret',
        ),
        headers: {'x-key': 'existing'},
      );
      expect(app.headers, isEmpty);
    });

    test('query location returns a queryParam, no header', () {
      final app = apply(
        const AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: 'token',
          apiKeyValue: 'secret',
          apiKeyLocation: ApiKeyLocation.query,
        ),
      );
      expect(app.headers, isEmpty);
      expect(app.queryParam?.key, 'token');
      expect(app.queryParam?.value, 'secret');
    });

    test('skips entirely when the name resolves empty', () {
      final app = apply(
        const AuthConfig(type: AuthType.apiKey, apiKeyValue: 'v'),
      );
      expect(app.headers, isEmpty);
      expect(app.queryParam, isNull);
    });

    test('resolves both name and value', () {
      final app = apply(
        const AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: '{{n}}',
          apiKeyValue: '{{v}}',
        ),
        resolve: (s) => s == '{{n}}' ? 'X-Real' : (s == '{{v}}' ? 'val' : s),
      );
      expect(app.headers, {'X-Real': 'val'});
    });
  });
}
