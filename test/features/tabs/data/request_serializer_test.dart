import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/features/tabs/data/request_serializer.dart';

void main() {
  group('RequestSerializer.injectAuth', () {
    late Map<String, String> headers;
    late Map<String, List<String>> query;

    setUp(() {
      headers = {};
      query = {};
    });

    void inject(AuthConfig auth, {Map<String, String> env = const {}}) {
      RequestSerializer.injectAuth(
        auth: auth,
        headers: headers,
        query: query,
        envVars: env,
      );
    }

    test('none / inherit are no-ops', () {
      inject(const AuthConfig());
      inject(const AuthConfig(type: AuthType.inherit));
      expect(headers, isEmpty);
      expect(query, isEmpty);
    });

    test('bearer adds an Authorization header', () {
      inject(const AuthConfig(type: AuthType.bearer, token: 'abc123'));
      expect(headers['Authorization'], 'Bearer abc123');
    });

    test('bearer resolves env vars in the token', () {
      inject(
        const AuthConfig(type: AuthType.bearer, token: '{{tok}}'),
        env: {'tok': 'secret'},
      );
      expect(headers['Authorization'], 'Bearer secret');
    });

    test('bearer with empty token is a no-op', () {
      inject(const AuthConfig(type: AuthType.bearer));
      expect(headers, isEmpty);
    });

    test('basic encodes username:password as base64', () {
      inject(const AuthConfig(
        type: AuthType.basic,
        username: 'aladdin',
        password: 'opensesame',
      ));
      final expected = base64.encode(utf8.encode('aladdin:opensesame'));
      expect(headers['Authorization'], 'Basic $expected');
    });

    test('basic resolves env vars in credentials', () {
      inject(
        const AuthConfig(type: AuthType.basic, username: '{{u}}', password: '{{p}}'),
        env: {'u': 'admin', 'p': 'pw'},
      );
      final expected = base64.encode(utf8.encode('admin:pw'));
      expect(headers['Authorization'], 'Basic $expected');
    });

    test('apikey in header adds the named header', () {
      inject(const AuthConfig(
        type: AuthType.apiKey,
        apiKeyName: 'X-Api-Key',
        apiKeyValue: 'v',
      ));
      expect(headers['X-Api-Key'], 'v');
      expect(query, isEmpty);
    });

    test('apikey in query adds to the query map', () {
      inject(const AuthConfig(
        type: AuthType.apiKey,
        apiKeyName: 'api_key',
        apiKeyValue: 'v',
        apiKeyLocation: ApiKeyLocation.query,
      ));
      expect(query['api_key'], ['v']);
      expect(headers, isEmpty);
    });

    test('apikey with empty name is a no-op', () {
      inject(const AuthConfig(type: AuthType.apiKey, apiKeyValue: 'v'));
      expect(headers, isEmpty);
      expect(query, isEmpty);
    });

    test('does not clobber an explicit Authorization header (case-insensitive)', () {
      headers['authorization'] = 'Bearer manual';
      inject(const AuthConfig(type: AuthType.bearer, token: 'auto'));
      expect(headers['authorization'], 'Bearer manual');
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('does not clobber an explicit api-key header (case-insensitive)', () {
      headers['x-api-key'] = 'manual';
      inject(const AuthConfig(
        type: AuthType.apiKey,
        apiKeyName: 'X-Api-Key',
        apiKeyValue: 'auto',
      ));
      expect(headers['x-api-key'], 'manual');
      expect(headers.containsKey('X-Api-Key'), isFalse);
    });
  });
}
