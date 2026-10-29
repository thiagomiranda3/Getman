import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/tabs/domain/logic/json_body_validation.dart';

void main() {
  group('validateJsonBody', () {
    for (final body in [
      '',
      '  \n\t',
      '{}',
      '[]',
      'true',
      'null',
      '42',
      '"hello"',
      '{"nested":[1,{"ok":true}],"value":null}',
      '{"quoted":"{{name}}", "value":{{payload}}}',
      r'[{{first}}, {{second}}, "escaped \" {{third}}"]',
      r'{"key":"{{name}}", "id":{{$guid}}}',
      '{{wholeBody}}',
    ]) {
      test('accepts JSON template $body', () {
        expect(validateJsonBody(body), isNull);
      });
    }

    for (final body in [
      '{',
      '[1,]',
      '{"a":1,}',
      '{"a":1 "b":2}',
      '{"a":{{value}} "b":2}',
      '[{{a}}{{b}}]',
      '{"a":{{value}},}',
      '{{name}}123',
      '{"a":{{incomplete}',
      r'{"bad":"\q {{name}}"}',
      '{"bad":"unterminated {{name}}}',
      '{"bad":{{name}} false}',
    ]) {
      test('reports malformed JSON template $body', () {
        final error = validateJsonBody(body);
        expect(error, isNotNull);
        expect(error!.message, isNotEmpty);
        expect(error.offset, inInclusiveRange(0, body.length));
      });
    }

    test('keeps original Unicode offsets after unquoted placeholders', () {
      const body = '{\n"😀":{{value}},\n"x": ]\n}';
      final error = validateJsonBody(body)!;
      expect(error.offset, 23);
      expect(error.line, 3);
      expect(error.column, 6);
    });

    test('keeps malformed escape visible beside a placeholde', () {
      const body = r'{"x":"\q{{name}}"}';
      final error = validateJsonBody(body)!;
      expect(error.offset, 8);
      expect(error.line, 1);
      expect(error.column, 9);
    });
  });
}
