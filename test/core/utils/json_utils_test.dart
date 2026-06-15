import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/json_utils.dart';

void main() {
  group('JsonUtils.prettify', () {
    test('returns empty string for null', () async {
      expect(await JsonUtils.prettify(null), '');
    });

    test('returns empty string for empty input', () async {
      expect(await JsonUtils.prettify(''), '');
    });

    test(
      'short-circuits non-JSON: HTML body returned verbatim without '
      'modification',
      () async {
        const html = '<!DOCTYPE html><html><body>Hello</body></html>';
        final result = await JsonUtils.prettify(html);
        expect(result, html);
      },
    );

    test(
      'short-circuits non-JSON: plain-text body returned verbatim',
      () async {
        const plain = 'OK';
        final result = await JsonUtils.prettify(plain);
        expect(result, plain);
      },
    );

    test(
      'short-circuits non-JSON: body with leading whitespace before '
      'non-JSON char',
      () async {
        const text = '   some plain text';
        final result = await JsonUtils.prettify(text);
        expect(result, text);
      },
    );

    test('JSON object is prettified', () async {
      const compact = '{"a":1,"b":2}';
      final result = await JsonUtils.prettify(compact);
      // Prettified form contains newlines and indentation.
      expect(result, contains('\n'));
      expect(result, contains('"a"'));
      expect(result, contains('"b"'));
    });

    test('JSON array is prettified', () async {
      const compact = '[1,2,3]';
      final result = await JsonUtils.prettify(compact);
      expect(result, contains('\n'));
    });

    test(
      'invalid JSON string starting with { is returned as-is (not valid JSON)',
      () async {
        const invalid = '{not valid json}';
        final result = await JsonUtils.prettify(invalid);
        expect(result, invalid);
      },
    );

    test(
      'non-JSON body starting with [ is returned verbatim '
      '(e.g. the over-1-MB placeholder)',
      () async {
        // Regression: this string defeats the {/[ short-circuit, reaches the
        // parser, and used to spam the console with a FormatException log.
        const placeholder =
            '[response body over 1 MB was not persisted — re-send the request]';
        final result = await JsonUtils.prettify(placeholder);
        expect(result, placeholder);
      },
    );
  });
}
