import 'package:equatable/equatable.dart';

/// The subset of JSON Schema that OpenAPI 3.0 uses for request/response bodies.
/// Pure data — no Flutter, no I/O. Built by [JsonSchemaInferrer] from a decoded
/// JSON value, then rendered to an OpenAPI `schema` map via [toOpenApi].
class JsonSchema extends Equatable {
  const JsonSchema({
    this.type,
    this.format,
    this.properties = const {},
    this.required = const [],
    this.items,
    this.nullable = false,
    this.example,
  });

  /// `object` / `array` / `string` / `integer` / `number` / `boolean`, or null
  /// when unknown (e.g. a bare null value).
  final String? type;
  final String? format; // e.g. `binary`
  final Map<String, JsonSchema> properties;
  final List<String> required;
  final JsonSchema? items;
  final bool nullable;
  final Object? example;

  Map<String, dynamic> toOpenApi() {
    final map = <String, dynamic>{};
    if (type != null) map['type'] = type;
    if (format != null) map['format'] = format;
    if (nullable) map['nullable'] = true;
    if (type == 'object') {
      map['properties'] = <String, dynamic>{
        for (final entry in properties.entries)
          entry.key: entry.value.toOpenApi(),
      };
      if (required.isNotEmpty) map['required'] = List<String>.from(required);
    }
    if (type == 'array' && items != null) {
      map['items'] = items!.toOpenApi();
    }
    if (example != null) map['example'] = example;
    return map;
  }

  @override
  List<Object?> get props => [
    type,
    format,
    properties,
    required,
    items,
    nullable,
    example,
  ];
}

/// Synthesizes a [JsonSchema] from a decoded JSON value (the reverse of the
/// import-side `schema_sampler.dart`). Arrays are inferred from their first
/// element; an object's keys are all treated as `required`.
class JsonSchemaInferrer {
  JsonSchemaInferrer._();

  static JsonSchema infer(Object? value) {
    if (value == null) return const JsonSchema(nullable: true);
    if (value is bool) return const JsonSchema(type: 'boolean');
    if (value is int) return const JsonSchema(type: 'integer');
    if (value is num) return const JsonSchema(type: 'number');
    if (value is String) return const JsonSchema(type: 'string');
    if (value is List) {
      if (value.isEmpty) return const JsonSchema(type: 'array');
      return JsonSchema(type: 'array', items: infer(value.first));
    }
    if (value is Map) {
      final props = <String, JsonSchema>{};
      final required = <String>[];
      for (final entry in value.entries) {
        final key = entry.key.toString();
        props[key] = infer(entry.value);
        required.add(key);
      }
      return JsonSchema(type: 'object', properties: props, required: required);
    }
    return const JsonSchema(type: 'string');
  }
}
