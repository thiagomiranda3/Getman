import 'dart:convert';

import 'package:getman/core/network/http_response.dart';

/// Best-effort response size in bytes: a numeric `Content-Length` header when
/// present, else the UTF-8 byte length of the body.
int responseSizeBytes(HttpResponseEntity response) {
  for (final e in response.headers.entries) {
    if (e.key.toLowerCase() == 'content-length') {
      final n = int.tryParse(e.value.trim());
      if (n != null) return n;
    }
  }
  return utf8.encode(response.body).length;
}

/// Humanizes a byte count as `B` / `KB` / `MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}
