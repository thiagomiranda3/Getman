import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/tabs/domain/logic/json_field_extractor.dart';

void main() {
  test('counts nested object keys and objects inside arrays', () {
    expect(
      extractJsonFieldCounts(
        '{"name":"name", "nested":{"name":1}, '
        '"items":[{"name":2}, {"other":true}]}',
      ),
      {'name': 3, 'nested': 1, 'items': 1, 'other': 1},
    );
  });

  test('learns complete keys before incomplete values and closing braces', () {
    expect(
      extractJsonFieldCounts('{"user": {"email":'),
      {'user': 1, 'email': 1},
    );
    expect(extractJsonFieldCounts('{"incomplete'), isEmpty);
    expect(extractJsonFieldCounts('{"noColon"'), isEmpty);
  });

  test('decodes escaped property names without matching strings in values', () {
    expect(
      extractJsonFieldCounts(
        r'{"quoted\"key": "\"fake\": 1", "\u006eame": ["value: text"]}',
      ),
      {'quoted"key': 1, 'name': 1},
    );
  });

  test('requires object key context and valid JSON string escapes', () {
    expect(extractJsonFieldCounts('["notAKey": 1]'), isEmpty);
    expect(extractJsonFieldCounts('"notAKey": 1'), isEmpty);
    expect(extractJsonFieldCounts(r'{"bad\q": 1}'), isEmpty);
    expect(extractJsonFieldCounts('{"real": "value": "fake": 1}'), {
      'real': 1,
    });
    expect(extractJsonFieldCounts('{"": 1}'), isEmpty);
  });

  test('stops at malformed string values before learning subsequent keys', () {
    expect(
      extractJsonFieldCounts(r'{"valid":"bad\q","later":1}'),
      {'valid': 1},
    );
  });

  test('continues learning after opaque unquoted variable values', () {
    expect(
      extractJsonFieldCounts(
        '{"id": {{id}}, "name": "x", '
        r'"items": [{{ dynamic value }}, {"nested": {{$timestamp}}}]}',
      ),
      {'id': 1, 'name': 1, 'items': 1, 'nested': 1},
    );
    expect(
      extractJsonFieldCounts('{"value": {{"fake":1}}, "real": 2}'),
      {'value': 1, 'real': 1},
    );
    expect(extractJsonFieldCounts('{{key}}: 1'), isEmpty);
    expect(extractJsonFieldCounts('{"value": {{incomplete'), {'value': 1});
  });

  test('stays iterative for deeply nested arrays', () {
    final prefix = List.filled(10000, '[').join();
    expect(extractJsonFieldCounts('$prefix{"leaf":'), {'leaf': 1});
  });
}
