/// Tiny subsequence fuzzy matcher for the command palette. No package — keeps
/// the local-first/lightweight dependency surface small.
class FuzzyMatcher {
  FuzzyMatcher._();

  /// Returns a relevance score (higher is better) when [query] is a
  /// case-insensitive subsequence of [candidate], else null. An empty query
  /// matches everything with score 0. Consecutive matches and word-start hits
  /// (after space/`/`/`_`/`-`) score higher.
  static int? score(String query, String candidate) {
    if (query.isEmpty) return 0;
    final q = query.toLowerCase();
    final c = candidate.toLowerCase();
    var ci = 0;
    var total = 0;
    var streak = 0;
    for (var qi = 0; qi < q.length; qi++) {
      var found = false;
      while (ci < c.length) {
        if (c[ci] == q[qi]) {
          total += 1 + streak;
          if (ci == 0 || _isBoundary(c[ci - 1])) total += 2;
          streak++;
          ci++;
          found = true;
          break;
        }
        streak = 0;
        ci++;
      }
      if (!found) return null;
    }
    return total;
  }

  /// Filters + ranks [items] by [query] against [label]. Stable for ties.
  static List<T> filter<T>(
    String query,
    Iterable<T> items,
    String Function(T) label,
  ) {
    if (query.trim().isEmpty) return items.toList();
    final scored = <({int score, int index, T item})>[];
    var i = 0;
    for (final item in items) {
      final s = score(query, label(item));
      if (s != null) scored.add((score: s, index: i, item: item));
      i++;
    }
    scored.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      return a.index.compareTo(b.index);
    });
    return [for (final e in scored) e.item];
  }

  static bool _isBoundary(String ch) =>
      ch == ' ' || ch == '/' || ch == '_' || ch == '-' || ch == '.';
}
