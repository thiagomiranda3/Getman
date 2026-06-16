// lib/core/utils/openapi/swagger_v2_normalizer.dart
import 'dart:convert';

import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/openapi/ref_resolver.dart';
import 'package:getman/core/utils/openapi/schema_sampler.dart';
import 'package:getman/core/utils/openapi/spec_helpers.dart';

const _httpMethods = [
  'get',
  'post',
  'put',
  'patch',
  'delete',
  'head',
  'options',
];

/// Converts a Swagger 2.0 spec map into a [NormalizedApi].
NormalizedApi normalizeSwaggerV2(Map<String, dynamic> spec) {
  final refs = RefResolver(spec);
  final title =
      (spec['info'] is Map
          ? (spec['info'] as Map)['title'] as String?
          : null) ??
      'Imported API';

  final scheme =
      (spec['schemes'] is List && (spec['schemes'] as List).isNotEmpty)
      ? (spec['schemes'] as List).first.toString()
      : 'https';
  final host = (spec['host'] as String?) ?? '';
  final basePath = (spec['basePath'] as String?) ?? '';
  final servers = host.isEmpty
      ? <NormalizedServer>[]
      : [NormalizedServer(url: '$scheme://$host$basePath')];

  final schemes = _securityDefinitions(spec);
  final globalSecurity = firstSecuritySchemeName(spec['security']);

  final operations = <NormalizedOperation>[];
  final paths = spec['paths'];
  if (paths is Map) {
    for (final pathEntry in paths.entries) {
      final path = pathEntry.key.toString();
      final pathItem = pathEntry.value;
      if (pathItem is! Map) continue;
      for (final method in _httpMethods) {
        final op = pathItem[method];
        if (op is! Map) continue;
        operations.add(
          _operation(
            method: method.toUpperCase(),
            path: path,
            op: Map<String, dynamic>.from(op),
            refs: refs,
            schemes: schemes,
            globalSecurity: globalSecurity,
          ),
        );
      }
    }
  }
  return NormalizedApi(title: title, servers: servers, operations: operations);
}

NormalizedOperation _operation({
  required String method,
  required String path,
  required Map<String, dynamic> op,
  required RefResolver refs,
  required Map<String, NormalizedSecurityScheme> schemes,
  required String? globalSecurity,
}) {
  final tags = op['tags'];
  final tag = (tags is List && tags.isNotEmpty) ? tags.first.toString() : null;
  final name =
      (op['summary'] as String?) ??
      (op['operationId'] as String?) ??
      '$method $path';

  final query = <NormalizedParam>[];
  final headers = <NormalizedParam>[];
  final formFields = <MultipartFieldEntity>[];
  NormalizedBody? body;

  final rawParams = op['parameters'];
  if (rawParams is List) {
    for (final p in rawParams.whereType<Map<String, dynamic>>()) {
      final param = refs.resolve(Map<String, dynamic>.from(p));
      final location = param['in'] as String?;
      final pName = param['name'] as String?;
      switch (location) {
        case 'query':
          if (pName != null) {
            query.add(NormalizedParam(name: pName, value: _paramValue(param)));
          }
        case 'header':
          if (pName != null) {
            headers.add(
              NormalizedParam(name: pName, value: _paramValue(param)),
            );
          }
        case 'formData':
          if (pName != null) {
            formFields.add(
              MultipartFieldEntity(
                name: pName,
                isFile: param['type'] == 'file',
              ),
            );
          }
        case 'body':
          final schema = param['schema'];
          if (schema is Map) {
            final resolved = refs.deepResolve(
              Map<String, dynamic>.from(schema),
            );
            final sample = resolved is Map<String, dynamic>
                ? sampleSchema(resolved)
                : null;
            body = NormalizedBody(
              bodyType: BodyType.raw,
              contentType: 'application/json',
              raw: sample == null
                  ? ''
                  : const JsonEncoder.withIndent('  ').convert(sample),
            );
          }
        default:
          break; // 'path' stays templated
      }
    }
  }

  if (body == null && formFields.isNotEmpty) {
    final consumes = op['consumes'];
    final isMultipart =
        consumes is List &&
        consumes.any((c) => c.toString().contains('multipart'));
    body = NormalizedBody(
      bodyType: isMultipart ? BodyType.multipart : BodyType.urlencoded,
      formFields: formFields,
    );
  }

  NormalizedSecurityScheme? security;
  if (op.containsKey('security')) {
    final n = firstSecuritySchemeName(op['security']);
    security = n == null ? null : schemes[n];
  } else if (globalSecurity != null) {
    security = schemes[globalSecurity];
  }

  return NormalizedOperation(
    method: method,
    path: path,
    name: name,
    tag: tag,
    queryParams: query,
    headerParams: headers,
    body: body,
    security: security,
  );
}

Map<String, NormalizedSecurityScheme> _securityDefinitions(
  Map<String, dynamic> spec,
) {
  final out = <String, NormalizedSecurityScheme>{};
  final raw = spec['securityDefinitions'];
  if (raw is! Map) return out;
  for (final e in raw.entries) {
    final def = e.value;
    if (def is! Map) continue;
    final type = def['type'] as String?;
    switch (type) {
      case 'basic':
        out[e.key.toString()] = const NormalizedSecurityScheme(
          kind: SecuritySchemeKind.basic,
        );
      case 'apiKey':
        out[e.key.toString()] = NormalizedSecurityScheme(
          kind: def['in'] == 'query'
              ? SecuritySchemeKind.apiKeyQuery
              : SecuritySchemeKind.apiKeyHeader,
          apiKeyName: def['name'] as String?,
        );
      case 'oauth2':
        out[e.key.toString()] = const NormalizedSecurityScheme(
          kind: SecuritySchemeKind.oauth2,
        );
      default:
        out[e.key.toString()] = const NormalizedSecurityScheme(
          kind: SecuritySchemeKind.unsupported,
        );
    }
  }
  return out;
}

/// Extracts an example value from a Swagger 2.0 non-body parameter, which
/// carries `default` / `enum` / `x-example` directly on the parameter object
/// (unlike OpenAPI 3.x, which nests them under `schema`).
String _paramValue(Map<String, dynamic> param) {
  final explicit = param['x-example'] ?? param['default'];
  if (explicit != null) return explicit.toString();
  final enumValues = param['enum'];
  if (enumValues is List && enumValues.isNotEmpty) {
    return enumValues.first.toString();
  }
  return '';
}
