// lib/core/utils/openapi/spec_loader.dart
import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Decodes an OpenAPI/Swagger spec [source] (JSON *or* YAML) into a plain,
/// mutable `Map<String, dynamic>` tree (YAML `Map`/`List` nodes converted to
/// Dart `Map`/`List`). Throws [FormatException] if the source can't be parsed
/// or its root is not a map.
Map<String, dynamic> loadSpec(String source) {
  final trimmed = source.trimLeft();
  Object? decoded;
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Invalid JSON spec: ${e.message}');
    }
  } else {
    try {
      decoded = _normalizeYaml(loadYaml(source));
    } on Object catch (e) {
      throw FormatException('Invalid YAML spec: $e');
    }
  }
  if (decoded is! Map) {
    throw const FormatException('Spec root must be an object.');
  }
  return Map<String, dynamic>.from(decoded);
}

/// Recursively converts `YamlMap`/`YamlList` into mutable `Map`/`List`.
Object? _normalizeYaml(Object? node) {
  if (node is YamlMap) {
    return <String, dynamic>{
      for (final entry in node.entries)
        entry.key.toString(): _normalizeYaml(entry.value),
    };
  }
  if (node is YamlList) {
    return node.map(_normalizeYaml).toList();
  }
  return node;
}
