/// Case-insensitive helpers for HTTP header maps.
///
/// HTTP header names are case-insensitive, but a `Map<String, String>` is not —
/// so we never want to emit both `Content-Type` and `content-type`, and a
/// "is this header set?" check must ignore case. Shared by the send-path
/// serializer and the code-gen service, which previously each kept a verbatim
/// private copy of these. Pure — no dependencies.
class HeaderUtils {
  HeaderUtils._();

  /// True when a header whose name case-insensitively equals [name] is present.
  static bool hasHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    return headers.keys.any((k) => k.toLowerCase() == lower);
  }

  /// Sets [name] to [value], dropping any case-variant of the key first so we
  /// never emit two spellings of the same header.
  static void setHeader(Map<String, String> headers, String name, String value) {
    removeHeader(headers, name);
    headers[name] = value;
  }

  /// Removes every case-variant of [name] from [headers].
  static void removeHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    headers.removeWhere((k, _) => k.toLowerCase() == lower);
  }

  /// True when a Content-Type is present that isn't the app's JSON default —
  /// i.e. the user deliberately chose one (which a binary body should keep).
  static bool hasCustomContentType(Map<String, String> headers) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'content-type') {
        return e.value.trim().toLowerCase() != 'application/json';
      }
    }
    return false;
  }
}
