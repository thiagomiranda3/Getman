// Hive model (typeId 1, box: history; also embedded in collection nodes) for
// a stored HTTP request + its captured response columns. `==`/`hashCode`
// DELIBERATELY exclude `id` and the response fields so history dedup works on
// request signature (method/url/body plus the body-shape fields bodyType/
// graphqlVariables/bodyFilePath/formFields) — do not re-include `id` without
// a discussion (see docs/architecture/settings-history-updates.md). Also
// carries a lazy one-time migration of legacy `params` map entries into the
// URL's query string (see toEntity).

import 'package:collection/collection.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/utils/url_query_utils.dart';
import 'package:getman/features/tabs/data/models/multipart_field_model.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

part 'request_config_model.g.dart';

@HiveType(typeId: 1)
class HttpRequestConfig extends HiveObject {
  HttpRequestConfig({
    String? id,
    this.method = 'GET',
    this.url = '',
    Map<String, String>? headers,
    Map<String, String>? params,
    this.body = '',
    Map<String, String>? auth,
    this.bodyType = 'raw',
    List<MultipartFieldModel>? formFields,
    this.bodyFilePath,
    this.graphqlVariables = '',
    this.kind = 0,
    this.responseBody,
    this.responseHeaders,
    this.statusCode,
    this.durationMs,
  }) : id = id ?? const Uuid().v4(),
       headers =
           headers ??
           {
             'Content-Type': 'application/json',
             'Accept': '*/*',
           },
       params = params ?? {},
       auth = auth ?? {},
       formFields = formFields ?? [];

  factory HttpRequestConfig.fromEntity(HttpRequestConfigEntity entity) =>
      HttpRequestConfig(
        id: entity.id,
        method: entity.method,
        url: entity.url,
        headers: entity.headers,
        // URL carries the query now; stored params stays empty going forward.
        params: const {},
        body: entity.body,
        auth: entity.auth,
        bodyType: entity.bodyType.wire,
        formFields: entity.formFields
            .map(MultipartFieldModel.fromEntity)
            .toList(),
        bodyFilePath: entity.bodyFilePath,
        graphqlVariables: entity.graphqlVariables,
        kind: entity.kind.wire,
        responseBody: entity.responseBody,
        responseHeaders: entity.responseHeaders,
        statusCode: entity.statusCode,
        durationMs: entity.durationMs,
      );
  @HiveField(0)
  String id;

  @HiveField(1, defaultValue: 'GET')
  String method;

  @HiveField(2, defaultValue: '')
  String url;

  @HiveField(3)
  Map<String, String> headers;

  // Legacy field retained for backward compat with pre-migration Hive data.
  // New records always write an empty map here; queries live inside [url].
  // See toEntity() for the one-time lazy migration.
  @HiveField(4)
  Map<String, String> params;

  @HiveField(5, defaultValue: '')
  String body;

  @HiveField(6)
  Map<String, String> auth;

  @HiveField(7)
  String? responseBody;

  @HiveField(8)
  Map<String, String>? responseHeaders;

  @HiveField(9)
  int? statusCode;

  @HiveField(10)
  int? durationMs;

  // Body-type fields (added after auth/response). Safe defaults mean records
  // persisted before this migration read back as a raw body with no form
  // fields — exactly today's behavior.
  @HiveField(11, defaultValue: 'raw')
  String bodyType;

  @HiveField(12)
  List<MultipartFieldModel> formFields;

  @HiveField(13)
  String? bodyFilePath;

  @HiveField(14, defaultValue: 0)
  int kind;

  @HiveField(15, defaultValue: '')
  String graphqlVariables;

  HttpRequestConfigEntity toEntity() {
    // Lazy migration: if a legacy record stored params in the separate map,
    // merge them into the URL's query string. Next save writes params back
    // as empty — this runs at most once per record.
    var entityUrl = url;
    if (params.isNotEmpty) {
      final legacy = params.entries
          .map((e) => QueryParamEntity(key: e.key, value: e.value))
          .toList(growable: false);
      entityUrl = UrlQueryUtils.replaceQuery(url, legacy);
    }
    return HttpRequestConfigEntity(
      id: id,
      method: method,
      url: entityUrl,
      headers: headers,
      body: body,
      auth: auth,
      bodyType: BodyType.fromWire(bodyType),
      formFields: formFields.map((f) => f.toEntity()).toList(),
      bodyFilePath: bodyFilePath,
      graphqlVariables: graphqlVariables,
      kind: RequestKind.fromWire(kind),
      responseBody: responseBody,
      responseHeaders: responseHeaders,
      statusCode: statusCode,
      durationMs: durationMs,
    );
  }

  // Deep value-equality for the form-body rows. The Hive models
  // (MultipartFieldModel) use identity equality, so we compare their Equatable
  // entity projections — consistent with the ListEquality<MultipartFieldEntity>
  // used in the form editor.
  static const ListEquality<MultipartFieldEntity> _formFieldEquality =
      ListEquality<MultipartFieldEntity>();

  List<MultipartFieldEntity> get _formFieldSignature =>
      formFields.map((f) => f.toEntity()).toList(growable: false);

  // Equality deliberately considers only the request signature — never `id` or
  // the response fields. It spans everything that shapes the outgoing request:
  // method, url (which now carries the query, so ?a=1 differs from ?a=2), body,
  // and the body-shape fields (bodyType / graphqlVariables / bodyFilePath /
  // formFields). Without the body-shape fields, distinct GraphQL/binary/
  // multipart sends that share method+url+body would wrongly dedup. `kind`
  // (HTTP vs WS/SSE) is intentionally excluded. See
  // docs/architecture/settings-history-updates.md.
  @override
  // Signature-only equality is intentional for history dedup; a HiveObject is
  // inherently mutable so it can't be @immutable.
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HttpRequestConfig &&
        other.method == method &&
        other.url == url &&
        other.body == body &&
        other.bodyType == bodyType &&
        other.graphqlVariables == graphqlVariables &&
        other.bodyFilePath == bodyFilePath &&
        _formFieldEquality.equals(
          other._formFieldSignature,
          _formFieldSignature,
        );
  }

  @override
  // Signature-only equality is intentional for history dedup; a HiveObject is
  // inherently mutable so it can't be @immutable.
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => Object.hash(
    method,
    url,
    body,
    bodyType,
    graphqlVariables,
    bodyFilePath,
    _formFieldEquality.hash(_formFieldSignature),
  );
}
