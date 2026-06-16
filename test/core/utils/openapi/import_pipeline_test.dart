import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/openapi/collection_builder.dart';
import 'package:getman/core/utils/openapi/spec_loader.dart';
import 'package:getman/core/utils/openapi/spec_normalizer.dart';

const _json = '''
{"openapi":"3.0.0","info":{"title":"RT"},
 "servers":[{"url":"https://x.test"}],
 "paths":{"/a":{"get":{"summary":"GetA","tags":["T"]}}}}
''';

const _yaml = '''
openapi: 3.0.0
info:
  title: RT
servers:
  - url: https://x.test
paths:
  /a:
    get:
      summary: GetA
      tags: [T]
''';

void main() {
  test('JSON and YAML produce the same collection shape', () {
    final fromJson = buildImport(normalizeSpec(loadSpec(_json)));
    final fromYaml = buildImport(normalizeSpec(loadSpec(_yaml)));

    expect(fromJson.root.name, 'RT');
    expect(fromYaml.root.name, 'RT');
    expect(fromJson.root.children.single.name, 'T');
    expect(fromYaml.root.children.single.name, 'T');
    expect(fromJson.environments.single.variables['baseUrl'], 'https://x.test');
    expect(fromYaml.environments.single.variables['baseUrl'], 'https://x.test');
  });
}
