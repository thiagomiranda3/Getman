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
  });

  group('CurlUtils.generate', () {
    test('emits a command that parses back to the same request', () {
      const original = 'curl --request POST \\\n'
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
