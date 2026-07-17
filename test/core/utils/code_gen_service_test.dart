import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/code_gen_service.dart';
import 'package:getman/core/utils/environment_resolver.dart';

void main() {
  const bearerJson = HttpRequestConfigEntity(
    id: 'c',
    method: 'POST',
    url: 'https://{{host}}/login',
    headers: {'Content-Type': 'application/json'},
    body: '{"a":1}',
    auth: {'type': 'bearer', 'token': '{{token}}'},
  );

  group('variable resolution (export = runnable, no placeholders)', () {
    const templated = HttpRequestConfigEntity(
      id: 'c',
      method: 'POST',
      url: 'https://{{base}}/login',
      headers: {
        'Content-Type': 'application/json',
        'X-Token': 'Bearer {{token}}',
      },
      body: '{"key":"{{token}}"}',
      auth: {'type': 'bearer', 'token': '{{token}}'},
    );

    String resolve(String value) => EnvironmentResolver.resolve(value, const {
      'base': 'api.example.com',
      'token': 'secret123',
    });

    test('cURL resolves URL, header value, auth and body', () {
      final out = CodeGenService.generate(
        templated,
        CodeGenTarget.curl,
        resolve: resolve,
      );
      expect(out, contains('https://api.example.com/login'));
      expect(out, contains('X-Token: Bearer secret123'));
      expect(out, contains('Authorization: Bearer secret123'));
      expect(out, contains('"key":"secret123"'));
      expect(out, isNot(contains('{{base}}')));
      expect(out, isNot(contains('{{token}}')));
    });

    test('Python resolves URL, header value, auth and body', () {
      final out = CodeGenService.generate(
        templated,
        CodeGenTarget.pythonRequests,
        resolve: resolve,
      );
      expect(out, contains("url = 'https://api.example.com/login'"));
      expect(out, contains("'X-Token': 'Bearer secret123'"));
      expect(out, contains("'Authorization': 'Bearer secret123'"));
      expect(out, contains('secret123'));
      expect(out, isNot(contains('{{base}}')));
      expect(out, isNot(contains('{{token}}')));
    });

    test('JS fetch resolves URL, header value, auth and body', () {
      final out = CodeGenService.generate(
        templated,
        CodeGenTarget.jsFetch,
        resolve: resolve,
      );
      expect(out, contains("fetch('https://api.example.com/login'"));
      expect(out, contains("'X-Token': 'Bearer secret123'"));
      expect(out, contains("'Authorization': 'Bearer secret123'"));
      expect(out, isNot(contains('{{base}}')));
      expect(out, isNot(contains('{{token}}')));
    });

    test('resolves urlencoded form-field values', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        method: 'POST',
        url: 'https://api.dev/x',
        bodyType: BodyType.urlencoded,
        formFields: [MultipartFieldEntity(name: 'k', value: '{{token}}')],
      );
      final out = CodeGenService.generate(
        config,
        CodeGenTarget.curl,
        resolve: resolve,
      );
      expect(out, contains("--data 'k=secret123'"));
      expect(out, isNot(contains('{{token}}')));
    });

    test('unknown {{missing}} variables stay verbatim', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        url: 'https://{{missing}}/x',
        headers: {'X-Note': '{{absent}}'},
      );
      final out = CodeGenService.generate(
        config,
        CodeGenTarget.curl,
        resolve: resolve,
      );
      expect(out, contains('https://{{missing}}/x'));
      expect(out, contains('X-Note: {{absent}}'));
    });

    test('without a resolver, placeholders stay verbatim (default)', () {
      final out = CodeGenService.generate(templated, CodeGenTarget.curl);
      expect(out, contains('https://{{base}}/login'));
      expect(out, contains('Bearer {{token}}'));
    });
  });

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

    test('escapes a single quote in a header KEY with the POSIX idiom', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        url: 'https://api.dev/x',
        headers: {"X-It's-Fine": 'v'},
      );
      final out = CodeGenService.generate(config, CodeGenTarget.curl);
      expect(out, contains(r"--header 'X-It'\''s-Fine: v'"));
    });

    test('escapes a single quote in a binary body file path', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        url: 'https://api.dev/x',
        bodyType: BodyType.binary,
        bodyFilePath: "/tmp/a's file.png",
      );
      final out = CodeGenService.generate(config, CodeGenTarget.curl);
      expect(out, contains(r"--data-binary '@/tmp/a'\''s file.png'"));
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

    test('escapes a single quote in a header KEY', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        url: 'https://api.dev/x',
        headers: {"X-It's-Fine": 'v'},
      );
      final out = CodeGenService.generate(config, CodeGenTarget.jsFetch);
      expect(out, contains(r"'X-It\'s-Fine': 'v'"));
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

    test('escapes a single quote in a header KEY', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        url: 'https://api.dev/x',
        headers: {"X-It's-Fine": 'v'},
      );
      final out = CodeGenService.generate(config, CodeGenTarget.pythonRequests);
      expect(out, contains(r"'X-It\'s-Fine': 'v'"));
    });

    test(
      r'a Windows binary file path never becomes an invalid \U unicode '
      'escape (backslashes are escaped like the multipart branch already '
      'does)',
      () {
        const config = HttpRequestConfigEntity(
          id: 'c',
          url: 'https://api.dev/x',
          bodyType: BodyType.binary,
          bodyFilePath: r'C:\Users\me\file.bin',
        );
        final out = CodeGenService.generate(
          config,
          CodeGenTarget.pythonRequests,
        );
        expect(out, contains(r"open('C:\\Users\\me\\file.bin', 'rb')"));
      },
    );

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

    test('escapes a single quote in a header KEY', () {
      const config = HttpRequestConfigEntity(
        id: 'c',
        url: 'https://api.dev/x',
        headers: {"X-It's-Fine": 'v'},
      );
      final out = CodeGenService.generate(config, CodeGenTarget.nodeAxios);
      expect(out, contains(r"'X-It\'s-Fine': 'v'"));
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

  group('escaping (snippets must stay syntactically valid)', () {
    // A single quote is a legal URL sub-delim (e.g. names in a query).
    const quoteUrl = HttpRequestConfigEntity(
      id: 'q',
      url: "https://api.dev/search?q=O'Brien",
      headers: {},
    );

    test('cURL single-quotes the URL safely', () {
      final out = CodeGenService.generate(quoteUrl, CodeGenTarget.curl);
      expect(out, contains(r"--url 'https://api.dev/search?q=O'\''Brien'"));
    });

    test('JS fetch / axios / Python escape the URL literal', () {
      expect(
        CodeGenService.generate(quoteUrl, CodeGenTarget.jsFetch),
        contains(r"fetch('https://api.dev/search?q=O\'Brien'"),
      );
      expect(
        CodeGenService.generate(quoteUrl, CodeGenTarget.nodeAxios),
        contains(r"url: 'https://api.dev/search?q=O\'Brien'"),
      );
      expect(
        CodeGenService.generate(quoteUrl, CodeGenTarget.pythonRequests),
        contains(r"url = 'https://api.dev/search?q=O\'Brien'"),
      );
    });

    test('Python urlencoded/multipart values are escaped', () {
      const config = HttpRequestConfigEntity(
        id: 'p',
        method: 'POST',
        url: 'https://api.dev/x',
        headers: {},
        bodyType: BodyType.urlencoded,
        formFields: [MultipartFieldEntity(name: 'note', value: "it's fine")],
      );
      final out = CodeGenService.generate(
        config,
        CodeGenTarget.pythonRequests,
      );
      expect(out, contains(r"'note': 'it\'s fine'"));
    });

    test(
      'curl/Go urlencoded bodies are form-encoded like the send path '
      '(no parameter injection)',
      () {
        const config = HttpRequestConfigEntity(
          id: 'u',
          method: 'POST',
          url: 'https://api.dev/x',
          headers: {},
          bodyType: BodyType.urlencoded,
          formFields: [
            MultipartFieldEntity(name: 'q', value: 'a b&admin=true'),
          ],
        );
        final curl = CodeGenService.generate(config, CodeGenTarget.curl);
        expect(curl, contains('q=a+b%26admin%3Dtrue'));
        expect(curl, isNot(contains('&admin=true')));
        final go = CodeGenService.generate(config, CodeGenTarget.goNetHttp);
        expect(go, contains('q=a+b%26admin%3Dtrue'));
      },
    );
  });

  group('graphql body', () {
    test('cURL emits the GraphQL JSON envelope with application/json', () {
      const config = HttpRequestConfigEntity(
        id: 'gq',
        method: 'POST',
        url: 'https://api.example.com/graphql',
        bodyType: BodyType.graphql,
        body: 'query { me { id } }',
        graphqlVariables: '{"x":1}',
        headers: {},
      );
      final out = CodeGenService.generate(config, CodeGenTarget.curl);
      expect(out, contains('application/json'));
      expect(out, contains('"query"'));
      expect(out, contains('query { me { id } }'));
      expect(out, contains('"variables"'));
      expect(out, contains('"x":1'));
    });
  });
}
