import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

/// Pure JSON shaping for the on-disk workspace format. The directory layout and
/// I/O live in the data source; this only encodes/decodes individual nodes.
///
/// A request file is a **curated projection** of the entity that deliberately
/// OMITS the response cache fields (responseBody/headers/statusCode/durationMs)
/// — they would leak response data into git and create churny diffs. On read
/// they default to null, exactly like a freshly-imported request.
///
/// Saved examples are likewise OMITTED: they carry captured responses (same
/// leak/churn concern) and are a local convenience, not a git-tracked artifact.
/// `requestFromJson` therefore reconstructs leaves with no examples.
class WorkspaceCollectionSerializer {
  WorkspaceCollectionSerializer._();

  static const int version = 1;

  // ---- request leaf ----

  static Map<String, dynamic> requestToJson(CollectionNodeEntity leaf) {
    final c = leaf.config ?? HttpRequestConfigEntity(id: leaf.id);
    return {
      'id': leaf.id,
      'name': leaf.name,
      'isFavorite': leaf.isFavorite,
      'request': _configToJson(c),
    };
  }

  static CollectionNodeEntity requestFromJson(Map<String, dynamic> json) {
    final request =
        (json['request'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CollectionNodeEntity(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Request',
      isFolder: false,
      isFavorite: json['isFavorite'] == true,
      config: _configFromJson(request),
    );
  }

  // ---- folder ----

  static Map<String, dynamic> folderToJson(
    CollectionNodeEntity folder,
    List<String> childOrder,
  ) {
    return {
      'id': folder.id,
      'name': folder.name,
      'isFavorite': folder.isFavorite,
      'childOrder': childOrder,
    };
  }

  static CollectionNodeEntity folderFromJson(
    Map<String, dynamic> json,
    List<CollectionNodeEntity> children,
  ) {
    return CollectionNodeEntity(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Folder',
      isFavorite: json['isFavorite'] == true,
      children: children,
    );
  }

  static List<String> childOrder(Map<String, dynamic> folderJson) =>
      ((folderJson['childOrder'] as List?) ?? const []).cast<String>();

  // ---- workspace manifest ----

  static Map<String, dynamic> manifestToJson(List<String> rootOrder) => {
    'version': version,
    'rootOrder': rootOrder,
  };

  static List<String> rootOrder(Map<String, dynamic> manifest) =>
      ((manifest['rootOrder'] as List?) ?? const []).cast<String>();

  // ---- config (response fields omitted) ----

  static Map<String, dynamic> _configToJson(HttpRequestConfigEntity c) => {
    'id': c.id,
    'method': c.method,
    'url': c.url,
    'headers': c.headers,
    'body': c.body,
    'bodyType': c.bodyType.wire,
    'auth': c.auth,
    if (c.formFields.isNotEmpty)
      'formFields': [
        for (final f in c.formFields)
          {
            'name': f.name,
            'value': f.value,
            'isFile': f.isFile,
            if (f.filePath != null) 'filePath': f.filePath,
            if (f.contentType != null) 'contentType': f.contentType,
          },
      ],
    if (c.bodyFilePath != null) 'bodyFilePath': c.bodyFilePath,
  };

  static HttpRequestConfigEntity _configFromJson(Map<String, dynamic> json) {
    return HttpRequestConfigEntity(
      id: (json['id'] as String?) ?? '',
      method: (json['method'] as String?) ?? 'GET',
      url: (json['url'] as String?) ?? '',
      headers: ((json['headers'] as Map?) ?? const {}).cast<String, String>(),
      body: (json['body'] as String?) ?? '',
      bodyType: BodyType.fromWire(json['bodyType'] as String?),
      auth: ((json['auth'] as Map?) ?? const {}).cast<String, String>(),
      formFields: [
        for (final Map<String, dynamic> m
            in ((json['formFields'] as List?) ?? const [])
                .cast<Map<String, dynamic>>())
          MultipartFieldEntity(
            name: (m['name'] as String?) ?? '',
            value: (m['value'] as String?) ?? '',
            isFile: m['isFile'] == true,
            filePath: m['filePath'] as String?,
            contentType: m['contentType'] as String?,
          ),
      ],
      bodyFilePath: json['bodyFilePath'] as String?,
      // response cache fields intentionally not persisted → null on read.
    );
  }
}
