// Shared helpers for the OpenAPI v3 / Swagger v2 normalizers:
// firstSecuritySchemeName reads the first scheme name off a `security`
// array, and mergedParameters combines a path-item's shared `parameters`
// with an operation's own (op-level overrides a shared entry with the same
// name+in), resolving `$ref`s along the way.

import 'package:getman/core/utils/openapi/ref_resolver.dart';

/// `[{schemeName: [...]}, ...]` → first scheme name, or null if empty/absent.
String? firstSecuritySchemeName(Object? security) {
  if (security is List && security.isNotEmpty) {
    final first = security.first;
    if (first is Map && first.isNotEmpty) return first.keys.first.toString();
  }
  return null;
}

/// Merges the path-item-level shared `parameters` list with an operation's
/// own (both OpenAPI 3.x and Swagger 2.0 define this): the shared params
/// apply to every operation on the path, and an op-level parameter overrides
/// a shared one with the same `name` + `in`. Entries are `$ref`-resolved;
/// non-list inputs are treated as empty.
List<Map<String, dynamic>> mergedParameters(
  dynamic shared,
  dynamic opLevel,
  RefResolver refs,
) {
  final byKey = <String, Map<String, dynamic>>{};
  void collect(dynamic list) {
    if (list is! List) return;
    for (final p in list.whereType<Map<String, dynamic>>()) {
      final resolved = refs.resolve(Map<String, dynamic>.from(p));
      byKey['${resolved['in']}|${resolved['name']}'] = resolved;
    }
  }

  collect(shared);
  collect(opLevel);
  return byKey.values.toList();
}
