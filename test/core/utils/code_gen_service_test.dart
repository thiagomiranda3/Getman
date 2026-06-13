import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/code_gen_service.dart';

void main() {
  const bearerJson = HttpRequestConfigEntity(
    id: 'c',
    method: 'POST',
    url: 'https://{{host}}/login',
    headers: {'Content-Type': 'application/json'},
    body: '{"a":1}',
    auth: {'type': 'bearer', 'token': '{{token}}'},
  );

  group('cURL', () {
    test('reflects bearer auth and the body', () {
      final out = CodeGenService.generate(bearerJson, CodeGenTarget.curl);
      expect(out, contains('--request POST'));
      expect(out, contains("--header 'Authorization: Bearer {{token}}'"));
      expect(out, contains('--data'));
    });

    test('leaves {{env vars}} verbatim (it is a template)', () {
      final out = CodeGenService.generate(bearerJson, CodeGenTarget.curl);
      expect(out, contains('{{host}}'));
      expect(out, contains('Bearer {{token}}'));
    });

    test('urlencoded body renders a --data key=value string', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        method: 'POST',
        url: 'https://api.dev/x',
        bodyType: BodyType.urlencoded,
        formFields: [
          MultipartFieldEntity(name: 'a', value: '1'),
          MultipartFieldEntity(name: 'b', value: '2'),
        ],
      );
      final out = CodeGenService.generate(config, CodeGenTarget.curl);
      expect(out, contains("--data 'a=1&b=2'"));
      expect(out, contains('application/x-www-form-urlencoded'));
    });

    test('multipart body renders --form entries', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        method: 'POST',
        url: 'https://api.dev/x',
        bodyType: BodyType.multipart,
        formFields: [MultipartFieldEntity(name: 'field', value: 'v')],
      );
      final out = CodeGenService.generate(config, CodeGenTarget.curl);
      expect(out, contains("--form 'field=v'"));
    });

    test('api key in query is appended to the URL', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        url: 'https://api.dev/y',
        auth: {'type': 'apikey', 'key': 'k', 'value': 'v', 'addTo': 'query'},
      );
      final out = CodeGenService.generate(config, CodeGenTarget.curl);
      expect(out, contains('https://api.dev/y?k=v'));
    });
  });

  group('JavaScript fetch', () {
    test('emits a fetch call with method, headers and body', () {
      final out = CodeGenService.generate(bearerJson, CodeGenTarget.jsFetch);
      expect(out, contains("fetch('https://{{host}}/login'"));
      expect(out, contains("method: 'POST'"));
      expect(out, contains("'Authorization': 'Bearer {{token}}'"));
      expect(out, contains('body:'));
    });
  });

  group('Python requests', () {
    test('emits a requests.request call with headers and data', () {
      final out = CodeGenService.generate(bearerJson, CodeGenTarget.pythonRequests);
      expect(out, contains('import requests'));
      expect(out, contains("requests.request('POST'"));
      expect(out, contains('headers=headers'));
      expect(out, contains('data='));
    });
  });
}
