import 'dart:convert';

import 'package:getman/core/network/http_response.dart';

/// Memoizes the computed size per response instance so a textual body without a
/// `Content-Length` header is UTF-8 measured at most once. Entities are
/// immutable value objects (`copyWithBody` yields a new instance, which
/// correctly misses the cache), so a stale size is impossible. Avoids
/// re-encoding a multi-MB body on every metadata-row rebuild.
final Expando<int> _sizeCache = Expando<int>('responseSizeBytes');

/// Best-effort response size in bytes: prefers [HttpResponseEntity.bodyBytes]
/// if present, else a numeric `Content-Length` header, else the (memoized)
/// UTF-8 byte length of the body.
int responseSizeBytes(HttpResponseEntity response) {
  final bytes = response.bodyBytes;
  if (bytes != null) return bytes.length;
  for (final e in response.headers.entries) {
    if (e.key.toLowerCase() == 'content-length') {
      final n = int.tryParse(e.value.trim());
      if (n != null) return n;
    }
  }
  return _sizeCache[response] ??= utf8.encode(response.body).length;
}

/// Humanizes a byte count as `B` / `KB` / `MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}
