// lib/core/utils/openapi/openapi_v3_normalizer.dart
import 'dart:convert';

import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/openapi/ref_resolver.dart';
import 'package:getman/core/utils/openapi/schema_sampler.dart';

const _httpMethods = [
  'get',
  'post',
  'put',
  'patch',
  'delete',
  'head',
  'options',
];

/// Converts an OpenAPI 3.x spec map into a [NormalizedApi].
NormalizedApi normalizeOpenApiV3(Map<String, dynamic> spec) {
  final refs = RefResolver(spec);
  final title =
      (spec['info'] is Map
          ? (spec['info'] as Map)['title'] as String?
          : null) ??
      'Imported API';

  final servers = <NormalizedServer>[];
  final rawServers = spec['servers'];
  if (rawServers is List) {
    for (final s in rawServers.whereType<Map<String, dynamic>>()) {
      final vars = <String, String>{};
      final rawVars = s['variables'];
      if (rawVars is Map) {
        for (final e in rawVars.entries) {
          final def = e.value is Map ? (e.value as Map)['default'] : null;
          vars[e.key.toString()] = def?.toString() ?? '';
        }
      }
      servers.add(
        NormalizedServer(
          url: (s['url'] as String?) ?? '',
          description: s['description'] as String?,
          variables: vars,
        ),
      );
    }
  }

  final schemes = _securitySchemes(spec, refs);
  final globalSecurity = _firstSchemeName(spec['security']);

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
  final warnings = <String>[];
  final tags = op['tags'];
  final tag = (tags is List && tags.isNotEmpty) ? tags.first.toString() : null;
  final name =
      (op['summary'] as String?) ??
      (op['operationId'] as String?) ??
      '$method $path';

  final query = <NormalizedParam>[];
  final headers = <NormalizedParam>[];
  final rawParams = op['parameters'];
  if (rawParams is List) {
    for (final p in rawParams.whereType<Map<String, dynamic>>()) {
      final resolved = refs.resolve(Map<String, dynamic>.from(p));
      final location = resolved['in'] as String?;
      final pName = resolved['name'] as String?;
      if (pName == null) continue;
      final value = _paramExample(resolved, refs);
      if (location == 'query') {
        query.add(NormalizedParam(name: pName, value: value));
      } else if (location == 'header') {
        headers.add(NormalizedParam(name: pName, value: value));
      }
      // 'path' params stay templated in the path; 'cookie' ignored.
    }
  }

  NormalizedBody? body;
  final requestBody = op['requestBody'];
  if (requestBody is Map) {
    final resolvedBody = refs.resolve(Map<String, dynamic>.from(requestBody));
    final content = resolvedBody['content'];
    if (content is Map) {
      body = _body(content, refs, warnings);
    }
  }

  // Operation-level security overrides global; [] means "no auth".
  NormalizedSecurityScheme? security;
  if (op.containsKey('security')) {
    final opSecName = _firstSchemeName(op['security']);
    security = opSecName == null ? null : schemes[opSecName];
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
    warnings: warnings,
  );
}

String _paramExample(Map<String, dynamic> param, RefResolver refs) {
  if (param['example'] != null) return param['example'].toString();
  final schema = param['schema'];
  if (schema is Map) {
    final resolved = refs.deepResolve(Map<String, dynamic>.from(schema));
    if (resolved is Map<String, dynamic>) {
      final sample = sampleSchema(resolved);
      if (sample is String) return sample;
      if (sample is num || sample is bool) return sample.toString();
    }
  }
  return '';
}

NormalizedBody? _body(
  Map<dynamic, dynamic> content,
  RefResolver refs,
  List<String> warnings,
) {
  // Prefer JSON.
  String? chosenType;
  if (content.containsKey('application/json')) {
    chosenType = 'application/json';
  } else if (content.containsKey('application/x-www-form-urlencoded')) {
    chosenType = 'application/x-www-form-urlencoded';
  } else if (content.containsKey('multipart/form-data')) {
    chosenType = 'multipart/form-data';
  } else if (content.isNotEmpty) {
    chosenType = content.keys.first.toString();
  }
  if (chosenType == null) return null;

  final media = content[chosenType];
  final schema = media is Map && media['schema'] is Map
      ? refs.deepResolve(Map<String, dynamic>.from(media['schema'] as Map))
      : null;

  if (chosenType == 'application/x-www-form-urlencoded' ||
      chosenType == 'multipart/form-data') {
    final fields = _formFields(schema);
    return NormalizedBody(
      bodyType: chosenType == 'multipart/form-data'
          ? BodyType.multipart
          : BodyType.urlencoded,
      formFields: fields,
    );
  }

  // Raw JSON (or any other single content type treated as raw text).
  final sample = schema is Map<String, dynamic> ? sampleSchema(schema) : null;
  final raw = sample == null
      ? ''
      : const JsonEncoder.withIndent('  ').convert(sample);
  return NormalizedBody(
    bodyType: BodyType.raw,
    raw: raw,
    contentType: chosenType,
  );
}

List<MultipartFieldEntity> _formFields(Object? schema) {
  final out = <MultipartFieldEntity>[];
  if (schema is Map && schema['properties'] is Map) {
    for (final e in (schema['properties'] as Map).entries) {
      final prop = e.value;
      final isFile =
          prop is Map &&
          (prop['format'] == 'binary' || prop['format'] == 'byte');
      out.add(MultipartFieldEntity(name: e.key.toString(), isFile: isFile));
    }
  }
  return out;
}

Map<String, NormalizedSecurityScheme> _securitySchemes(
  Map<String, dynamic> spec,
  RefResolver refs,
) {
  final out = <String, NormalizedSecurityScheme>{};
  final components = spec['components'];
  final raw = components is Map ? components['securitySchemes'] : null;
  if (raw is! Map) return out;
  for (final e in raw.entries) {
    final scheme = refs.resolve(Map<String, dynamic>.from(e.value as Map));
    out[e.key.toString()] = _scheme(scheme);
  }
  return out;
}

NormalizedSecurityScheme _scheme(Map<String, dynamic> scheme) {
  final type = scheme['type'] as String?;
  switch (type) {
    case 'http':
      final s = (scheme['scheme'] as String?)?.toLowerCase();
      if (s == 'bearer') {
        return const NormalizedSecurityScheme(kind: SecuritySchemeKind.bearer);
      }
      if (s == 'basic') {
        return const NormalizedSecurityScheme(kind: SecuritySchemeKind.basic);
      }
      return const NormalizedSecurityScheme(
        kind: SecuritySchemeKind.unsupported,
      );
    case 'apiKey':
      final location = scheme['in'] as String?;
      return NormalizedSecurityScheme(
        kind: location == 'query'
            ? SecuritySchemeKind.apiKeyQuery
            : SecuritySchemeKind.apiKeyHeader,
        apiKeyName: scheme['name'] as String?,
      );
    case 'oauth2':
    case 'openIdConnect':
      return const NormalizedSecurityScheme(kind: SecuritySchemeKind.oauth2);
    default:
      return const NormalizedSecurityScheme(
        kind: SecuritySchemeKind.unsupported,
      );
  }
}

/// `[{schemeName: [...]}, ...]` → first scheme name, or null if empty/absent.
String? _firstSchemeName(Object? security) {
  if (security is List && security.isNotEmpty) {
    final first = security.first;
    if (first is Map && first.isNotEmpty) return first.keys.first.toString();
  }
  return null;
}
