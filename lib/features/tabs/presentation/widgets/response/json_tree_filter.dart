// Pure filter/expand planners for the response TREE body mode (C2):
// filterJsonTree matches key names + primitive value strings (case-
// insensitive contains) and returns the node ids to keep and auto-expand,
// capped at kTreeFilterMaxRevealedNodes revealed nodes; planExpandAll
// returns every container id, falling back to depth kTreeExpandAllDepthCap
// on trees over kTreeExpandAllMaxNodes so EXPAND ALL can never freeze the UI.
// Node ids are JSONPath strings in the JsonPathBuilder grammar — the same
// ids JsonTreeView keys its expansion set with.
import 'package:equatable/equatable.dart';
import 'package:getman/core/utils/json_path_builder.dart';

/// Auto-expansion cap: a filter reveals at most this many nodes (matches +
/// their ancestors); past it the result is flagged [JsonTreeFilterResult
/// .truncated] and the UI shows "Refine filter to see more".
const int kTreeFilterMaxRevealedNodes = 500;

/// EXPAND ALL guardrail: trees with more total nodes than this expand only to
/// [kTreeExpandAllDepthCap] instead of fully.
const int kTreeExpandAllMaxNodes = 2000;

/// The depth EXPAND ALL falls back to on over-limit trees (containers at
/// depth 0..cap-1 are expanded, revealing rows down to depth cap).
const int kTreeExpandAllDepthCap = 3;

/// Result of a [filterJsonTree] walk, in JsonPathBuilder path ids.
class JsonTreeFilterResult extends Equatable {
  const JsonTreeFilterResult({
    required this.matchedPaths,
    required this.ancestorPaths,
    required this.matchCount,
    required this.truncated,
  });

  /// The no-filter sentinel (empty query).
  static const JsonTreeFilterResult empty = JsonTreeFilterResult(
    matchedPaths: <String>{},
    ancestorPaths: <String>{},
    matchCount: 0,
    truncated: false,
  );

  /// Paths of revealed matching nodes (capped by the reveal limit).
  final Set<String> matchedPaths;

  /// Ancestor container paths of revealed matches — auto-expand these.
  final Set<String> ancestorPaths;

  /// Total matches in the document, including ones beyond the reveal cap.
  final int matchCount;

  /// True when the reveal cap was hit (some matches are not in
  /// [matchedPaths]) — surface "Refine filter to see more".
  final bool truncated;

  @override
  List<Object?> get props => [
    matchedPaths,
    ancestorPaths,
    matchCount,
    truncated,
  ];
}

/// Walks decoded JSON [data] and matches [query] (case-insensitive contains)
/// against key names and primitive value strings. Matching nodes are revealed
/// together with their ancestor chain, up to [maxRevealed] total revealed
/// nodes; [JsonTreeFilterResult.matchCount] always counts every match.
JsonTreeFilterResult filterJsonTree({
  required Object? data,
  required String query,
  int maxRevealed = kTreeFilterMaxRevealedNodes,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return JsonTreeFilterResult.empty;

  final matched = <String>{};
  final ancestors = <String>{};
  final chain = <String>[];
  var matchCount = 0;
  var truncated = false;

  bool isMatch(String label, Object? value) {
    if (label.toLowerCase().contains(q)) return true;
    if (value is Map || value is List) return false;
    final s = value?.toString() ?? 'null';
    return s.toLowerCase().contains(q);
  }

  void record(String path) {
    matchCount++;
    // A chain entry already revealed as a *match* (a matched container that
    // is also the ancestor of a deeper match) must not be re-budgeted as an
    // ancestor — otherwise the same node id is counted twice toward the cap
    // and the walk truncates before the reveal set actually fills up.
    final newAncestors = chain
        .where((a) => !ancestors.contains(a) && !matched.contains(a))
        .length;
    if (matched.length + ancestors.length + 1 + newAncestors > maxRevealed) {
      truncated = true;
      return;
    }
    matched.add(path);
    for (final a in chain) {
      if (!matched.contains(a)) ancestors.add(a);
    }
  }

  void walk(Object? value, String path, String label) {
    if (isMatch(label, value)) record(path);
    if (value is Map) {
      chain.add(path);
      for (final e in value.entries) {
        walk(
          e.value,
          JsonPathBuilder.appendKey(path, e.key.toString()),
          e.key.toString(),
        );
      }
      chain.removeLast();
    } else if (value is List) {
      chain.add(path);
      for (var i = 0; i < value.length; i++) {
        walk(value[i], JsonPathBuilder.appendIndex(path, i), '[$i]');
      }
      chain.removeLast();
    }
  }

  if (data is Map) {
    for (final e in data.entries) {
      walk(
        e.value,
        JsonPathBuilder.appendKey(JsonPathBuilder.root, e.key.toString()),
        e.key.toString(),
      );
    }
  } else if (data is List) {
    for (var i = 0; i < data.length; i++) {
      walk(
        data[i],
        JsonPathBuilder.appendIndex(JsonPathBuilder.root, i),
        '[$i]',
      );
    }
  } else if (isMatch(JsonPathBuilder.root, data)) {
    // Scalar root: a single row at `$` (mirrors flattenVisibleJsonTree).
    matchCount++;
    matched.add(JsonPathBuilder.root);
  }

  return JsonTreeFilterResult(
    matchedPaths: matched,
    ancestorPaths: ancestors,
    matchCount: matchCount,
    truncated: truncated,
  );
}

/// The container paths EXPAND ALL should add to the expansion set.
class JsonTreeExpandAllPlan extends Equatable {
  const JsonTreeExpandAllPlan({
    required this.containerPaths,
    required this.limitedToDepth,
  });

  /// Every container path to expand (possibly depth-limited).
  final Set<String> containerPaths;

  /// True when the tree exceeded the node budget and only containers above
  /// the depth cap were included — surface a "expanded to depth N" note.
  final bool limitedToDepth;

  @override
  List<Object?> get props => [containerPaths, limitedToDepth];
}

/// Plans EXPAND ALL over decoded JSON [data]: all container paths, unless the
/// tree has more than [maxNodes] total nodes — then only containers at depth
/// < [depthCap] (top-level rows are depth 0, matching flattenVisibleJsonTree).
JsonTreeExpandAllPlan planExpandAll({
  required Object? data,
  int maxNodes = kTreeExpandAllMaxNodes,
  int depthCap = kTreeExpandAllDepthCap,
}) {
  var total = 0;
  void count(Object? v) {
    total++;
    if (v is Map) {
      v.values.forEach(count);
    } else if (v is List) {
      v.forEach(count);
    }
  }

  if (data is Map) {
    data.values.forEach(count);
  } else if (data is List) {
    data.forEach(count);
  } else {
    total = 1;
  }

  final limited = total > maxNodes;
  final out = <String>{};

  void collect(Object? value, String path, int depth) {
    if (value is! Map && value is! List) return;
    if (limited && depth >= depthCap) return;
    out.add(path);
    if (value is Map) {
      for (final e in value.entries) {
        collect(
          e.value,
          JsonPathBuilder.appendKey(path, e.key.toString()),
          depth + 1,
        );
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        collect(value[i], JsonPathBuilder.appendIndex(path, i), depth + 1);
      }
    }
  }

  if (data is Map) {
    for (final e in data.entries) {
      collect(
        e.value,
        JsonPathBuilder.appendKey(JsonPathBuilder.root, e.key.toString()),
        0,
      );
    }
  } else if (data is List) {
    for (var i = 0; i < data.length; i++) {
      collect(data[i], JsonPathBuilder.appendIndex(JsonPathBuilder.root, i), 0);
    }
  }

  return JsonTreeExpandAllPlan(containerPaths: out, limitedToDepth: limited);
}
