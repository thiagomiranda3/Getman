// lib/core/utils/apidoc/collection_to_api_doc.dart
import 'package:getman/core/utils/apidoc/api_doc.dart';
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
      // headerParams / requestBody / responses / security: Tasks 4 & 5.
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
