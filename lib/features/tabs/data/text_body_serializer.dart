// Resolves textual request bodies and builds GraphQL envelopes. Large inputs
// run in a worker; only strings/maps cross the boundary, never Dio or sockets.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/utils/environment_resolver.dart';

typedef _TextBody = ({
  BodyType type,
  String body,
  String variables,
  Map<String, String> environment,
});

Future<String> serializeTextBody({
  required BodyType type,
  required String body,
  required String variables,
  required Map<String, String> environment,
}) {
  final input = (
    type: type,
    body: body,
    variables: variables,
    environment: environment,
  );
  if (body.length + variables.length >= 64 * 1024) {
    return compute(_serialize, input);
  }
  return Future.value(_serialize(input));
}

String _serialize(_TextBody input) {
  String resolve(String text) =>
      EnvironmentResolver.resolve(text, input.environment);
  if (input.type == BodyType.raw) return resolve(input.body);
  final text = resolve(input.variables).trim();
  final Object? variables;
  try {
    variables = text.isEmpty ? const <String, dynamic>{} : jsonDecode(text);
  } on FormatException catch (error) {
    throw GraphqlVariablesException(error.message);
  }
  return jsonEncode(<String, dynamic>{
    'query': resolve(input.body),
    'variables': variables,
  });
}
