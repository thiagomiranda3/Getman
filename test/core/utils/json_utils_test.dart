import 'dart:convert';

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

  group('JsonUtils.prettify — lexeme-preserving reindent (I4)', () {
    test(
      'a large integer beyond 2^63-1 keeps its exact digits (a decode→encode '
      'round trip would coerce it to a lossy double)',
      () async {
        const input = '{"id":9223372036854775808}';
        final result = await JsonUtils.prettify(input);
        expect(result, contains('9223372036854775808'));
        // The lossy double form must NOT appear.
        expect(result, isNot(contains('9223372036854776000')));
        // And it is prettified (multi-line), not returned verbatim.
        expect(result, '{\n    "id": 9223372036854775808\n}');
      },
    );

    test(
      'an out-of-range magnitude keeps its literal lexeme (1e999)',
      () async {
        const input = '[1e999]';
        final result = await JsonUtils.prettify(input);
        expect(result, '[\n    1e999\n]');
      },
    );

    test('a high-precision decimal keeps its exact lexeme', () async {
      const input = '[0.30000000000000004]';
      final result = await JsonUtils.prettify(input);
      expect(result, '[\n    0.30000000000000004\n]');
    });

    test(
      'a unicode escape inside a string is preserved verbatim (not decoded '
      'to the raw character)',
      () async {
        // Built via char codes to sidestep source-encoding ambiguity:
        // `escape` is the six chars backslash u 0 0 e 9; `decoded` is 'é'.
        final escape = '${String.fromCharCode(0x5c)}u00e9';
        final decoded = String.fromCharCode(0xe9);
        final result = await JsonUtils.prettify('{"name":"$escape"}');
        expect(result, contains(escape));
        // The decoded character form must NOT appear.
        expect(result, isNot(contains(decoded)));
        expect(result, '{\n    "name": "$escape"\n}');
      },
    );

    test('a raw non-ASCII character is preserved (not escaped)', () async {
      final char = String.fromCharCode(0xe9); // 'é'
      final escape = '${String.fromCharCode(0x5c)}u00e9';
      final result = await JsonUtils.prettify('{"name":"$char"}');
      expect(result, contains(char));
      // It must NOT be rewritten into a \uXXXX escape.
      expect(result, isNot(contains(escape)));
      expect(result, '{\n    "name": "$char"\n}');
    });

    test(
      'escaped quotes and backslashes inside a string do not break tokenizing',
      () async {
        final result = await JsonUtils.prettify(r'{"a":"say \"hi\" \\ bye"}');
        expect(result, contains(r'say \"hi\" \\ bye'));
        expect(
          result,
          '{\n    "a": ${r'"say \"hi\" \\ bye"'}\n}',
        );
      },
    );

    test(
      'normal nested JSON indents identically to the pre-rewrite '
      'JsonEncoder.withIndent("    ") output',
      () async {
        const input = '{"a":1,"b":[1,2,{"c":true}],"d":{"e":"f"}}';
        final expected = const JsonEncoder.withIndent(
          '    ',
        ).convert(json.decode(input));
        final result = await JsonUtils.prettify(input);
        expect(result, expected);
      },
    );

    test('empty object and array stay on one line', () async {
      expect(await JsonUtils.prettify('{}'), '{}');
      expect(await JsonUtils.prettify('[]'), '[]');
      expect(await JsonUtils.prettify('{"a":[]}'), '{\n    "a": []\n}');
      expect(await JsonUtils.prettify('{"a":{}}'), '{\n    "a": {}\n}');
    });

    test('null / true / false literals pass through verbatim', () async {
      expect(
        await JsonUtils.prettify('{"a":null,"b":true,"c":false}'),
        '{\n    "a": null,\n    "b": true,\n    "c": false\n}',
      );
    });

    test('already-pretty input round-trips to the same shape', () async {
      const input = '{\n    "a": 1,\n    "b": 2\n}';
      final result = await JsonUtils.prettify(input);
      expect(result, input);
    });

    test(
      'invalid JSON leading with { is still returned verbatim (validity gate '
      'preserved)',
      () async {
        const invalid = '{not: valid, json}';
        expect(await JsonUtils.prettify(invalid), invalid);
      },
    );
  });
}
