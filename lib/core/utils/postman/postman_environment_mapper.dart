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
      return [_mapToEnv(parsed.cast<String, dynamic>())];
    }
    if (parsed is List) {
      return parsed
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => _mapToEnv(m.cast<String, dynamic>()))
          .toList();
    }
    throw const FormatException(
      'Expected a JSON object or array for a Postman environment.',
    );
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
    if (rawValues is List) {
      for (final entry in rawValues.whereType<Map<dynamic, dynamic>>()) {
        if (entry['enabled'] == false) continue;
        final key = entry['key'];
        final value = entry['value'];
        if (key is! String || key.isEmpty) continue;
        variables[key] = value is String ? value : (value?.toString() ?? '');
      }
    }
    return EnvironmentEntity(name: name, variables: variables);
  }
}
