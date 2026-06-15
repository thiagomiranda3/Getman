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

    test('api key value in query is URL-encoded', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        url: 'https://api.dev/y',
        auth: {
          'type': 'apikey',
          'key': 'k',
          'value': 'a b&c',
          'addTo': 'query',
        },
      );
      final out = CodeGenService.generate(config, CodeGenTarget.curl);
      expect(out, contains('https://api.dev/y?k=a%20b%26c'));
    });

    test('escapes a single quote in a header value with the POSIX idiom', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        url: 'https://api.dev/x',
        headers: {'X-Note': "it's fine"},
      );
      final out = CodeGenService.generate(config, CodeGenTarget.curl);
      expect(out, contains(r"X-Note: it'\''s fine"));
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

    test(
      'multiline body is a safe double-quoted literal, not a template literal',
      () {
        const config = HttpRequestConfigEntity(
          id: 'c',
          method: 'POST',
          url: 'https://api.dev/x',
          body:
              'line1\n'
              r'`back` ${x}',
        );
        final out = CodeGenService.generate(config, CodeGenTarget.jsFetch);
        expect(
          out,
          contains('body: "'),
          reason: r'double-quoted, so backtick/${} are literal',
        );
        expect(
          out,
          isNot(contains('body: `')),
          reason: 'must not wrap in a template literal',
        );
        expect(
          out,
          contains(r'\n'),
          reason: 'newline escaped into a single-line literal',
        );
      },
    );
  });

  group('Python requests', () {
    test('emits a requests.request call with headers and data', () {
      final out = CodeGenService.generate(
        bearerJson,
        CodeGenTarget.pythonRequests,
      );
      expect(out, contains('import requests'));
      expect(out, contains("requests.request('POST'"));
      expect(out, contains('headers=headers'));
      expect(out, contains('data='));
    });

    test(
      'multiline body is a double-quoted literal, not triple-single-quoted',
      () {
        const config = HttpRequestConfigEntity(
          id: 'c',
          method: 'POST',
          url: 'https://api.dev/x',
          body: "a\n'''b",
        );
        final out = CodeGenService.generate(
          config,
          CodeGenTarget.pythonRequests,
        );
        expect(
          out,
          contains('data = "'),
          reason: 'double-quoted, so an embedded triple-quote cannot break it',
        );
        expect(out, isNot(contains("data = '''")));
      },
    );
  });

  group('Node.js axios', () {
    test('emits an axios.request with method, url, headers and data', () {
      final out = CodeGenService.generate(bearerJson, CodeGenTarget.nodeAxios);
      expect(out, contains("require('axios')"));
      expect(out, contains("method: 'POST'"));
      expect(out, contains("url: 'https://{{host}}/login'"));
      expect(out, contains("'Authorization': 'Bearer {{token}}'"));
      expect(out, contains('data:'));
      expect(out, contains('axios.request(options)'));
    });

    test('multipart spreads form.getHeaders and appends fields', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        method: 'POST',
        url: 'https://api.dev/x',
        bodyType: BodyType.multipart,
        formFields: [MultipartFieldEntity(name: 'field', value: 'v')],
      );
      final out = CodeGenService.generate(config, CodeGenTarget.nodeAxios);
      expect(out, contains("require('form-data')"));
      expect(out, contains("form.append('field', 'v')"));
      expect(out, contains('...form.getHeaders()'));
      expect(out, contains('data: form'));
    });
  });

  group('Go net/http', () {
    test('emits a net/http request with method, url and headers', () {
      final out = CodeGenService.generate(bearerJson, CodeGenTarget.goNetHttp);
      expect(out, contains('package main'));
      expect(out, contains('"net/http"'));
      expect(out, contains('method := "POST"'));
      expect(out, contains('url := "https://{{host}}/login"'));
      expect(
        out,
        contains('req.Header.Add("Authorization", "Bearer {{token}}")'),
      );
      expect(out, contains('strings.NewReader'));
    });

    test('omits the strings import when there is no body', () {
      const config = HttpRequestConfigEntity(id: 'c', url: 'https://api.dev/x');
      final out = CodeGenService.generate(config, CodeGenTarget.goNetHttp);
      expect(
        out,
        isNot(contains('"strings"')),
        reason: 'unused imports are a compile error in Go',
      );
      expect(out, contains('http.NewRequest(method, url, nil)'));
    });
  });

  group('Java OkHttp', () {
    test('emits an OkHttp request with method, url and a typed body', () {
      final out = CodeGenService.generate(bearerJson, CodeGenTarget.javaOkHttp);
      expect(out, contains('OkHttpClient client = new OkHttpClient()'));
      expect(out, contains('.url("https://{{host}}/login")'));
      expect(out, contains('.method("POST", body)'));
      expect(out, contains('MediaType.parse("application/json")'));
      expect(out, contains('.addHeader("Authorization", "Bearer {{token}}")'));
    });

    test(
      'does not duplicate the Content-Type header when the body carries it',
      () {
        final out = CodeGenService.generate(
          bearerJson,
          CodeGenTarget.javaOkHttp,
        );
        expect(out, isNot(contains('.addHeader("Content-Type"')));
      },
    );

    test('urlencoded body uses a FormBody builder', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        method: 'POST',
        url: 'https://api.dev/x',
        bodyType: BodyType.urlencoded,
        formFields: [MultipartFieldEntity(name: 'a', value: '1')],
      );
      final out = CodeGenService.generate(config, CodeGenTarget.javaOkHttp);
      expect(out, contains('new FormBody.Builder()'));
      expect(out, contains('.add("a", "1")'));
    });
  });
}
