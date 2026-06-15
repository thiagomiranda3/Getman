// lib/core/utils/openapi/schema_sampler.dart

const int _maxDepth = 8;

/// Produces a representative Dart value (Map/List/scalar) for a resolved
/// JSON-Schema [schema], suitable for `jsonEncode`. Honors `example` →
/// `default` → first `enum`, then falls back to a type-based zero value.
Object? sampleSchema(Map<String, dynamic> schema) => _sample(schema, 0);

Object? _sample(Map<String, dynamic> schema, int depth) {
  if (depth > _maxDepth) return <String, dynamic>{};

  if (schema.containsKey('example')) return schema['example'];
  if (schema.containsKey('default')) return schema['default'];
  final enumValues = schema['enum'];
  if (enumValues is List && enumValues.isNotEmpty) return enumValues.first;

  if (schema['allOf'] is List) {
    final merged = <String, dynamic>{};
    final allOf = (schema['allOf'] as List).whereType<Map<String, dynamic>>();
    for (final part in allOf) {
      final sub = _sample(Map<String, dynamic>.from(part), depth);
      if (sub is Map<String, dynamic>) merged.addAll(sub);
    }
    return merged;
  }
  // oneOf/anyOf: sample the first branch.
  for (final key in const ['oneOf', 'anyOf']) {
    final branches = schema[key];
    if (branches is List && branches.isNotEmpty) {
      final first = branches.first;
      if (first is Map) {
        return _sample(Map<String, dynamic>.from(first), depth);
      }
    }
  }

  final type = schema['type'] as String?;
  if (type == 'object' || (type == null && schema['properties'] is Map)) {
    final props = schema['properties'];
    final out = <String, dynamic>{};
    if (props is Map) {
      for (final entry in props.entries) {
        final propSchema = entry.value;
        out[entry.key.toString()] = propSchema is Map
            ? _sample(Map<String, dynamic>.from(propSchema), depth + 1)
            : null;
      }
    }
    return out;
  }
  if (type == 'array') {
    final items = schema['items'];
    if (items is Map) {
      return [_sample(Map<String, dynamic>.from(items), depth + 1)];
    }
    return <dynamic>[];
  }
  switch (type) {
    case 'integer':
    case 'number':
      return 0;
    case 'boolean':
      return false;
    case 'string':
    default:
      return '';
  }
}
