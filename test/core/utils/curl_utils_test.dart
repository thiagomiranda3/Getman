import 'package:flutter_test/flutter_test.dart';
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

    test('-u becomes a Basic Authorization header', () {
      final config = CurlUtils.parse(
        'curl https://api.dev -u user:pass',
        id: 'a',
      );
      // base64('user:pass') == 'dXNlcjpwYXNz'
      expect(config!.headers['Authorization'], 'Basic dXNlcjpwYXNz');
    });

    test('--data-urlencode encodes the value and upgrades to POST', () {
      final config = CurlUtils.parse(
        "curl https://api.dev --data-urlencode 'q=a b'",
        id: 'a',
      );
      expect(config!.method, 'POST');
      expect(config.body, 'q=a%20b');
    });

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
      },
    );
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
