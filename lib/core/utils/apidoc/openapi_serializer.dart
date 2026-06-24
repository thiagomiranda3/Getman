// lib/core/utils/apidoc/openapi_serializer.dart
import 'dart:convert';

import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';
import 'package:getman/core/utils/apidoc/yaml_emitter.dart';

/// Renders an [ApiDoc] to an OpenAPI 3.0.3 document, as a map, JSON, or YAML.
/// Reads only auth *shape* from [ApiOperation.security] — never token/password/
/// key values.
class OpenApiSerializer {
  OpenApiSerializer._();

  static String toJson(ApiDoc doc) =>
      const JsonEncoder.withIndent('  ').convert(toMap(doc));

  static String toYaml(ApiDoc doc) => YamlEmitter.emit(toMap(doc));

  static Map<String, dynamic> toMap(ApiDoc doc) {
    final usedSchemes = <String, Map<String, dynamic>>{};

    final paths = <String, dynamic>{};
    for (final op in doc.operations) {
      final pathItem =
          (paths[op.path] as Map<String, dynamic>?) ??
          (paths[op.path] = <String, dynamic>{});
      final methodKey = op.method.toLowerCase();
      if (pathItem.containsKey(methodKey)) continue; // first wins on collision
      pathItem[methodKey] = _operation(op, usedSchemes);
    }

    final map = <String, dynamic>{
      'openapi': '3.0.3',
      'info': {'title': doc.title, 'version': doc.version},
      if (doc.servers.isNotEmpty)
        'servers': [for (final s in doc.servers) _server(s)],
      'paths': paths,
    };
    if (usedSchemes.isNotEmpty) {
      map['components'] = {'securitySchemes': usedSchemes};
    }
    return map;
  }

  static Map<String, dynamic> _server(ApiServer s) {
    final map = <String, dynamic>{'url': s.url};
    if (s.variables.isNotEmpty) {
      map['variables'] = {
        for (final entry in s.variables.entries)
          entry.key: {'default': entry.value},
      };
    }
    return map;
  }

  static Map<String, dynamic> _operation(
    ApiOperation op,
    Map<String, Map<String, dynamic>> usedSchemes,
  ) {
    final parameters = <Map<String, dynamic>>[
      for (final p in op.pathParams) _param(p, 'path'),
      for (final p in op.queryParams) _param(p, 'query'),
      for (final p in op.headerParams) _param(p, 'header'),
    ];

    final result = <String, dynamic>{
      'summary': op.summary,
      if (op.description != null) 'description': op.description,
      if (op.tag != null) 'tags': [op.tag],
      if (parameters.isNotEmpty) 'parameters': parameters,
      if (op.requestBody != null) 'requestBody': _body(op.requestBody!),
      'responses': {
        for (final r in op.responses)
          r.statusCode.toString(): {
            'description': r.description.isEmpty ? 'Response' : r.description,
            if (r.body != null) 'content': _content(r.body!),
          },
      },
    };

    final security = _security(op.security, usedSchemes);
    if (security != null) result['security'] = security;
    return result;
  }

  static Map<String, dynamic> _param(ApiParam p, String location) => {
    'name': p.name,
    'in': location,
    'required': location == 'path' || p.isRequired,
    'schema': p.schema?.toOpenApi() ?? {'type': 'string'},
    if (p.example != null) 'example': p.example,
  };

  static Map<String, dynamic> _body(ApiBody body) => {
    'content': _content(body),
  };

  static Map<String, dynamic> _content(ApiBody body) => {
    body.contentType: {
      if (body.schema != null) 'schema': body.schema!.toOpenApi(),
      if (body.example != null) 'example': body.example,
    },
  };

  /// Returns the `security` list for an operation, registering the scheme in
  /// [usedSchemes]. Null for none/inherit.
  static List<Map<String, List<dynamic>>>? _security(
    AuthConfig auth,
    Map<String, Map<String, dynamic>> usedSchemes,
  ) {
    switch (auth.type) {
      case AuthType.none:
      case AuthType.inherit:
        return null;
      case AuthType.bearer:
        usedSchemes['bearerAuth'] = {'type': 'http', 'scheme': 'bearer'};
        return [
          {'bearerAuth': <dynamic>[]},
        ];
      case AuthType.basic:
        usedSchemes['basicAuth'] = {'type': 'http', 'scheme': 'basic'};
        return [
          {'basicAuth': <dynamic>[]},
        ];
      case AuthType.apiKey:
        usedSchemes['apiKeyAuth'] = {
          'type': 'apiKey',
          'in': auth.apiKeyLocation == ApiKeyLocation.query
              ? 'query'
              : 'header',
          'name': auth.apiKeyName,
        };
        return [
          {'apiKeyAuth': <dynamic>[]},
        ];
    }
  }
}
