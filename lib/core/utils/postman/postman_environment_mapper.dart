// Encodes/decodes Postman environment JSON: toJson/toJsonAll export one or
// many EnvironmentEntity values (matching Postman's single-export and
// "Export Data" multi-export shapes); fromJson accepts either shape on
// import, rejecting anything that isn't recognizably a Postman environment
// via _requireEnvironmentShape. Secret variables are masked to an empty
// value (`type:'secret'`) on export; import restores the lock flag so a
// re-imported secret stays a secret instead of arriving as a plain variable.

import 'dart:convert';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:uuid/uuid.dart';

class PostmanEnvironmentMapper {
  static const Uuid _uuid = Uuid();
  static const String _scope = 'environment';

  /// Encodes a single Getman environment as a Postman environment JSON string.
  static String toJson(EnvironmentEntity env) {
    return const JsonEncoder.withIndent('  ').convert(_envToMap(env));
  }

  /// Encodes multiple environments as a JSON array. Matches how Postman's
  /// "Export Data" dump lists multiple environments.
  static String toJsonAll(List<EnvironmentEntity> envs) {
    final list = envs.map(_envToMap).toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  /// Decodes a Postman environment JSON string — accepts a single environment
  /// object or a JSON array of environment objects. Returns a fresh-id list so
  /// imports never collide with existing Getman environment ids.
  ///
  /// Throws [FormatException] on malformed input.
  static List<EnvironmentEntity> fromJson(String source) {
    final dynamic parsed;
    try {
      parsed = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Invalid JSON: ${e.message}');
    }
    if (parsed is Map) {
      final data = parsed.cast<String, dynamic>();
      _requireEnvironmentShape(data);
      return [_mapToEnv(data)];
    }
    if (parsed is List) {
      final entries =
          parsed
              .whereType<Map<dynamic, dynamic>>()
              .map((m) => m.cast<String, dynamic>())
              .toList()
            ..forEach(_requireEnvironmentShape);
      return entries.map(_mapToEnv).toList();
    }
    throw const FormatException(
      'Expected a JSON object or array for a Postman environment.',
    );
  }

  /// Mirrors the collections importer's `info.schema` strictness: reject an
  /// object that doesn't look like a Postman environment (neither a
  /// `values` list nor the `_postman_variable_scope` marker) rather than
  /// silently importing it as a junk environment.
  static void _requireEnvironmentShape(Map<String, dynamic> data) {
    final hasValues = data['values'] is List;
    final isEnvironmentScope = data['_postman_variable_scope'] == _scope;
    if (!hasValues && !isEnvironmentScope) {
      throw const FormatException(
        'Not a Postman environment — expected a "values" list or '
        '"_postman_variable_scope": "environment".',
      );
    }
  }

  static Map<String, dynamic> _envToMap(EnvironmentEntity env) {
    final values = env.variables.entries.map((e) {
      // Secret values are masked on export (matches Postman's shared-export
      // behavior) and tagged `secret` rather than `default`.
      final isSecret = env.secretKeys.contains(e.key);
      return {
        'key': e.key,
        'value': isSecret ? '' : e.value,
        'type': isSecret ? 'secret' : 'default',
        'enabled': true,
      };
    }).toList();
    return {
      'id': _uuid.v4(),
      'name': env.name,
      'values': values,
      '_postman_variable_scope': _scope,
      '_postman_exported_at': DateTime.now().toUtc().toIso8601String(),
      '_postman_exported_using': 'Getman',
    };
  }

  static EnvironmentEntity _mapToEnv(Map<String, dynamic> data) {
    final name = (data['name'] as String?) ?? 'Imported Environment';
    final rawValues = data['values'];
    final variables = <String, String>{};
    final secretKeys = <String>{};
    if (rawValues is List) {
      for (final entry in rawValues.whereType<Map<dynamic, dynamic>>()) {
        if (entry['enabled'] == false) continue;
        final key = entry['key'];
        final value = entry['value'];
        if (key is! String || key.isEmpty) continue;
        variables[key] = value is String ? value : (value?.toString() ?? '');
        // Restore the lock flag: without it a secret arrives as a plain
        // variable — displayed unobscured and re-exported unmasked. (Real
        // Postman local exports include secret values in plaintext.)
        if (entry['type'] == 'secret') secretKeys.add(key);
      }
    }
    return EnvironmentEntity(
      name: name,
      variables: variables,
      secretKeys: secretKeys,
    );
  }
}
