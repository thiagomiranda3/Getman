import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/openapi/auth_mapper.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/url_query_utils.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Builds a collection tree + environments from a [NormalizedApi].
ImportResult buildImport(NormalizedApi api) {
  final warnings = <String>[];
  final secretVars = <String>{};

  // Group operations into folders (tag, else first path segment).
  final folders = <String, List<CollectionNodeEntity>>{};
  for (final op in api.operations) {
    warnings.addAll(op.warnings);
    final auth = mapAuth(op.security);
    if (auth.secretVarName != null) secretVars.add(auth.secretVarName!);
    if (auth.warning != null) {
      warnings.add('${op.method} ${op.path}: ${auth.warning}');
    }

    final leaf = CollectionNodeEntity(
      id: _uuid.v4(),
      name: op.name,
      isFolder: false,
      config: _config(op, auth),
    );
    final group = op.tag ?? _firstSegment(op.path);
    folders.putIfAbsent(group, () => []).add(leaf);
  }

  final folderNodes = [
    for (final entry in folders.entries)
      CollectionNodeEntity(
        id: _uuid.v4(),
        name: entry.key,
        children: entry.value,
      ),
  ];

  final root = CollectionNodeEntity(
    id: _uuid.v4(),
    name: api.title,
    children: folderNodes,
  );

  final environments = _environments(api.servers, secretVars);
  return ImportResult(
    root: root,
    environments: environments,
    warnings: warnings,
  );
}

HttpRequestConfigEntity _config(NormalizedOperation op, NormalizedAuth auth) {
  var url = '{{baseUrl}}${_templatePath(op.path)}';
  if (op.queryParams.isNotEmpty) {
    url = UrlQueryUtils.replaceQuery(url, [
      for (final q in op.queryParams)
        QueryParamEntity(key: q.name, value: q.value),
    ]);
  }

  final headers = <String, String>{
    for (final h in op.headerParams) h.name: h.value,
  };
  final body = op.body;
  if (body != null &&
      body.bodyType == BodyType.raw &&
      body.contentType != null) {
    headers['Content-Type'] = body.contentType!;
  }

  return HttpRequestConfigEntity(
    id: _uuid.v4(),
    method: op.method,
    url: url,
    headers: headers,
    body: body?.raw ?? '',
    bodyType: body?.bodyType ?? BodyType.none,
    formFields: body?.formFields ?? const [],
    auth: auth.config.toMap(),
  );
}

/// `/users/{id}` → `/users/{{id}}`.
String _templatePath(String path) =>
    path.replaceAllMapped(RegExp(r'\{([^}/]+)\}'), (m) => '{{${m[1]}}}');

String _firstSegment(String path) {
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? 'default' : parts.first;
}

List<EnvironmentEntity> _environments(
  List<NormalizedServer> servers,
  Set<String> secretVars,
) {
  if (servers.isEmpty) {
    // No servers declared: still create one env so {{baseUrl}} resolves.
    return [
      EnvironmentEntity(
        name: 'Imported',
        variables: {
          'baseUrl': '',
          for (final v in secretVars) v: '',
        },
        secretKeys: {...secretVars},
      ),
    ];
  }
  final usedNames = <String>{};
  return [
    for (final server in servers)
      EnvironmentEntity(
        name: _uniqueName(_serverName(server), usedNames),
        variables: {
          'baseUrl': _concreteBaseUrl(server),
          for (final v in secretVars) v: '',
        },
        secretKeys: {...secretVars},
      ),
  ];
}

/// Substitutes `{var}` server variables with their defaults; trims a trailing
/// slash. See plan "Design decisions locked in" #2.
String _concreteBaseUrl(NormalizedServer server) {
  var url = server.url;
  server.variables.forEach((name, value) {
    url = url.replaceAll('{$name}', value);
  });
  if (url.endsWith('/')) url = url.substring(0, url.length - 1);
  return url;
}

String _serverName(NormalizedServer server) {
  if (server.description != null && server.description!.trim().isNotEmpty) {
    return server.description!.trim();
  }
  final host = Uri.tryParse(_concreteBaseUrl(server))?.host;
  return (host != null && host.isNotEmpty) ? host : 'server';
}

String _uniqueName(String base, Set<String> used) {
  if (used.add(base)) return base;
  var i = 2;
  while (!used.add('$base ($i)')) {
    i++;
  }
  return '$base ($i)';
}
