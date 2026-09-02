// Content-Type rules per BodyType — the single vocabulary shared by the HEADERS
// tab (defaultContentType / isAutoContentType / syncContentType keep the
// editable Content-Type row in step with the body-type selector), the
// importers (withDefaultContentType materializes the row Postman/curl/OpenAPI
// sources leave implicit), and the wire (applyContentType, used by both the
// send-path RequestSerializer and CodeGenService so the two can't drift).
//
// Gotchas: applyContentType's `raw` rule makes Dio's implied default explicit
// (ImplyContentTypeInterceptor sends application/json for a String body with
// no Content-Type) — callers must only apply it when a body is actually sent
// (non-empty raw), because Dio implies nothing for a null body. Callers also
// own WHEN to apply the binary rule: the serializer only calls this for binary
// after confirming a file exists, while the code generator applies it
// unconditionally (it always shows the header). multipart REMOVES the header
// here so Dio can add the boundary; code-gen re-adds a boundary-less
// `multipart/form-data` for targets whose form encoder tolerates it.

import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/utils/header_utils.dart';

/// Shared Content-Type rules per [BodyType], used by the HEADERS tab, the
/// importers, the send-path serializer and the code generator so none of them
/// can drift on what header a body type implies.
///
/// NOTE: callers own *when* to apply the binary rule. The send-path serializer
/// only invokes this for binary after confirming a file exists, so a binary
/// request with no file stays header-free (matching prior behavior); the code
/// generator applies it unconditionally because it always shows the header.
class BodyTypeUtils {
  BodyTypeUtils._();

  /// Canonical header name used whenever a row is inserted.
  static const String contentTypeHeader = 'Content-Type';

  /// The Content-Type the wire carries for [type] when the user hasn't chosen
  /// one — null for a bodyless request.
  static String? defaultContentType(BodyType type) {
    switch (type) {
      case BodyType.none:
        return null;
      case BodyType.raw:
      case BodyType.graphql:
        return 'application/json';
      case BodyType.urlencoded:
        return 'application/x-www-form-urlencoded';
      case BodyType.multipart:
        return 'multipart/form-data';
      case BodyType.binary:
        return 'application/octet-stream';
    }
  }

  static final Set<String> _autoValues = {
    for (final t in BodyType.values)
      if (defaultContentType(t) != null) defaultContentType(t)!,
  };

  /// True when [value] is one of the app's own defaults (any case, parameters
  /// such as `; charset=utf-8` ignored) — i.e. NOT a type the user chose, so a
  /// body-type switch may rewrite it.
  static bool isAutoContentType(String value) {
    final mime = value.split(';').first.trim().toLowerCase();
    return mime.isNotEmpty && _autoValues.contains(mime);
  }

  /// The HEADERS-tab rule for a body-type switch: returns a NEW map whose
  /// Content-Type row tracks [type] unless the user owns it.
  /// - absent → the default is inserted as the FIRST row;
  /// - auto value → rewritten in place (key spelling + position kept);
  /// - user-chosen (non-auto) value → untouched;
  /// - [BodyType.none] → an auto row is removed, a user-chosen one kept.
  static Map<String, String> syncContentType(
    Map<String, String> headers,
    BodyType type,
  ) {
    final existing = _contentTypeEntry(headers);
    if (existing != null && !isAutoContentType(existing.value)) {
      return Map.of(headers);
    }
    final target = defaultContentType(type);
    if (target == null) {
      if (existing == null) return Map.of(headers);
      return {
        for (final e in headers.entries)
          if (e.key != existing.key) e.key: e.value,
      };
    }
    if (existing != null) {
      return {
        for (final e in headers.entries)
          e.key: e.key == existing.key ? target : e.value,
      };
    }
    return {contentTypeHeader: target, ...headers};
  }

  /// The import rule: adds the default Content-Type row (first) when [headers]
  /// has none, so a request built from a Postman/curl/OpenAPI source shows the
  /// same row a hand-built one does. Never touches an existing row.
  static Map<String, String> withDefaultContentType(
    Map<String, String> headers,
    BodyType type,
  ) {
    final target = defaultContentType(type);
    if (target == null || HeaderUtils.hasHeader(headers, contentTypeHeader)) {
      return Map.of(headers);
    }
    return {contentTypeHeader: target, ...headers};
  }

  /// The wire rule (send path + code-gen), mutating [headers] in place.
  static void applyContentType(Map<String, String> headers, BodyType type) {
    switch (type) {
      case BodyType.raw:
        // Dio's ImplyContentTypeInterceptor sends application/json for a
        // String body with no Content-Type; make that explicit so code-gen
        // mirrors the wire. Only call for a non-empty raw body.
        if (!HeaderUtils.hasHeader(headers, contentTypeHeader)) {
          HeaderUtils.setHeader(headers, contentTypeHeader, 'application/json');
        }
      case BodyType.urlencoded:
        HeaderUtils.setHeader(
          headers,
          contentTypeHeader,
          'application/x-www-form-urlencoded',
        );
      case BodyType.multipart:
        HeaderUtils.removeHeader(headers, contentTypeHeader);
      case BodyType.binary:
        if (!HeaderUtils.hasCustomContentType(headers)) {
          HeaderUtils.setHeader(
            headers,
            contentTypeHeader,
            'application/octet-stream',
          );
        }
      case BodyType.graphql:
        if (!HeaderUtils.hasCustomContentType(headers)) {
          HeaderUtils.setHeader(headers, contentTypeHeader, 'application/json');
        }
      case BodyType.none:
        break;
    }
  }

  static MapEntry<String, String>? _contentTypeEntry(
    Map<String, String> headers,
  ) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'content-type') return e;
    }
    return null;
  }
}
