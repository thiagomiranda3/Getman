// Pure filter/expand planners for the response TREE body mode (C2):
// filterJsonTree matches key names + primitive value strings (case-
// insensitive contains) and returns the node ids to keep and auto-expand,
// capped at kTreeFilterMaxRevealedNodes revealed nodes; planExpandAll
// returns every container id, falling back to depth kTreeExpandAllDepthCap
// on trees over kTreeExpandAllMaxNodes so EXPAND ALL can never freeze the UI.
// Node ids are JSONPath strings in the JsonPathBuilder grammar — the same
// ids JsonTreeView keys its expansion set with. Every recursive walk here
// (and flattenVisibleJsonTree's) stops at kTreeMaxDepth so a pathological
// deeply-nested body can never overflow the stack.
import 'package:equatable/equatable.dart';
import 'package:getman/core/utils/json_path_builder.dart';

/// Hard recursion ceiling shared by every walk over decoded JSON — the
/// flatten pass (`flattenVisibleJsonTree`), the filter walk, and
/// [planExpandAll]'s count/collect. The TREE gate admits bodies up to
/// `kLargeResponseViewerChars` (512 KiB), and a pathological `[[[[…]]]]`
/// body in that budget nests ~200k levels deep — `jsonDecode` survives
/// that, but an unguarded recursive walk overflows the stack. 512 levels
/// is generous for real JSON (typical APIs nest well under 20) while
/// staying far below crash depth. Content past the cap renders as a single
/// "[nested too deep — N more levels]" leaf (flatten), stops being matched
/// (filter — flagged via [JsonTreeFilterResult.truncated]), and stops being
/// counted/collected (expand-all planning).
const int kTreeMaxDepth = 512;

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

  /// Every chain entry of a revealed match — auto-expand these. Includes
  /// containers that are themselves matches (they overlap [matchedPaths]):
  /// a matched container with a matching descendant must still expand, or
  /// the descendant match is counted but invisible.
  final Set<String> ancestorPaths;

  /// Total matches in the document, including ones beyond the reveal cap.
  final int matchCount;

  /// True when the reveal cap was hit (some matches are not in
  /// [matchedPaths]) or content past [kTreeMaxDepth] was skipped without
  /// being matched — surface "Refine filter to see more".
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
///
/// The walk never descends past [maxDepth] (default [kTreeMaxDepth], the
/// stack-overflow guard); skipped non-empty subtrees flag
/// [JsonTreeFilterResult.truncated].
JsonTreeFilterResult filterJsonTree({
  required Object? data,
  required String query,
  int maxRevealed = kTreeFilterMaxRevealedNodes,
  int maxDepth = kTreeMaxDepth,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return JsonTreeFilterResult.empty;

  final matched = <String>{};
  final ancestors = <String>{};
  // Budget = revealed ROWS (matched ∪ ancestors). Tracked as a separate
  // union set because `ancestors` deliberately overlaps `matched`: a matched
  // container that is also the ancestor of a deeper match must appear in
  // BOTH — excluding it from `ancestors` (the auto-expand set) left it
  // collapsed, hiding its matching descendants while the match counter still
  // announced them ("2 MATCHES" with one invisible).
  final revealed = <String>{};
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
    final newReveals =
        (revealed.contains(path) ? 0 : 1) +
        chain.where((a) => !revealed.contains(a)).length;
    if (revealed.length + newReveals > maxRevealed) {
      truncated = true;
      return;
    }
    matched.add(path);
    revealed.add(path);
    for (final a in chain) {
      ancestors.add(a);
      revealed.add(a);
    }
  }

  void walk(Object? value, String path, String label, int depth) {
    if (isMatch(label, value)) record(path);
    final hasChildren = value is Map
        ? value.isNotEmpty
        : value is List && value.isNotEmpty;
    if (!hasChildren) return;
    if (depth + 1 >= maxDepth) {
      // Depth guard (kTreeMaxDepth): children past the cap are never
      // rendered by flattenVisibleJsonTree, so stop matching here — but
      // flag the skip so the UI shows "Refine filter to see more" instead
      // of silently pretending the subtree is empty.
      truncated = true;
      return;
    }
    if (value is Map) {
      chain.add(path);
      for (final e in value.entries) {
        walk(
          e.value,
          JsonPathBuilder.appendKey(path, e.key.toString()),
          e.key.toString(),
          depth + 1,
        );
      }
      chain.removeLast();
    } else if (value is List) {
      chain.add(path);
      for (var i = 0; i < value.length; i++) {
        walk(value[i], JsonPathBuilder.appendIndex(path, i), '[$i]', depth + 1);
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
        0,
      );
    }
  } else if (data is List) {
    for (var i = 0; i < data.length; i++) {
      walk(
        data[i],
        JsonPathBuilder.appendIndex(JsonPathBuilder.root, i),
        '[$i]',
        0,
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
///
/// Neither the count nor the collect pass descends past [maxDepth] (default
/// [kTreeMaxDepth], the stack-overflow guard): nodes below the cap can never
/// render, so they are neither counted toward [maxNodes] nor expandable.
JsonTreeExpandAllPlan planExpandAll({
  required Object? data,
  int maxNodes = kTreeExpandAllMaxNodes,
  int depthCap = kTreeExpandAllDepthCap,
  int maxDepth = kTreeMaxDepth,
}) {
  var total = 0;
  void count(Object? v, int depth) {
    total++;
    if (depth + 1 >= maxDepth) return; // depth guard (kTreeMaxDepth)
    if (v is Map) {
      for (final child in v.values) {
        count(child, depth + 1);
      }
    } else if (v is List) {
      for (final child in v) {
        count(child, depth + 1);
      }
    }
  }

  if (data is Map) {
    for (final child in data.values) {
      count(child, 0);
    }
  } else if (data is List) {
    for (final child in data) {
      count(child, 0);
    }
  } else {
    total = 1;
  }

  final limited = total > maxNodes;
  final out = <String>{};

  void collect(Object? value, String path, int depth) {
    if (value is! Map && value is! List) return;
    if (depth >= maxDepth) return; // depth guard (kTreeMaxDepth)
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
