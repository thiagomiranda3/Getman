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
// Query-string handling: export composes `url.query` via
// ParamRowComposer.compose over the decoded (params, disabledParams) pair —
// the same interleaving logic the params tab editor uses — then
// re-percent-encodes each row's key/value (matching Postman's own
// still-percent-encoded convention; `{{var}}` tokens pass through intact).
// Reusing the composer keeps parked-param display order correct by
// construction, including when two parked params tie on the same rowIndex.
// Import prefers a structured `url.query` when present (percent-decoded
// before merging back in, else double-encoding results), otherwise keeps the
// raw URL's query as-is.
// Disabled rows (B1) map to Postman's native `disabled: true` both ways:
// export marks parked (composer-interleaved) query rows and disabled header
// entries (key in disabledHeaderKeys) with `disabled: true`; import keeps
// disabled headers in the map + set and turns disabled query entries into
// ParkedParamEntity at their array position (previously they were dropped).
// Producer leniency: leaf values (names, method) are coerced via toString,
// never `as`-cast (a numeric name must not abort the whole file import), and
// disabled flags accept the string forms 'true'/'false' via _truthy.
// Getman-only fidelity rides keys inert to real Postman: the `_getman_kind`
// vendor key round-trips RequestKind (WS/SSE/MCP; absent = http), and
// formdata entries carry Postman-native `contentType` both ways.

import 'dart:convert';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/parked_param_entity.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/utils/param_row_composer.dart';
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
    final name = info['name']?.toString() ?? 'Imported Collection';
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
        .map(
          (e) => {
            'key': e.key,
            'value': e.value,
            'type': 'text',
            if (config.disabledHeaderKeys.contains(e.key)) 'disabled': true,
          },
        )
        .toList();
    final urlObj = <String, dynamic>{'raw': config.url};
    // Emit the structured `query` array so Postman's UI renders rows, in
    // display order — built via the same ParamRowComposer the params tab
    // editor uses to interleave enabled params with parked (disabled) ones,
    // so tied rowIndexes come out in their stable sorted order instead of
    // being re-clamped (and reversed) one insertion at a time. Composer input
    // is decoded plaintext; re-encode each row for Postman's still-percent-
    // encoded url.query convention (encodeComponent keeps {{var}} intact).
    final composedRows = ParamRowComposer.compose(
      params: config.params,
      parked: config.disabledParams,
    );
    final query = [
      for (final row in composedRows)
        <String, dynamic>{
          'key': UrlQueryUtils.encodeComponent(row.key),
          'value': UrlQueryUtils.encodeComponent(row.value),
          if (!row.enabled) 'disabled': true,
        },
    ];
    if (query.isNotEmpty) {
      urlObj['query'] = query;
    }
    final result = <String, dynamic>{
      'method': config.method,
      'header': headers,
      'url': urlObj,
      // Vendor key (inert to real Postman): round-trips the protocol so a
      // WS/SSE/MCP request doesn't silently come back as HTTP. Absent = http.
      if (config.kind != RequestKind.http) '_getman_kind': config.kind.name,
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
                  {
                    'key': f.name,
                    'type': 'file',
                    'src': f.filePath ?? '',
                    // Postman v2.1 supports contentType on formdata natively.
                    if (f.contentType != null) 'contentType': f.contentType,
                  }
                else
                  {
                    'key': f.name,
                    'type': 'text',
                    'value': f.value,
                    if (f.contentType != null) 'contentType': f.contentType,
                  },
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

  /// Postman flag values arrive from third-party exporters as booleans OR as
  /// the strings 'true'/'false' — read both shapes, or a disabled row imports
  /// as enabled and gets sent.
  static bool _truthy(dynamic v) => v == true || v == 'true';

  static ({Map<String, String> variables, Set<String> secretKeys})
  _variablesFromPostman(
    dynamic raw,
  ) {
    final variables = <String, String>{};
    final secretKeys = <String>{};
    if (raw is List) {
      for (final entry in raw.whereType<Map<dynamic, dynamic>>()) {
        if (_truthy(entry['disabled'])) continue;
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
    final name = item['name']?.toString() ?? 'Untitled';
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
    // Postman v2.1 also allows the string shorthand `"request": "<url>"`
    // (a bare GET at that URL) — keep the URL instead of importing an empty
    // default config.
    final HttpRequestConfigEntity config;
    if (request is Map) {
      config = _requestToConfig(request.cast<String, dynamic>());
    } else if (request is String) {
      config = HttpRequestConfigEntity(id: _uuid.v4(), url: request);
    } else {
      config = HttpRequestConfigEntity(id: _uuid.v4());
    }
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
    final method = request['method']?.toString().toUpperCase() ?? 'GET';
    final rawUrl = _parseUrl(request['url']);
    final structuredQuery = _parseQueryList(request['url']);
    // If Postman gave us a structured query block, it wins — merge into the
    // raw URL's query portion. Otherwise keep raw as-is.
    final mergedUrl = structuredQuery == null
        ? rawUrl
        : UrlQueryUtils.replaceQuery(rawUrl, structuredQuery.params);
    final headers = _parseHeaders(request['header']);
    final body = _parseBody(request['body']);
    return HttpRequestConfigEntity(
      id: _uuid.v4(),
      method: method,
      url: mergedUrl,
      headers: headers.headers,
      disabledHeaderKeys: headers.disabledKeys,
      disabledParams: structuredQuery?.parked ?? const [],
      auth: _parseAuth(request['auth']),
      body: body.body,
      bodyType: body.bodyType,
      formFields: body.formFields,
      bodyFilePath: body.bodyFilePath,
      graphqlVariables: body.graphqlVariables,
      kind: _parseKind(request['_getman_kind']),
    );
  }

  /// Parses the `_getman_kind` vendor key back into a [RequestKind].
  /// Lenient: absent, non-string, or unknown values all read as HTTP —
  /// real Postman exports never carry the key.
  static RequestKind _parseKind(dynamic raw) {
    if (raw == null) return RequestKind.http;
    final name = raw.toString().toLowerCase();
    for (final kind in RequestKind.values) {
      if (kind.name.toLowerCase() == name) return kind;
    }
    return RequestKind.http;
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
  /// Enabled entries land in `params` (merged back into the URL); entries
  /// marked `disabled: true` land in `parked` carrying their array position
  /// as rowIndex, so the params tab re-interleaves them in place.
  static ({List<QueryParamEntity> params, List<ParkedParamEntity> parked})?
  _parseQueryList(
    dynamic url,
  ) {
    if (url is! Map) return null;
    final query = url['query'];
    if (query is! List) return null;
    final params = <QueryParamEntity>[];
    final parked = <ParkedParamEntity>[];
    var display = 0;
    for (final entry in query.whereType<Map<dynamic, dynamic>>()) {
      final key = entry['key'];
      if (key is! String || key.isEmpty) continue;
      final value = entry['value'];
      // Postman's structured entries carry the query as it appears in
      // `url.raw`, i.e. still percent-encoded — decode before handing them to
      // replaceQuery (which encodes), or `hello%20world` arrives as
      // `hello%2520world` and the request sends a literal `%20`.
      final decodedKey = _decodeQueryPart(key);
      final decodedValue = _decodeQueryPart(
        value is String ? value : (value?.toString() ?? ''),
      );
      if (_truthy(entry['disabled'])) {
        parked.add(
          ParkedParamEntity(
            key: decodedKey,
            value: decodedValue,
            rowIndex: display,
          ),
        );
      } else {
        params.add(QueryParamEntity(key: decodedKey, value: decodedValue));
      }
      display++;
    }
    return (params: params, parked: parked);
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

  /// Headers plus which of them Postman marked `disabled: true` — disabled
  /// entries are KEPT in the map (order preserved) and their keys recorded,
  /// matching Getman's own disabled-header model.
  static ({Map<String, String> headers, Set<String> disabledKeys})
  _parseHeaders(dynamic header) {
    final result = <String, String>{};
    final disabled = <String>{};
    if (header is List) {
      for (final entry in header.whereType<Map<dynamic, dynamic>>()) {
        final key = entry['key'];
        final value = entry['value'];
        if (key is! String || key.isEmpty) continue;
        result[key] = value is String ? value : (value?.toString() ?? '');
        // Later occurrences win the flag too: a common Postman shape parks a
        // disabled variant of a header above the live one — the surviving
        // (last) value must not inherit the earlier row's disabled mark, or
        // the imported header is silently never sent.
        if (_truthy(entry['disabled'])) {
          disabled.add(key);
        } else {
          disabled.remove(key);
        }
      }
    }
    return (headers: result, disabledKeys: disabled);
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
      if (_truthy(entry['disabled'])) continue;
      final key = entry['key'];
      if (key is! String || key.isEmpty) continue;
      // Postman v2.1 formdata entries may carry a per-row contentType.
      final rawContentType = entry['contentType']?.toString();
      final contentType = (rawContentType != null && rawContentType.isNotEmpty)
          ? rawContentType
          : null;
      if (multipart && entry['type'] == 'file') {
        final src = entry['src'];
        result.add(
          MultipartFieldEntity(
            name: key,
            isFile: true,
            filePath: src is String ? src : null,
            contentType: contentType,
          ),
        );
      } else {
        final value = entry['value'];
        result.add(
          MultipartFieldEntity(
            name: key,
            value: value is String ? value : (value?.toString() ?? ''),
            contentType: multipart ? contentType : null,
          ),
        );
      }
    }
    return result;
  }
}
