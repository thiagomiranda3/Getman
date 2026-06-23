// lib/core/utils/apidoc/collection_to_api_doc.dart
import 'dart:convert';

import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';
import 'package:getman/core/utils/apidoc/json_schema.dart';
import 'package:getman/core/utils/url_query_utils.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

/// Builds a format-agnostic [ApiDoc] from a collection subtree. The reverse of
/// the OpenAPI import: leaves → operations, folders → tags, request URLs →
/// servers + templated paths. Bodies/responses/auth are filled in by the
/// body/response/auth helpers (added in later tasks). Pure Dart.
class CollectionToApiDoc {
  CollectionToApiDoc._();

  static final RegExp _leadingVar = RegExp(
    r'^\{\{\s*([A-Za-z0-9_\-\.]+)\s*\}\}',
  );
  static final RegExp _origin = RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+');
  static final RegExp _pathVar = RegExp(r'\{\{\s*([A-Za-z0-9_\-\.]+)\s*\}\}');

  static ApiDoc build(CollectionNodeEntity root, {EnvironmentEntity? env}) {
    final warnings = <String>[];
    final servers = <String, ApiServer>{}; // url → server (dedup)
    final operations = <ApiOperation>[];

    void walk(CollectionNodeEntity node, List<String> folderPath) {
      for (final child in node.children) {
        if (child.isFolder) {
          walk(child, [...folderPath, child.name]);
        } else if (child.config != null) {
          operations.add(
            _operation(child, folderPath, env, servers, warnings),
          );
        }
      }
    }

    walk(root, const []);

    return ApiDoc(
      title: root.name,
      servers: servers.values.toList(),
      operations: operations,
      warnings: warnings,
    );
  }

  static ApiOperation _operation(
    CollectionNodeEntity leaf,
    List<String> folderPath,
    EnvironmentEntity? env,
    Map<String, ApiServer> servers,
    List<String> warnings,
  ) {
    final config = leaf.config!;
    final parts = UrlQueryUtils.parse(config.url);

    final queryParams = [
      for (final p in parts.params)
        ApiParam(name: p.key, example: p.value.isEmpty ? null : p.value),
    ];

    final split = _splitServerAndPath(parts.base, config.url, env, warnings);
    servers.putIfAbsent(split.server.url, () => split.server);

    final pathParams = <ApiParam>[];
    final templatedPath = split.path.replaceAllMapped(_pathVar, (m) {
      final name = m.group(1)!.trim();
      pathParams.add(
        ApiParam(
          name: name,
          isRequired: true,
          example: _resolved(name, env),
        ),
      );
      return '{$name}';
    });

    return ApiOperation(
      method: config.method.toUpperCase(),
      path: _ensureLeadingSlash(templatedPath),
      summary: leaf.name,
      description: (leaf.description == null || leaf.description!.isEmpty)
          ? null
          : leaf.description,
      tag: folderPath.isEmpty ? null : folderPath.join(' / '),
      queryParams: queryParams,
      pathParams: pathParams,
      headerParams: _headerParams(config),
      requestBody: _requestBody(leaf, config, warnings),
      // responses / security: Task 5.
    );
  }

  static _ServerPath _splitServerAndPath(
    String base,
    String fullUrl,
    EnvironmentEntity? env,
    List<String> warnings,
  ) {
    final leading = _leadingVar.firstMatch(base);
    if (leading != null) {
      final name = leading.group(1)!.trim();
      final remainder = base.substring(leading.end);
      final value = _resolved(name, env);
      if (value != null && value.isNotEmpty) {
        return _ServerPath(ApiServer(url: value), remainder);
      }
      return _ServerPath(
        ApiServer(url: '{$name}', variables: {name: value ?? ''}),
        remainder,
      );
    }

    final origin = _origin.firstMatch(base);
    if (origin != null) {
      final url = origin.group(0)!;
      return _ServerPath(ApiServer(url: url), base.substring(url.length));
    }

    warnings.add('Could not determine a server URL for "$fullUrl" — used "/".');
    return _ServerPath(const ApiServer(url: '/'), base);
  }

  static List<ApiParam> _headerParams(HttpRequestConfigEntity config) {
    const skip = {'content-type', 'accept'};
    final auth = config.authConfig;
    final apiKeyHeader =
        (auth.type == AuthType.apiKey &&
            auth.apiKeyLocation == ApiKeyLocation.header)
        ? auth.apiKeyName.toLowerCase()
        : null;
    return [
      for (final entry in config.headers.entries)
        if (!skip.contains(entry.key.toLowerCase()) &&
            entry.key.toLowerCase() != apiKeyHeader)
          ApiParam(
            name: entry.key,
            example: entry.value.isEmpty ? null : entry.value,
          ),
    ];
  }

  static ApiBody? _requestBody(
    CollectionNodeEntity leaf,
    HttpRequestConfigEntity config,
    List<String> warnings,
  ) {
    switch (config.bodyType) {
      case BodyType.none:
        return null;
      case BodyType.raw:
        if (config.body.isEmpty) return null;
        try {
          final decoded = jsonDecode(config.body);
          return ApiBody(
            contentType: 'application/json',
            schema: JsonSchemaInferrer.infer(decoded),
            example: decoded,
          );
        } on FormatException {
          warnings.add(
            'Request body for "${leaf.name}" is not valid JSON — '
            'exported as text/plain.',
          );
          return ApiBody(contentType: 'text/plain', example: config.body);
        }
      case BodyType.urlencoded:
        return _formBody(config, 'application/x-www-form-urlencoded');
      case BodyType.multipart:
        return _formBody(config, 'multipart/form-data');
      case BodyType.binary:
        return const ApiBody(
          contentType: 'application/octet-stream',
          schema: JsonSchema(type: 'string', format: 'binary'),
        );
      case BodyType.graphql:
        Object variables = <String, dynamic>{};
        if (config.graphqlVariables.isNotEmpty) {
          try {
            variables = jsonDecode(config.graphqlVariables) as Object;
          } on FormatException {
            variables = <String, dynamic>{};
          }
        }
        return ApiBody(
          contentType: 'application/json',
          schema: const JsonSchema(
            type: 'object',
            properties: {
              'query': JsonSchema(type: 'string'),
              'variables': JsonSchema(type: 'object'),
            },
          ),
          example: {'query': config.body, 'variables': variables},
        );
    }
  }

  static ApiBody _formBody(HttpRequestConfigEntity config, String contentType) {
    final props = <String, JsonSchema>{};
    final example = <String, dynamic>{};
    for (final f in config.formFields) {
      if (f.isFile) {
        props[f.name] = const JsonSchema(type: 'string', format: 'binary');
      } else {
        props[f.name] = const JsonSchema(type: 'string');
        example[f.name] = f.value;
      }
    }
    return ApiBody(
      contentType: contentType,
      schema: JsonSchema(type: 'object', properties: props),
      example: example,
    );
  }

  /// Env value for [name], or null when there's no env, the var is missing, or
  /// the var is secret (secrets are never emitted).
  static String? _resolved(String name, EnvironmentEntity? env) {
    if (env == null) return null;
    if (env.secretKeys.contains(name)) return null;
    return env.variables[name];
  }

  static String _ensureLeadingSlash(String path) {
    if (path.isEmpty) return '/';
    return path.startsWith('/') ? path : '/$path';
  }
}

class _ServerPath {
  const _ServerPath(this.server, this.path);
  final ApiServer server;
  final String path;
}
