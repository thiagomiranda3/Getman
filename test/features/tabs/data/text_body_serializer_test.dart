// Exercise the actual compute boundary: large bodies, variable semantics and
// typed failures must match the small synchronous path without mutating inputs.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/features/tabs/data/text_body_serializer.dart';

void main() {
  test(
    'large raw bodies resolve nested variables and preserve unknowns',
    () async {
      final input = '${' ' * 65536}{{nested}} {{missing}}';
      const environment = {'nested': '{{value}}', 'value': 'resolved'};
      final output = await serializeTextBody(
        type: BodyType.raw,
        body: input,
        variables: '',
        environment: environment,
      );
      expect(output, '${' ' * 65536}resolved {{missing}}');
      expect(input.endsWith('{{nested}} {{missing}}'), isTrue);
      expect(environment['nested'], '{{value}}');
    },
  );

  test(
    'large GraphQL bodies preserve envelope and resolved JSON types',
    () async {
      final padding = 'x' * 65536;
      final output = await serializeTextBody(
        type: BodyType.graphql,
        body: 'query {{name}} { item }',
        variables: jsonEncode({
          'padding': padding,
          'value': '{{value}}',
          'n': 7,
        }),
        environment: const {'name': 'Test', 'value': 'resolved'},
      );
      expect(jsonDecode(output), {
        'query': 'query Test { item }',
        'variables': {'padding': padding, 'value': 'resolved', 'n': 7},
      });
    },
  );

  test('invalid large GraphQL variables preserve the typed failure', () async {
    await expectLater(
      serializeTextBody(
        type: BodyType.graphql,
        body: 'query { item }',
        variables: '${' ' * 65536}{bad',
        environment: const {},
      ),
      throwsA(isA<GraphqlVariablesException>()),
    );
  });
}
