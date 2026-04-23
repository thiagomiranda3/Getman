import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../domain/entities/request_config_entity.dart';
import '../../../features/collections/domain/entities/collection_node_entity.dart';

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
    if (config.params.isNotEmpty) {
      urlObj['query'] = config.params.entries
          .map((e) => {'key': e.key, 'value': e.value})
          .toList();
    }
    final result = <String, dynamic>{
      'method': config.method,
      'header': headers,
      'url': urlObj,
    };
    if (config.body.isNotEmpty) {
      final isJson = config.headers.entries.any((e) =>
          e.key.toLowerCase() == 'content-type' &&
          e.value.toLowerCase().contains('json'));
      result['body'] = {
        'mode': 'raw',
        'raw': config.body,
        if (isJson)
          'options': {
            'raw': {'language': 'json'},
          },
      };
    }
    return result;
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
    final url = _parseUrl(request['url']);
    final params = _parseQuery(request['url']);
    final headers = _parseHeaders(request['header']);
    final body = _parseBody(request['body']);
    return HttpRequestConfigEntity(
      id: _uuid.v4(),
      method: method,
      url: url,
      headers: headers,
      params: params,
      body: body,
    );
  }

  static String _parseUrl(dynamic url) {
    if (url is String) return url;
    if (url is Map) {
      final raw = url['raw'];
      if (raw is String) return raw;
      final host = url['host'];
      final path = url['path'];
      final hostStr = host is List ? host.join('.') : '';
      final pathStr = path is List ? path.join('/') : '';
      if (hostStr.isEmpty && pathStr.isEmpty) return '';
      return '$hostStr${pathStr.isNotEmpty ? '/$pathStr' : ''}';
    }
    return '';
  }

  static Map<String, String> _parseQuery(dynamic url) {
    if (url is! Map) return {};
    final query = url['query'];
    if (query is! List) return {};
    final result = <String, String>{};
    for (final entry in query.whereType<Map>()) {
      if (entry['disabled'] == true) continue;
      final key = entry['key'];
      final value = entry['value'];
      if (key is! String || key.isEmpty) continue;
      result[key] = value is String ? value : (value?.toString() ?? '');
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

  static String _parseBody(dynamic body) {
    if (body is! Map) return '';
    final mode = body['mode'];
    if (mode == 'raw') {
      final raw = body['raw'];
      return raw is String ? raw : '';
    }
    return '';
  }
}
