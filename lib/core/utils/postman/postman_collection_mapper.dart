import 'dart:convert';
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
    final collection = {
      'info': {
        '_postman_id': _uuid.v4(),
        'name': rootNode.name,
        'schema': _schemaV21,
        '_exporter_id': 'getman',
      },
      'item': items,
    };
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
      throw const FormatException('Missing "info" object — not a Postman collection.');
    }
    final schema = info['schema'];
    if (schema is! String || !schema.contains('v2.1')) {
      throw const FormatException('Unsupported collection schema — expected Postman v2.1.');
    }
    final name = (info['name'] as String?) ?? 'Imported Collection';
    final rawItems = parsed['item'];
    final items = rawItems is List ? rawItems : const [];
    final children = items
        .whereType<Map>()
        .map((m) => _itemToNode(m.cast<String, dynamic>()))
        .toList();
    return CollectionNodeEntity(
      id: _uuid.v4(),
      name: name,
      isFolder: true,
      children: children,
    );
  }

  // ---------- export helpers ----------

  static Map<String, dynamic> _nodeToItem(CollectionNodeEntity node) {
    if (node.isFolder) {
      return {
        'name': node.name,
        'item': node.children.map(_nodeToItem).toList(),
      };
    }
    return {
      'name': node.name,
      'request': _configToRequest(node.config),
    };
  }

  static Map<String, dynamic> _configToRequest(HttpRequestConfigEntity? config) {
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
    // Derived from the URL's query portion — duplicates preserved.
    final query = UrlQueryUtils.parseQuery(config.url);
    if (query.isNotEmpty) {
      urlObj['query'] = query
          .map((p) => {'key': p.key, 'value': p.value})
          .toList();
    }
    final result = <String, dynamic>{
      'method': config.method,
      'header': headers,
      'url': urlObj,
    };
    final body = _configToBody(config);
    if (body != null) result['body'] = body;
    return result;
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
        final isJson = config.headers.entries.any((e) =>
            e.key.toLowerCase() == 'content-type' &&
            e.value.toLowerCase().contains('json'));
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
              if (!f.isFile && f.name.isNotEmpty) {'key': f.name, 'value': f.value},
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
    }
  }

  // ---------- import helpers ----------

  static CollectionNodeEntity _itemToNode(Map<String, dynamic> item) {
    final name = (item['name'] as String?) ?? 'Untitled';
    final nestedItems = item['item'];
    if (nestedItems is List) {
      final children = nestedItems
          .whereType<Map>()
          .map((m) => _itemToNode(m.cast<String, dynamic>()))
          .toList();
      return CollectionNodeEntity(
        id: _uuid.v4(),
        name: name,
        isFolder: true,
        children: children,
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
      config: config,
    );
  }

  static HttpRequestConfigEntity _requestToConfig(Map<String, dynamic> request) {
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
      body: body.body,
      bodyType: body.bodyType,
      formFields: body.formFields,
      bodyFilePath: body.bodyFilePath,
    );
  }

  static String _parseUrl(dynamic url) {
    if (url is String) return url;
    if (url is Map) {
      final raw = url['raw'];
      if (raw is String) return raw;
      final host = url['host'];
      final path = url['path'];
      final hostStr = host is List ? host.join('.') : (host is String ? host : '');
      final pathStr = path is List ? path.join('/') : (path is String ? path : '');
      if (hostStr.isEmpty && pathStr.isEmpty) return '';
      final pathPart = pathStr.isNotEmpty ? '/$pathStr' : '';
      if (hostStr.isEmpty) return pathPart;
      // Postman keeps protocol/port separate from host; rebuild a sendable URL
      // (default https) instead of dropping the scheme and producing a
      // schemeless, unsendable string.
      final protocol = url['protocol'];
      final scheme = (protocol is String && protocol.isNotEmpty) ? protocol : 'https';
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
    for (final entry in query.whereType<Map>()) {
      if (entry['disabled'] == true) continue;
      final key = entry['key'];
      final value = entry['value'];
      if (key is! String || key.isEmpty) continue;
      result.add(QueryParamEntity(
        key: key,
        value: value is String ? value : (value?.toString() ?? ''),
      ));
    }
    return result;
  }

  static Map<String, String> _parseHeaders(dynamic header) {
    if (header is! List) return {};
    final result = <String, String>{};
    for (final entry in header.whereType<Map>()) {
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
    List<MultipartFieldEntity> formFields,
    String? bodyFilePath,
  }) _parseBody(dynamic body) {
    if (body is Map) {
      switch (body['mode']) {
        case 'raw':
          final raw = body['raw'];
          return (
            bodyType: BodyType.raw,
            body: raw is String ? raw : '',
            formFields: const [],
            bodyFilePath: null,
          );
        case 'urlencoded':
          return (
            bodyType: BodyType.urlencoded,
            body: '',
            formFields: _parseFormList(body['urlencoded'], multipart: false),
            bodyFilePath: null,
          );
        case 'formdata':
          return (
            bodyType: BodyType.multipart,
            body: '',
            formFields: _parseFormList(body['formdata'], multipart: true),
            bodyFilePath: null,
          );
        case 'file':
          final file = body['file'];
          final src = file is Map ? file['src'] : null;
          return (
            bodyType: BodyType.binary,
            body: '',
            formFields: const [],
            bodyFilePath: src is String && src.isNotEmpty ? src : null,
          );
      }
    }
    return (bodyType: BodyType.raw, body: '', formFields: const [], bodyFilePath: null);
  }

  /// Parses a Postman `urlencoded` / `formdata` array into form rows. Disabled
  /// and empty-key entries are skipped (matching headers/query parsing). For
  /// multipart, `type:'file'` rows become file rows carrying `src` as the path.
  static List<MultipartFieldEntity> _parseFormList(dynamic list, {required bool multipart}) {
    if (list is! List) return const [];
    final result = <MultipartFieldEntity>[];
    for (final entry in list.whereType<Map>()) {
      if (entry['disabled'] == true) continue;
      final key = entry['key'];
      if (key is! String || key.isEmpty) continue;
      if (multipart && entry['type'] == 'file') {
        final src = entry['src'];
        result.add(MultipartFieldEntity(
          name: key,
          isFile: true,
          filePath: src is String ? src : null,
        ));
      } else {
        final value = entry['value'];
        result.add(MultipartFieldEntity(
          name: key,
          value: value is String ? value : (value?.toString() ?? ''),
        ));
      }
    }
    return result;
  }
}
