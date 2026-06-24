// test/core/utils/apidoc/yaml_emitter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/apidoc/yaml_emitter.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('emits nested maps with 2-space indent; dotted versions stay bare', () {
    final yaml = YamlEmitter.emit({
      'openapi': '3.0.3',
      'info': {'title': 'My API', 'version': '1.0.0'},
    });
    expect(
      yaml,
      'openapi: 3.0.3\n'
      'info:\n'
      '  title: My API\n'
      '  version: 1.0.0\n',
    );
  });

  test('emits lists with dashes; URLs stay bare', () {
    final yaml = YamlEmitter.emit({
      'servers': [
        {'url': 'https://a.com'},
        {'url': 'https://b.com'},
      ],
    });
    expect(
      yaml,
      'servers:\n'
      '  - url: https://a.com\n'
      '  - url: https://b.com\n',
    );
  });

  test('quotes genuinely ambiguous scalars only', () {
    expect(YamlEmitter.emit('42'), '"42"\n'); // parses as a number
    expect(YamlEmitter.emit('true'), '"true"\n'); // parses as a bool
    expect(YamlEmitter.emit('a: b'), '"a: b"\n'); // colon-space
    expect(YamlEmitter.emit('1.0.0'), '1.0.0\n'); // not a valid number → bare
    expect(
      YamlEmitter.emit('https://a.com'),
      'https://a.com\n',
    ); // colon, no space
    expect(YamlEmitter.emit('plain'), 'plain\n');
  });

  test('emits empty containers inline', () {
    expect(YamlEmitter.emit(<String, dynamic>{}), '{}\n');
    expect(YamlEmitter.emit(<dynamic>[]), '[]\n');
  });

  test('emits scalars: bool, int, null', () {
    expect(YamlEmitter.emit(true), 'true\n');
    expect(YamlEmitter.emit(42), '42\n');
    expect(YamlEmitter.emit(null), 'null\n');
  });

  test('nested empty map/list emit inline containers, not quoted strings', () {
    expect(YamlEmitter.emit({'a': <String, dynamic>{}}), 'a: {}\n');
    expect(YamlEmitter.emit({'a': <dynamic>[]}), 'a: []\n');
  });

  test('empty containers inside a list item stay inline', () {
    final yaml = YamlEmitter.emit({
      'items': [
        {'props': <String, dynamic>{}},
      ],
    });
    expect(yaml, 'items:\n  - props: {}\n');
  });

  test(
    'a string with an embedded newline emits a single-line quoted scalar',
    () {
      final yaml = YamlEmitter.emit({'desc': 'line1\nline2'});
      // single line, newline escaped, parses back to the original value
      expect(yaml, 'desc: "line1\\nline2"\n');
      expect(loadYaml(yaml), {'desc': 'line1\nline2'});
    },
  );

  test('control-char strings round-trip through a real YAML parser', () {
    final tree = {
      'info': {'title': 'My API', 'version': '1.0.0'},
      'example': {'body': 'a\nb\tc', 'note': 'x: y'},
    };
    final parsed = loadYaml(YamlEmitter.emit(tree)) as YamlMap;
    // loadYaml returns YamlMap; compare via scalar leaf assertions
    expect((parsed['info'] as YamlMap)['title'], 'My API');
    expect((parsed['example'] as YamlMap)['body'], 'a\nb\tc');
    expect((parsed['example'] as YamlMap)['note'], 'x: y');
  });

  test('a bare empty map as a direct list item stays inline', () {
    expect(YamlEmitter.emit([<String, dynamic>{}]), '- {}\n');
  });
}
