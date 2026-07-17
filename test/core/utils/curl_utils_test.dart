import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/utils/curl_utils.dart';

void main() {
  group('CurlUtils.parse', () {
    test('parses method, url, headers, and body', () {
      final config = CurlUtils.parse(
        "curl -X POST 'https://api.dev/login' "
        "-H 'Content-Type: application/json' "
        "-H 'Authorization: Bearer abc' "
        "-d '{\"user\":\"x\"}'",
        id: 'id-1',
      );

      expect(config, isNotNull);
      expect(config!.id, 'id-1');
      expect(config.method, 'POST');
      expect(config.url, 'https://api.dev/login');
      expect(config.headers, {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer abc',
      });
      expect(config.body, '{"user":"x"}');
    });

    test('defaults to GET, upgrades to POST when data is present', () {
      final get = CurlUtils.parse('curl https://api.dev', id: 'a');
      expect(get!.method, 'GET');

      final post = CurlUtils.parse("curl https://api.dev -d 'x=1'", id: 'b');
      expect(post!.method, 'POST');
    });

    test('supports --url and --request long flags', () {
      final config = CurlUtils.parse(
        'curl --request PUT --url https://api.dev/items/1',
        id: 'a',
      );
      expect(config!.method, 'PUT');
      expect(config.url, 'https://api.dev/items/1');
    });

    test('returns null for non-curl input and for curl without a url', () {
      expect(CurlUtils.parse('wget https://api.dev', id: 'a'), isNull);
      expect(CurlUtils.parse('curl -X GET', id: 'a'), isNull);
    });

    test('recognizes a bare host (no http scheme) as the URL', () {
      final config = CurlUtils.parse('curl example.com/api', id: 'a');
      expect(config, isNotNull);
      expect(config!.url, 'example.com/api');
    });

    test('-u becomes a structured basic-auth config', () {
      final config = CurlUtils.parse(
        'curl https://api.dev -u user:pass',
        id: 'a',
      );
      expect(config!.authConfig.type, AuthType.basic);
      expect(config.authConfig.username, 'user');
      expect(config.authConfig.password, 'pass');
      // No raw Authorization header is emitted — the serializer derives it.
      expect(config.headers.containsKey('Authorization'), isFalse);
    });

    test('--data-urlencode encodes the value and upgrades to POST', () {
      final config = CurlUtils.parse(
        "curl https://api.dev --data-urlencode 'q=a b'",
        id: 'a',
      );
      expect(config!.method, 'POST');
      expect(config.body, 'q=a%20b');
    });

    test(
      '--data-urlencode with a leading = encodes the content and drops '
      'the =',
      () {
        // curl docs: `=content` encodes content, the leading `=` is not
        // included in the posted data (unlike `name=content`).
        final config = CurlUtils.parse(
          "curl https://api.dev --data-urlencode '=a b'",
          id: 'a',
        );
        expect(config!.body, 'a%20b');
      },
    );

    test('-G moves accumulated data into the query string and stays GET', () {
      final config = CurlUtils.parse(
        "curl https://api.dev/search -G -d 'q=term' -d 'p=2'",
        id: 'a',
      );
      expect(config!.method, 'GET');
      expect(config.url, 'https://api.dev/search?q=term&p=2');
      expect(config.body, isEmpty);
    });

    test(
      'skips an unhandled value flag so its value is not mistaken for the URL',
      () {
        final config = CurlUtils.parse(
          'curl -e https://ref.example https://api.dev/real',
          id: 'a',
        );
        expect(config!.url, 'https://api.dev/real');
        expect(config.headers['Referer'], 'https://ref.example');
      },
    );

    test(
      'FLAGSHIP: multiline --location + headers + multiline JSON --data '
      'infers POST and captures the body intact in the raw editor',
      () {
        const command = r'''
curl --location 'http://test.com/dynamics/websocket-metric' \
  --header 'async: true' \
  --header 'Content-Type: application/json' \
  --data '{
    "filter": {
        "account": "ACCOUNT",
        "dateMin": "20/12/2025 00:00:00",
        "dateMax": "03/01/2026 01:00:00",
        "tags": [
            "TAG"
        ]
    },
    "searchAfter": "123",
    "limit": 3
}'
''';

        final config = CurlUtils.parse(command, id: 'flagship');
        expect(config, isNotNull, reason: 'command must parse');

        // (a) method inferred from --data with no -X.
        expect(config!.method, 'POST');

        // URL captured (quotes stripped).
        expect(config.url, 'http://test.com/dynamics/websocket-metric');

        // Both headers present.
        expect(config.headers['async'], 'true');
        expect(config.headers['Content-Type'], 'application/json');

        // (b) The multiline single-quoted body is captured intact and lands in
        // the raw editor (Content-Type is JSON -> bodyType raw).
        expect(config.bodyType, BodyType.raw);
        expect(config.body.contains('"account": "ACCOUNT"'), isTrue);
        expect(config.body.contains('"limit": 3'), isTrue);
        // The body is valid JSON and round-trips structurally.
        final decoded = jsonDecode(config.body) as Map<String, dynamic>;
        expect(decoded['limit'], 3);
        expect((decoded['filter'] as Map)['account'], 'ACCOUNT');
        expect(((decoded['filter'] as Map)['tags'] as List).first, 'TAG');
      },
    );

    test('tokenizer handles backslash line continuations', () {
      const command =
          'curl -X POST https://api.dev/x \\\n'
          "  -H 'A: 1' \\\n"
          "  -d 'payload'";
      final config = CurlUtils.parse(command, id: 'a');
      expect(config!.method, 'POST');
      expect(config.url, 'https://api.dev/x');
      expect(config.headers['A'], '1');
      expect(config.body, 'payload');
    });

    test(
      'parses when line-continuation newlines are collapsed to spaces '
      '(single-line text field paste on web/Windows)',
      () {
        // A single-line TextField on web/Windows collapses pasted newlines to
        // spaces, so each trailing `\` line continuation arrives as `\ `
        // (backslash-space). macOS keeps the newline. The parser must treat the
        // collapsed form identically — otherwise every flag after the URL is
        // swallowed (only the URL survives) and the method falls back to GET.
        const multiline =
            "curl --location 'https://api.dev/orders' \\\n"
            "--header 'Content-Type: application/json' \\\n"
            '--data \'{"id": 1, "name": "widget"}\'';
        final collapsed = multiline.replaceAll('\n', ' ');

        final config = CurlUtils.parse(collapsed, id: 'collapsed');
        expect(config, isNotNull);
        expect(config!.method, 'POST');
        expect(config.url, 'https://api.dev/orders');
        expect(config.headers['Content-Type'], 'application/json');
        expect(config.bodyType, BodyType.raw);
        final decoded = jsonDecode(config.body) as Map<String, dynamic>;
        expect(decoded['id'], 1);
        expect(decoded['name'], 'widget');
      },
    );

    test(
      'mid-token escaped space stays a literal space (not a continuation)',
      () {
        // `\ ` inside a token (an unquoted path with a space) must remain a
        // genuine escaped space — only a backslash at a token boundary is a
        // collapsed line continuation.
        final config = CurlUtils.parse(
          r'curl https://api.dev/x -T /tmp/My\ Files/data.bin',
          id: 'escaped-space',
        );
        expect(config, isNotNull);
        expect(config!.method, 'PUT');
        expect(config.bodyFilePath, '/tmp/My Files/data.bin');
      },
    );

    test('double-quoted values support escapes and span newlines', () {
      final config = CurlUtils.parse(
        r'curl https://api.dev -d "line\"quote"',
        id: 'a',
      );
      expect(config!.body, 'line"quote');
    });

    test('single-quoted strings are literal (no escapes)', () {
      final config = CurlUtils.parse(
        r"curl https://api.dev -H 'X-Raw: a\nb'",
        id: 'a',
      );
      expect(config!.headers['X-Raw'], r'a\nb');
    });

    test(
      r"ANSI-C $'...' quoting is honored (Chrome/Firefox 'Copy as cURL' "
      'escapes an apostrophe in the body this way)',
      () {
        // Chrome/Firefox emit `--data-raw $'{"name":"O\'Brien"}'` whenever
        // the captured body contains an apostrophe. Before the fix this
        // corrupted the body: a leading `$`, truncated at the escaped
        // quote, and trailing garbage from the rest of the string.
        const command =
            r'''curl https://api.dev --data-raw $'{"name":"O\'Brien"}' ''';
        final config = CurlUtils.parse(command, id: 'a');
        expect(config, isNotNull);
        expect(config!.body, '{"name":"O\'Brien"}');
      },
    );

    test(
      r"ANSI-C $'...' honors backslash escapes "
      '(n, t, r, backslash, and quote)',
      () {
        final config = CurlUtils.parse(
          r'''curl https://api.dev -d $'line1\nline2\ttab\rcr\\slash\"quote' ''',
          id: 'a',
        );
        expect(config!.body, 'line1\nline2\ttab\rcr\\slash"quote');
      },
    );

    test(r"ANSI-C $'...' keeps unknown escapes verbatim (e.g. \q)", () {
      final config = CurlUtils.parse(
        r'''curl https://api.dev -d $'a\qb' ''',
        id: 'a',
      );
      expect(config!.body, r'a\qb');
    });

    test(r"ANSI-C $'...' decodes \xHH escapes", () {
      final config = CurlUtils.parse(
        r'''curl https://api.dev -d $'\x41BC' ''',
        id: 'a',
      );
      expect(config!.body, 'ABC');
    });

    test(r"ANSI-C $'...' decodes \uXXXX escapes", () {
      final config = CurlUtils.parse(
        r'''curl https://api.dev -d $'A\u0042C' ''',
        id: 'a',
      );
      expect(config!.body, 'ABC');
    });

    test('JSON body without an explicit Content-Type is still raw', () {
      final config = CurlUtils.parse(
        'curl https://api.dev -d \'{"k":1}\'',
        id: 'a',
      );
      expect(config!.bodyType, BodyType.raw);
      expect(config.body, '{"k":1}');
    });

    test('k=v&k=v data with no JSON content-type becomes urlencoded', () {
      final config = CurlUtils.parse(
        "curl https://api.dev -d 'a=1&b=2'",
        id: 'a',
      );
      expect(config!.bodyType, BodyType.urlencoded);
      expect(config.formFields.length, 2);
      expect(config.formFields[0].name, 'a');
      expect(config.formFields[0].value, '1');
      expect(config.formFields[1].name, 'b');
      expect(config.formFields[1].value, '2');
    });

    test('explicit urlencoded content-type forces urlencoded body type', () {
      final config = CurlUtils.parse(
        'curl https://api.dev '
        "-H 'Content-Type: application/x-www-form-urlencoded' "
        "-d 'a=1&b=2'",
        id: 'a',
      );
      expect(config!.bodyType, BodyType.urlencoded);
      expect(config.formFields.map((f) => f.name).toList(), ['a', 'b']);
    });

    test('--data-binary @file becomes a binary body referencing the file', () {
      final config = CurlUtils.parse(
        'curl https://api.dev --data-binary @/tmp/payload.bin',
        id: 'a',
      );
      expect(config!.method, 'POST');
      expect(config.bodyType, BodyType.binary);
      expect(config.bodyFilePath, '/tmp/payload.bin');
      expect(config.body, isEmpty);
    });

    test('--data-raw is taken verbatim, not concatenated', () {
      final config = CurlUtils.parse(
        "curl https://api.dev --data-raw 'a=1&b=2'",
        id: 'a',
      );
      // Treated as a urlencoded form (clear k=v pairs).
      expect(config!.bodyType, BodyType.urlencoded);
      expect(config.formFields.map((f) => f.name).toList(), ['a', 'b']);
    });

    test(
      '--data-raw with a leading @ is literal data, never a file reference',
      () {
        // curl's manual: --data-raw posts data without the special `@`
        // interpretation that -d/--data and --data-binary apply.
        final config = CurlUtils.parse(
          "curl https://api.dev --data-raw '@payload.json'",
          id: 'a',
        );
        expect(config!.bodyFilePath, isNull);
        expect(config.body, '@payload.json');
      },
    );

    test(
      '-d/--data with a leading @ is a file reference, like --data-binary',
      () {
        final config = CurlUtils.parse(
          'curl https://api.dev -d @payload.json',
          id: 'a',
        );
        expect(config!.method, 'POST');
        expect(config.bodyType, BodyType.binary);
        expect(config.bodyFilePath, 'payload.json');
        expect(config.body, isEmpty);
      },
    );

    test('-F populates multipart form fields (text + file)', () {
      final config = CurlUtils.parse(
        'curl https://api.dev '
        "-F 'name=value' "
        "-F 'avatar=@/tmp/a.png'",
        id: 'a',
      );
      expect(config!.method, 'POST');
      expect(config.bodyType, BodyType.multipart);
      expect(config.formFields.length, 2);

      final text = config.formFields[0];
      expect(text.name, 'name');
      expect(text.value, 'value');
      expect(text.isFile, isFalse);

      final file = config.formFields[1];
      expect(file.name, 'avatar');
      expect(file.isFile, isTrue);
      expect(file.filePath, '/tmp/a.png');
    });

    test('-A / -e / -b fold into User-Agent / Referer / Cookie headers', () {
      final config = CurlUtils.parse(
        'curl https://api.dev '
        "-A 'MyAgent/1.0' "
        "-e 'https://ref.example' "
        "-b 'session=abc'",
        id: 'a',
      );
      expect(config!.headers['User-Agent'], 'MyAgent/1.0');
      expect(config.headers['Referer'], 'https://ref.example');
      expect(config.headers['Cookie'], 'session=abc');
    });

    test('-I / --head infers the HEAD method', () {
      final config = CurlUtils.parse('curl -I https://api.dev', id: 'a');
      expect(config!.method, 'HEAD');
    });

    test('ignores -L/-k/--compressed/-s and similar boolean flags', () {
      final config = CurlUtils.parse(
        'curl -L -k --compressed -s https://api.dev/x',
        id: 'a',
      );
      expect(config, isNotNull);
      expect(config!.url, 'https://api.dev/x');
      expect(config.method, 'GET');
    });

    test('ignores value-taking flags like --max-time without crashing', () {
      final config = CurlUtils.parse(
        'curl --max-time 30 --connect-timeout 5 https://api.dev/x',
        id: 'a',
      );
      expect(config!.url, 'https://api.dev/x');
    });

    test('--tlsv1 is a boolean flag and does not swallow the URL', () {
      // --tlsv1 (and --tlsv1.0/.1/.2/.3) take no value; treating it as a
      // value-taking flag ate the URL entirely.
      final config = CurlUtils.parse(
        'curl --tlsv1 https://example.com',
        id: 'a',
      );
      expect(config, isNotNull);
      expect(config!.url, 'https://example.com');
    });

    test('--ciphers consumes its value without swallowing the URL', () {
      final config = CurlUtils.parse(
        'curl --ciphers ECDHE-RSA-AES128-GCM-SHA256 https://example.com',
        id: 'a',
      );
      expect(config, isNotNull);
      expect(config!.url, 'https://example.com');
    });

    test('long flag with =value form is tolerated', () {
      final config = CurlUtils.parse(
        "curl --request=POST --header='X: y' https://api.dev",
        id: 'a',
      );
      expect(config!.method, 'POST');
      expect(config.headers['X'], 'y');
    });

    test('an unknown long flag with =value does not become the URL', () {
      final config = CurlUtils.parse(
        'curl --some-unknown=thing https://api.dev/real',
        id: 'a',
      );
      expect(config!.url, 'https://api.dev/real');
    });

    test('method is clamped to a supported method (HttpMethods.all)', () {
      final config = CurlUtils.parse(
        'curl -X PATCH https://api.dev',
        id: 'a',
      );
      expect(config!.method, 'PATCH');
    });

    test('tolerates a leading "curl" with surrounding whitespace', () {
      final config = CurlUtils.parse('   curl   https://api.dev   ', id: 'a');
      expect(config!.url, 'https://api.dev');
    });

    test('accepts glued short options (-XPOST, -Hk: v, -dbody)', () {
      final del = CurlUtils.parse(
        'curl -XDELETE https://api.dev/items/1',
        id: 'a',
      )!;
      expect(del.method, 'DELETE');
      expect(del.url, 'https://api.dev/items/1');

      final post = CurlUtils.parse(
        "curl -XPOST 'https://api.dev' '-HContent-Type: application/json' "
        "-d'{\"a\":1}'",
        id: 'b',
      )!;
      expect(post.method, 'POST');
      expect(post.headers['Content-Type'], 'application/json');
      expect(post.body, '{"a":1}');
    });

    test('a glued skip-flag value is not mistaken for the URL', () {
      final config = CurlUtils.parse(
        'curl -ohttps://not-the-url.txt https://api.dev',
        id: 'a',
      )!;
      expect(config.url, 'https://api.dev');
    });

    test('boolean bundles like -sS are still ignored, not split', () {
      final config = CurlUtils.parse('curl -sS https://api.dev', id: 'a')!;
      expect(config.url, 'https://api.dev');
      expect(config.method, 'GET');
    });
  });

  group('CurlUtils.generate', () {
    test('emits a command that parses back to the same request', () {
      const original =
          'curl --request POST \\\n'
          "  --url 'https://api.dev/login' \\\n"
          "  --header 'Accept: */*' \\\n"
          "  --data '{\"a\":1}'";
      final config = CurlUtils.parse(original, id: 'x')!;

      final regenerated = CurlUtils.generate(config);
      final reparsed = CurlUtils.parse(regenerated, id: 'y')!;

      expect(reparsed.method, config.method);
      expect(reparsed.url, config.url);
      expect(reparsed.headers, config.headers);
      expect(reparsed.body, config.body);
    });
  });
}
