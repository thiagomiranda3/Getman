import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
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
      inject(AuthConfig.none);
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
      inject(
        const AuthConfig(
          type: AuthType.basic,
          username: 'aladdin',
          password: 'opensesame',
        ),
      );
      final expected = base64.encode(utf8.encode('aladdin:opensesame'));
      expect(headers['Authorization'], 'Basic $expected');
    });

    test('basic resolves env vars in credentials', () {
      inject(
        const AuthConfig(
          type: AuthType.basic,
          username: '{{u}}',
          password: '{{p}}',
        ),
        env: {'u': 'admin', 'p': 'pw'},
      );
      final expected = base64.encode(utf8.encode('admin:pw'));
      expect(headers['Authorization'], 'Basic $expected');
    });

    test('apikey in header adds the named header', () {
      inject(
        const AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: 'X-Api-Key',
          apiKeyValue: 'v',
        ),
      );
      expect(headers['X-Api-Key'], 'v');
      expect(query, isEmpty);
    });

    test('apikey in query adds to the query map', () {
      inject(
        const AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: 'api_key',
          apiKeyValue: 'v',
          apiKeyLocation: ApiKeyLocation.query,
        ),
      );
      expect(query['api_key'], ['v']);
      expect(headers, isEmpty);
    });

    test('apikey with empty name is a no-op', () {
      inject(const AuthConfig(type: AuthType.apiKey, apiKeyValue: 'v'));
      expect(headers, isEmpty);
      expect(query, isEmpty);
    });

    test(
      'does not clobber an explicit Authorization header (case-insensitive)',
      () {
        headers['authorization'] = 'Bearer manual';
        inject(const AuthConfig(type: AuthType.bearer, token: 'auto'));
        expect(headers['authorization'], 'Bearer manual');
        expect(headers.containsKey('Authorization'), isFalse);
      },
    );

    test('does not clobber an explicit api-key header (case-insensitive)', () {
      headers['x-api-key'] = 'manual';
      inject(
        const AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: 'X-Api-Key',
          apiKeyValue: 'auto',
        ),
      );
      expect(headers['x-api-key'], 'manual');
      expect(headers.containsKey('X-Api-Key'), isFalse);
    });
  });

  group('RequestSerializer.buildBody', () {
    late Map<String, String> headers;

    setUp(() {
      headers = {'Content-Type': 'application/json'};
    });

    // buildBody is async (file reads happen off the UI isolate).
    Future<dynamic> build(
      HttpRequestConfigEntity config, {
      Map<String, String> env = const {},
    }) {
      return RequestSerializer.buildBody(
        config: config,
        headers: headers,
        envVars: env,
      );
    }

    HttpRequestConfigEntity cfg({
      required BodyType bodyType,
      String body = '',
      List<MultipartFieldEntity> formFields = const [],
      String? bodyFilePath,
    }) => HttpRequestConfigEntity(
      id: 'c',
      bodyType: bodyType,
      body: body,
      formFields: formFields,
      bodyFilePath: bodyFilePath,
    );

    test('none returns null', () async {
      expect(await build(cfg(bodyType: BodyType.none)), isNull);
    });

    test('raw resolves env vars and is returned verbatim', () async {
      final data = await build(
        cfg(bodyType: BodyType.raw, body: '{"k":"{{v}}"}'),
        env: {'v': 'x'},
      );
      expect(data, '{"k":"x"}');
      // raw leaves the Content-Type the user set.
      expect(headers['Content-Type'], 'application/json');
    });

    test('raw with empty body returns null', () async {
      expect(await build(cfg(bodyType: BodyType.raw)), isNull);
    });

    test('urlencoded builds a map and forces the content type', () async {
      final data = await build(
        cfg(
          bodyType: BodyType.urlencoded,
          formFields: const [
            MultipartFieldEntity(name: 'a', value: '1'),
            MultipartFieldEntity(name: 'b', value: '{{x}}'),
            MultipartFieldEntity(name: '', value: 'skip'),
          ],
        ),
        env: {'x': '2'},
      );
      expect(data, {'a': '1', 'b': '2'});
      expect(headers['Content-Type'], 'application/x-www-form-urlencoded');
    });

    test(
      'multipart builds FormData with text fields and strips content type',
      () async {
        final data =
            await build(
                  cfg(
                    bodyType: BodyType.multipart,
                    formFields: const [
                      MultipartFieldEntity(name: 'field', value: 'v'),
                    ],
                  ),
                )
                as FormData;
        expect(data.fields, hasLength(1));
        expect(data.fields.first.key, 'field');
        expect(data.fields.first.value, 'v');
        // Content-Type removed so Dio sets multipart/form-data + boundary.
        expect(headers.containsKey('Content-Type'), isFalse);
      },
    );

    test('multipart reads a file row into FormData.files', () async {
      final file = File('${Directory.systemTemp.path}/getman_test_upload.txt')
        ..writeAsStringSync('hello');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final data =
          await build(
                cfg(
                  bodyType: BodyType.multipart,
                  formFields: [
                    MultipartFieldEntity(
                      name: 'doc',
                      isFile: true,
                      filePath: file.path,
                    ),
                  ],
                ),
              )
              as FormData;

      expect(data.files, hasLength(1));
      expect(data.files.first.key, 'doc');
      expect(data.files.first.value.filename, 'getman_test_upload.txt');
    });

    test('multipart applies an explicit file row content type (L2)', () async {
      // Extension is .bin (would otherwise infer octet-stream) so this asserts
      // the explicit contentType wins, not filename inference.
      final file = File('${Directory.systemTemp.path}/getman_test_typed.bin')
        ..writeAsBytesSync([1, 2, 3]);
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final data =
          await build(
                cfg(
                  bodyType: BodyType.multipart,
                  formFields: [
                    MultipartFieldEntity(
                      name: 'img',
                      isFile: true,
                      filePath: file.path,
                      contentType: 'image/png',
                    ),
                  ],
                ),
              )
              as FormData;

      expect(data.files.first.value.contentType?.mimeType, 'image/png');
    });

    test(
      'binary reads file bytes and sets octet-stream over the JSON default',
      () async {
        final file = File('${Directory.systemTemp.path}/getman_test_binary.bin')
          ..writeAsBytesSync([1, 2, 3]);
        addTearDown(() => file.existsSync() ? file.deleteSync() : null);

        final data = await build(
          cfg(bodyType: BodyType.binary, bodyFilePath: file.path),
        );
        expect(data, [1, 2, 3]);
        expect(headers['Content-Type'], 'application/octet-stream');
      },
    );

    test('binary keeps a user-chosen content type', () async {
      headers['Content-Type'] = 'image/png';
      final file = File('${Directory.systemTemp.path}/getman_test_img.bin')
        ..writeAsBytesSync([9]);
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      await build(cfg(bodyType: BodyType.binary, bodyFilePath: file.path));
      expect(headers['Content-Type'], 'image/png');
    });

    test('binary with no file path returns null', () async {
      expect(await build(cfg(bodyType: BodyType.binary)), isNull);
    });
  });
}
