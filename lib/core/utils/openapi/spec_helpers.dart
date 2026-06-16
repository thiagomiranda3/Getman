// lib/core/utils/openapi/spec_helpers.dart

// Shared helpers for the OpenAPI v3 / Swagger v2 normalizers.

/// `[{schemeName: [...]}, ...]` → first scheme name, or null if empty/absent.
String? firstSecuritySchemeName(Object? security) {
  if (security is List && security.isNotEmpty) {
    final first = security.first;
    if (first is Map && first.isNotEmpty) return first.keys.first.toString();
  }
  return null;
}
