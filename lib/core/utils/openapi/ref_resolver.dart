// Resolves internal JSON-pointer `$ref`s (`#/...`) within a single OpenAPI/
// Swagger spec document; external refs are left intact. deepResolve recurses
// through an entire node, replacing every ref with a copy of its target and
// short-circuiting cycles to `{}` so resolution always terminates.

/// Resolves internal JSON-pointer `$ref`s (`#/...`) within a single spec
/// document. External refs (anything not starting with `#/`) are left intact.
class RefResolver {
  RefResolver(this._root);
  final Map<String, dynamic> _root;

  /// True if [node] is `{ $ref: '#/...' }` (an internal reference).
  bool isInternalRef(Object? node) =>
      node is Map &&
      node[r'$ref'] is String &&
      (node[r'$ref'] as String).startsWith('#/');

  /// One-level resolve: if [node] is an internal `$ref`, return its target
  /// map; otherwise return [node] unchanged. Returns `{}` if the pointer is
  /// dangling.
  Map<String, dynamic> resolve(Map<String, dynamic> node) {
    if (!isInternalRef(node)) return node;
    final target = _follow(node[r'$ref'] as String);
    return target is Map
        ? Map<String, dynamic>.from(target)
        : <String, dynamic>{};
  }

  /// Recursively resolves all internal refs in [node], replacing each with a
  /// copy of its target. Cyclic refs are replaced with `{}` to terminate.
  Object? deepResolve(Object? node, [Set<String>? seen]) {
    final visited = seen ?? <String>{};
    if (node is Map) {
      final ref = node[r'$ref'];
      if (ref is String && ref.startsWith('#/')) {
        if (visited.contains(ref)) return <String, dynamic>{}; // cycle
        final target = _follow(ref);
        if (target is! Map) return <String, dynamic>{};
        return deepResolve(
          Map<String, dynamic>.from(target),
          {...visited, ref},
        );
      }
      return <String, dynamic>{
        for (final e in node.entries)
          e.key.toString(): deepResolve(e.value, visited),
      };
    }
    if (node is List) {
      return node.map((e) => deepResolve(e, visited)).toList();
    }
    return node;
  }

  Object? _follow(String ref) {
    // '#/components/schemas/User' -> ['components','schemas','User']
    final parts = ref
        .substring(2)
        .split('/')
        .map((p) => p.replaceAll('~1', '/').replaceAll('~0', '~'));
    Object? current = _root;
    for (final part in parts) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }
}
