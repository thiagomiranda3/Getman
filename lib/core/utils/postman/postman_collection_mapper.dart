// Bidirectional Postman v2.1 collection mapper: toJson serializes a
// CollectionNodeEntity subtree to Postman collection JSON (a folder root's
// children become top-level items; a leaf root is wrapped as the single
// item); fromJson deserializes Postman JSON back into a Getman folder tree.
// Backs the collections import/export UI.
//
// Gotchas: collection-/folder-scoped variables mask secret values on export
// (empty value, `type:'secret'`) via _variablesToPostman — never emit the
// real secret. Saved examples (CollectionNodeEntity.examples) are local-only
// and this mapper never reads that field, so they're excluded from export.
// Query-string handling is asymmetric by design: export always derives
// `url.query` from the raw URL's still-percent-encoded segments (matching
// Postman's own convention); import prefers a structured `url.query` when
// present (percent-decoded before merging back in, else double-encoding
// results), otherwise keeps the raw URL's query as-is.

import 'dart:convert';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/url_query_utils.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:uuid/uuid.dart';

class PostmanCollectionMapper {
  static const String _schemaV21 =
      'https://schema.getpostman.com/json/collection/v2.1.0/collection.json';
  static const Uuid _uuid = Uuid();

  /// Encodes a Getman collection node as a Postman v2.1 collection JSON string.
  ///
  /// If [rootNode] is a folder, its children become top-level `item` entries.
  /// If [rootNode] is a request leaf, it is wrapped as the single item.
  static String toJson(CollectionNodeEntity rootNode) {
    final items = rootNode.isFolder
        ? rootNode.children.map(_nodeToItem).toList()
        : [_nodeToItem(rootNode)];
    // A leaf root's own description is already carried on its wrapping item
    // (see _nodeToItem) — info.description only applies to a folder root.
    final rootDescription = rootNode.description;
    final collection = <String, dynamic>{
      'info': {
        '_postman_id': _uuid.v4(),
        'name': rootNode.name,
        'schema': _schemaV21,
        '_exporter_id': 'getman',
        if (rootNode.isFolder &&
            rootDescription != null &&
            rootDescription.isNotEmpty)
          'description': rootDescription,
      },
      'item': items,
    };
    if (rootNode.isFolder && rootNode.variables.isNotEmpty) {
      collection['variable'] = _variablesToPostman(
        rootNode.variables,
        rootNode.secretKeys,
      );
    }
    return const JsonEncoder.withIndent('  ').convert(collection);
  }

  /// Decodes a Postman v2.1 collection JSON string into a Getman folder whose
  /// name is the collection's `info.name` and whose children mirror the
  /// Postman `item` tree.
  ///
  /// Throws [FormatException] on invalid JSON or when `info.schema` is missing
  /// or not a v2.1 schema.
  static CollectionNodeEntity fromJson(String source) {
    final dynamic parsed;
    try {
      parsed = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Invalid JSON: ${e.message}');
    }
    if (parsed is! Map) {
      throw const FormatException('Expected a JSON object at the root.');
    }
    final info = parsed['info'];
    if (info is! Map) {
      throw const FormatException(
        'Missing "info" object — not a Postman collection.',
      );
    }
    final schema = info['schema'];
    if (schema is! String || !schema.contains('v2.1')) {
      throw const FormatException(
        'Unsupported collection schema — expected Postman v2.1.',
      );
    }
    final name = (info['name'] as String?) ?? 'Imported Collection';
    final rawItems = parsed['item'];
    final items = rawItems is List ? rawItems : const <dynamic>[];
    final children = items
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => _itemToNode(m.cast<String, dynamic>()))
        .toList();
    final vars = _variablesFromPostman(parsed['variable']);
    return CollectionNodeEntity(
      id: _uuid.v4(),
      name: name,
      description: _parseDescription(info['description']),
      children: children,
      variables: vars.variables,
      secretKeys: vars.secretKeys,
    );
  }

  // ---------- export helpers ----------

  static List<Map<String, dynamic>> _variablesToPostman(
    Map<String, String> variables,
    Set<String> secretKeys,
  ) {
    return [
      for (final e in variables.entries)
        if (secretKeys.contains(e.key))
          {'key': e.key, 'value': '', 'type': 'secret'}
        else
          {'key': e.key, 'value': e.value, 'type': 'default'},
    ];
  }

  static Map<String, dynamic> _nodeToItem(CollectionNodeEntity node) {
    final description = node.description;
    if (node.isFolder) {
      final item = <String, dynamic>{
        'name': node.name,
        if (description != null && description.isNotEmpty)
          'description': description,
        'item': node.children.map(_nodeToItem).toList(),
      };
      if (node.variables.isNotEmpty) {
        item['variable'] = _variablesToPostman(node.variables, node.secretKeys);
      }
      return item;
    }
    return {
      'name': node.name,
      if (description != null && description.isNotEmpty)
        'description': description,
      'request': _configToRequest(node.config),
    };
  }

  /// Splits the URL's query string into raw (still percent-encoded) key/value
  /// segments — mirrors `url.raw`, matching Postman's own convention that
  /// `url.query` entries are NOT decoded (see `_parseQueryList` below). Using
  /// the decoded [QueryParamEntity] list here would double-encode on import
  /// (`%2520` would round-trip through a decode step on each side).
  static List<Map<String, String>> _rawQuery(String url) {
    final hashIndex = url.indexOf('#');
    var qIndex = url.indexOf('?');
    if (hashIndex != -1 && qIndex > hashIndex) qIndex = -1;
    if (qIndex == -1) return const [];
    final afterQ = url.substring(qIndex + 1);
    final hIndex = afterQ.indexOf('#');
    final queryStr = hIndex == -1 ? afterQ : afterQ.substring(0, hIndex);
    if (queryStr.isEmpty) return const [];
    final result = <Map<String, String>>[];
    for (final pair in queryStr.split('&')) {
      if (pair.isEmpty) continue;
      final eqIndex = pair.indexOf('=');
      final key = eqIndex == -1 ? pair : pair.substring(0, eqIndex);
      if (key.isEmpty) continue;
      final value = eqIndex == -1 ? '' : pair.substring(eqIndex + 1);
      result.add({'key': key, 'value': value});
    }
    return result;
  }

  static Map<String, dynamic> _configToRequest(
    HttpRequestConfigEntity? config,
  ) {
    if (config == null) {
      return {
        'method': 'GET',
        'header': <Map<String, dynamic>>[],
        'url': {'raw': ''},
      };
    }
    final headers = config.headers.entries
        .map((e) => {'key': e.key, 'value': e.value, 'type': 'text'})
        .toList();
    final urlObj = <String, dynamic>{'raw': config.url};
    // Emit the structured `query` array so Postman's UI renders rows.
    // Derived from the URL's raw query segments — duplicates preserved.
    final query = _rawQuery(config.url);
    if (query.isNotEmpty) {
      urlObj['query'] = query;
    }
    final result = <String, dynamic>{
      'method': config.method,
      'header': headers,
      'url': urlObj,
    };
    final auth = _authToPostman(config.authConfig);
    if (auth != null) result['auth'] = auth;
    final body = _configToBody(config);
    if (body != null) result['body'] = body;
    return result;
  }

  /// Maps the request's auth to a Postman `auth` block. `none` and `inherit`
  /// emit nothing — in Postman, no auth block means "inherit from parent",
  /// which is the closest match for both.
  static Map<String, dynamic>? _authToPostman(AuthConfig auth) {
    switch (auth.type) {
      case AuthType.none:
      case AuthType.inherit:
        return null;
      case AuthType.bearer:
        return {
          'type': 'bearer',
          'bearer': [
            {'key': 'token', 'value': auth.token, 'type': 'string'},
          ],
        };
      case AuthType.basic:
        return {
          'type': 'basic',
          'basic': [
            {'key': 'username', 'value': auth.username, 'type': 'string'},
            {'key': 'password', 'value': auth.password, 'type': 'string'},
          ],
        };
      case AuthType.apiKey:
        return {
          'type': 'apikey',
          'apikey': [
            {'key': 'key', 'value': auth.apiKeyName, 'type': 'string'},
            {'key': 'value', 'value': auth.apiKeyValue, 'type': 'string'},
            {'key': 'in', 'value': auth.apiKeyLocation.wire, 'type': 'string'},
          ],
        };
    }
  }

  /// Maps the request's body type to a Postman `body` block. Returns null when
  /// there's nothing to emit (no body / empty raw / empty file path). Form rows
  /// with an empty key are skipped, matching the send pipeline and the import
  /// side (which skips empty keys too).
  static Map<String, dynamic>? _configToBody(HttpRequestConfigEntity config) {
    switch (config.bodyType) {
      case BodyType.none:
        return null;
      case BodyType.raw:
        if (config.body.isEmpty) return null;
        final isJson = config.headers.entries.any(
          (e) =>
              e.key.toLowerCase() == 'content-type' &&
              e.value.toLowerCase().contains('json'),
        );
        return {
          'mode': 'raw',
          'raw': config.body,
          if (isJson)
            'options': {
              'raw': {'language': 'json'},
            },
        };
      case BodyType.urlencoded:
        return {
          'mode': 'urlencoded',
          'urlencoded': [
            for (final f in config.formFields)
              if (!f.isFile && f.name.isNotEmpty)
                {'key': f.name, 'value': f.value},
          ],
        };
      case BodyType.multipart:
        return {
          'mode': 'formdata',
          'formdata': [
            for (final f in config.formFields)
              if (f.name.isNotEmpty)
                if (f.isFile)
                  {'key': f.name, 'type': 'file', 'src': f.filePath ?? ''}
                else
                  {'key': f.name, 'type': 'text', 'value': f.value},
          ],
        };
      case BodyType.binary:
        final path = config.bodyFilePath;
        if (path == null || path.isEmpty) return null;
        return {
          'mode': 'file',
          'file': {'src': path},
        };
      case BodyType.graphql:
        return {
          'mode': 'graphql',
          'graphql': {
            'query': config.body,
            'variables': config.graphqlVariables,
          },
        };
    }
  }

  // ---------- import helpers ----------

  static ({Map<String, String> variables, Set<String> secretKeys})
  _variablesFromPostman(dynamic raw) {
    final variables = <String, String>{};
    final secretKeys = <String>{};
    if (raw is List) {
      for (final entry in raw.whereType<Map<dynamic, dynamic>>()) {
        if (entry['disabled'] == true) continue;
        final key = entry['key'];
        if (key is! String || key.isEmpty) continue;
        final value = entry['value'];
        variables[key] = value is String ? value : (value?.toString() ?? '');
        if (entry['type'] == 'secret') secretKeys.add(key);
      }
    }
    return (variables: variables, secretKeys: secretKeys);
  }

  static CollectionNodeEntity _itemToNode(Map<String, dynamic> item) {
    final name = (item['name'] as String?) ?? 'Untitled';
    final nestedItems = item['item'];
    if (nestedItems is List) {
      final children = nestedItems
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => _itemToNode(m.cast<String, dynamic>()))
          .toList();
      final vars = _variablesFromPostman(item['variable']);
      return CollectionNodeEntity(
        id: _uuid.v4(),
        name: name,
        description: _parseDescription(item['description']),
        children: children,
        variables: vars.variables,
        secretKeys: vars.secretKeys,
      );
    }
    final request = item['request'];
    final config = request is Map
        ? _requestToConfig(request.cast<String, dynamic>())
        : HttpRequestConfigEntity(id: _uuid.v4());
    return CollectionNodeEntity(
      id: _uuid.v4(),
      name: name,
      isFolder: false,
      description:
          _parseDescription(item['description']) ??
          (request is Map ? _parseDescription(request['description']) : null),
      config: config,
    );
  }

  /// Postman descriptions are either a plain string or `{content, type}`.
  static String? _parseDescription(dynamic description) {
    if (description is String && description.isNotEmpty) return description;
    if (description is Map) {
      final content = description['content'];
      if (content is String && content.isNotEmpty) return content;
    }
    return null;
  }

  static HttpRequestConfigEntity _requestToConfig(
    Map<String, dynamic> request,
  ) {
    final method = (request['method'] as String?)?.toUpperCase() ?? 'GET';
    final rawUrl = _parseUrl(request['url']);
    final structuredQuery = _parseQueryList(request['url']);
    // If Postman gave us a structured query block, it wins — merge into the
    // raw URL's query portion. Otherwise keep raw as-is.
    final mergedUrl = structuredQuery == null
        ? rawUrl
        : UrlQueryUtils.replaceQuery(rawUrl, structuredQuery);
    final headers = _parseHeaders(request['header']);
    final body = _parseBody(request['body']);
    return HttpRequestConfigEntity(
      id: _uuid.v4(),
      method: method,
      url: mergedUrl,
      headers: headers,
      auth: _parseAuth(request['auth']),
      body: body.body,
      bodyType: body.bodyType,
      formFields: body.formFields,
      bodyFilePath: body.bodyFilePath,
      graphqlVariables: body.graphqlVariables,
    );
  }

  /// Inverse of [_authToPostman]. Unknown/absent types (incl. Postman's
  /// `noauth`) map to the empty map (= [AuthType.none]).
  static Map<String, String> _parseAuth(dynamic auth) {
    if (auth is! Map) return const {};
    String param(String section, String key) {
      final list = auth[section];
      if (list is! List) return '';
      for (final entry in list.whereType<Map<dynamic, dynamic>>()) {
        if (entry['key'] == key) {
          final value = entry['value'];
          return value is String ? value : (value?.toString() ?? '');
        }
      }
      return '';
    }

    switch (auth['type']) {
      case 'bearer':
        return AuthConfig(
          type: AuthType.bearer,
          token: param('bearer', 'token'),
        ).toMap();
      case 'basic':
        return AuthConfig(
          type: AuthType.basic,
          username: param('basic', 'username'),
          password: param('basic', 'password'),
        ).toMap();
      case 'apikey':
        return AuthConfig(
          type: AuthType.apiKey,
          apiKeyName: param('apikey', 'key'),
          apiKeyValue: param('apikey', 'value'),
          apiKeyLocation: ApiKeyLocation.fromWire(param('apikey', 'in')),
        ).toMap();
      default:
        return const {};
    }
  }

  static String _parseUrl(dynamic url) {
    if (url is String) return url;
    if (url is Map) {
      final raw = url['raw'];
      if (raw is String) return raw;
      final host = url['host'];
      final path = url['path'];
      final hostStr = host is List
          ? host.join('.')
          : (host is String ? host : '');
      final pathStr = path is List
          ? path.join('/')
          : (path is String ? path : '');
      if (hostStr.isEmpty && pathStr.isEmpty) return '';
      final pathPart = pathStr.isNotEmpty ? '/$pathStr' : '';
      if (hostStr.isEmpty) return pathPart;
      // Postman keeps protocol/port separate from host; rebuild a sendable URL
      // (default https) instead of dropping the scheme and producing a
      // schemeless, unsendable string.
      final protocol = url['protocol'];
      final scheme = (protocol is String && protocol.isNotEmpty)
          ? protocol
          : 'https';
      final portRaw = url['port'];
      final port = (portRaw == null || (portRaw is String && portRaw.isEmpty))
          ? ''
          : ':$portRaw';
      return '$scheme://$hostStr$port$pathPart';
    }
    return '';
  }

  /// Returns null when the Postman payload did not include a structured
  /// `url.query` array at all (caller should keep the raw URL's query intact).
  /// Returns an empty list when `url.query` was present but empty or fully
  /// disabled (caller should clear the raw URL's query).
  static List<QueryParamEntity>? _parseQueryList(dynamic url) {
    if (url is! Map) return null;
    final query = url['query'];
    if (query is! List) return null;
    final result = <QueryParamEntity>[];
    for (final entry in query.whereType<Map<dynamic, dynamic>>()) {
      if (entry['disabled'] == true) continue;
      final key = entry['key'];
      final value = entry['value'];
      if (key is! String || key.isEmpty) continue;
      // Postman's structured entries carry the query as it appears in
      // `url.raw`, i.e. still percent-encoded — decode before handing them to
      // replaceQuery (which encodes), or `hello%20world` arrives as
      // `hello%2520world` and the request sends a literal `%20`.
      result.add(
        QueryParamEntity(
          key: _decodeQueryPart(key),
          value: _decodeQueryPart(
            value is String ? value : (value?.toString() ?? ''),
          ),
        ),
      );
    }
    return result;
  }

  /// Percent-decodes a structured query key/value; malformed sequences (a
  /// literal `%` outside an escape) are kept verbatim.
  static String _decodeQueryPart(String s) {
    try {
      return Uri.decodeComponent(s);
    } on Object catch (_) {
      return s;
    }
  }

  static Map<String, String> _parseHeaders(dynamic header) {
    if (header is! List) return {};
    final result = <String, String>{};
    for (final entry in header.whereType<Map<dynamic, dynamic>>()) {
      if (entry['disabled'] == true) continue;
      final key = entry['key'];
      final value = entry['value'];
      if (key is! String || key.isEmpty) continue;
      result[key] = value is String ? value : (value?.toString() ?? '');
    }
    return result;
  }

  /// Reconstructs the body fields from a Postman `body` block. Mirrors the
  /// export side: raw → raw body; urlencoded/formdata → form rows + body type;
  /// file → binary path. Anything unrecognized falls back to an empty raw body.
  static ({
    BodyType bodyType,
    String body,
    String graphqlVariables,
    List<MultipartFieldEntity> formFields,
    String? bodyFilePath,
  })
  _parseBody(dynamic body) {
    if (body is Map) {
      switch (body['mode']) {
        case 'raw':
          final raw = body['raw'];
          return (
            bodyType: BodyType.raw,
            body: raw is String ? raw : '',
            graphqlVariables: '',
            formFields: const [],
            bodyFilePath: null,
          );
        case 'urlencoded':
          return (
            bodyType: BodyType.urlencoded,
            body: '',
            graphqlVariables: '',
            formFields: _parseFormList(body['urlencoded'], multipart: false),
            bodyFilePath: null,
          );
        case 'formdata':
          return (
            bodyType: BodyType.multipart,
            body: '',
            graphqlVariables: '',
            formFields: _parseFormList(body['formdata'], multipart: true),
            bodyFilePath: null,
          );
        case 'file':
          final file = body['file'];
          final src = file is Map ? file['src'] : null;
          return (
            bodyType: BodyType.binary,
            body: '',
            graphqlVariables: '',
            formFields: const [],
            bodyFilePath: src is String && src.isNotEmpty ? src : null,
          );
        case 'graphql':
          final gql = body['graphql'];
          final query = gql is Map ? gql['query'] : null;
          final vars = gql is Map ? gql['variables'] : null;
          return (
            bodyType: BodyType.graphql,
            body: query is String ? query : '',
            graphqlVariables: vars is String ? vars : '',
            formFields: const [],
            bodyFilePath: null,
          );
      }
    }
    return (
      bodyType: BodyType.raw,
      body: '',
      graphqlVariables: '',
      formFields: const [],
      bodyFilePath: null,
    );
  }

  /// Parses a Postman `urlencoded` / `formdata` array into form rows. Disabled
  /// and empty-key entries are skipped (matching headers/query parsing). For
  /// multipart, `type:'file'` rows become file rows carrying `src` as the path.
  static List<MultipartFieldEntity> _parseFormList(
    dynamic list, {
    required bool multipart,
  }) {
    if (list is! List) return const [];
    final result = <MultipartFieldEntity>[];
    for (final entry in list.whereType<Map<dynamic, dynamic>>()) {
      if (entry['disabled'] == true) continue;
      final key = entry['key'];
      if (key is! String || key.isEmpty) continue;
      if (multipart && entry['type'] == 'file') {
        final src = entry['src'];
        result.add(
          MultipartFieldEntity(
            name: key,
            isFile: true,
            filePath: src is String ? src : null,
          ),
        );
      } else {
        final value = entry['value'];
        result.add(
          MultipartFieldEntity(
            name: key,
            value: value is String ? value : (value?.toString() ?? ''),
          ),
        );
      }
    }
    return result;
  }
}
