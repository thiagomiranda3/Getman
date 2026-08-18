// Resolves internal JSON-pointer `$ref`s (`#/...`) within a single OpenAPI/
// Swagger spec document; external refs are left intact. deepResolve recurses
// through an entire node, replacing every ref with a copy of its target,
// short-circuiting cycles to `{}`, and stopping ref expansion once a total
// node budget is spent (fan-out guard) so resolution always terminates fast.

import 'package:flutter/foundation.dart';

/// Total number of nodes [RefResolver.deepResolve] may visit per resolver
/// instance (i.e. per imported spec) before it stops expanding `$ref`s.
///
/// Guards against "billion laughs" fan-out: the per-path cycle guard cannot
/// stop sibling refs from re-expanding, so ~2KB of JSON with 10 refs per
/// level x 10 levels would otherwise materialize 10^10 nodes synchronously
/// on the UI isolate. Normal specs resolve well under this; when the budget
/// is exceeded, remaining refs are left unresolved (schema_sampler renders
/// them as empty values) and [RefResolver.nodeBudgetExhausted] turns true so
/// callers can surface a "spec too complex" warning.
const int kRefResolverNodeBudget = 50000;

/// Resolves internal JSON-pointer `$ref`s (`#/...`) within a single spec
/// document. External refs (anything not starting with `#/`) are left intact.
class RefResolver {
  RefResolver(
    this._root, {
    @visibleForTesting this._nodeBudget = kRefResolverNodeBudget,
  });

  final Map<String, dynamic> _root;
  final int _nodeBudget;
  int _visitedNodes = 0;
  bool _truncated = false;

  /// True once [deepResolve] ran out of node budget and left at least one
  /// internal ref unexpanded — the caller should surface a "spec too complex
  /// to fully resolve" warning.
  bool get nodeBudgetExhausted => _truncated;

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
  /// copy of its target. Cyclic refs are replaced with `{}` to terminate;
  /// once the node budget is spent, refs are returned unexpanded (see
  /// [kRefResolverNodeBudget]) so a fan-out bomb cannot hang the isolate.
  Object? deepResolve(Object? node, [Set<String>? seen]) {
    final visited = seen ?? <String>{};
    _visitedNodes++;
    if (node is Map) {
      final ref = node[r'$ref'];
      if (ref is String && ref.startsWith('#/')) {
        if (visited.contains(ref)) return <String, dynamic>{}; // cycle
        if (_visitedNodes > _nodeBudget) {
          // Fan-out guard: budget spent — leave the ref unexpanded.
          _truncated = true;
          return Map<String, dynamic>.from(node);
        }
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
