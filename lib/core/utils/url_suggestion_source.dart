// Pure merge/rank/dedup/cap helper for the URL bar's URL-suggestion mode
// (B4): merges history URLs (newest first) with saved collection request
// URLs — case-insensitive contains match, prefix matches ranked above
// substring matches, case-insensitive first-occurrence-wins dedup (history
// spelling preserved), a candidate equal to the query itself is dropped,
// capped at kUrlSuggestionMaxResults. Zero imports — unit-testable in
// isolation; the widget side stays dumb (the min-chars gate lives here,
// not in the overlay).

/// Minimum trimmed characters typed before URL suggestions appear.
const int kUrlSuggestionMinChars = 3;

/// Maximum number of URL suggestions offered.
const int kUrlSuggestionMaxResults = 8;

/// Builds the URL-mode suggestion list for [query].
///
/// Candidates are [historyUrls] (newest first — their order is preserved)
/// followed by [collectionUrls]. Matching is case-insensitive `contains`;
/// prefix matches rank above substring matches (stable within each rank).
/// Duplicates are removed case-insensitively (first occurrence wins, so a URL
/// in both sources keeps its history rank and original spelling), and a
/// candidate equal to the trimmed [query] (case-insensitive) is dropped —
/// suggesting exactly what is typed is noise. Returns `const []` until the
/// trimmed [query] has at least [kUrlSuggestionMinChars] characters.
/// Capped at [limit].
List<String> buildUrlSuggestions({
  required String query,
  required List<String> historyUrls,
  required List<String> collectionUrls,
  int limit = kUrlSuggestionMaxResults,
}) {
  final trimmed = query.trim();
  if (trimmed.length < kUrlSuggestionMinChars) return const [];
  final lower = trimmed.toLowerCase();

  final seen = <String>{};
  final prefixMatches = <String>[];
  final substringMatches = <String>[];
  for (final url in [...historyUrls, ...collectionUrls]) {
    final candidate = url.trim();
    if (candidate.isEmpty) continue;
    final candidateLower = candidate.toLowerCase();
    if (!seen.add(candidateLower)) continue;
    if (candidateLower == lower) continue; // exactly what's typed — noise
    if (candidateLower.startsWith(lower)) {
      prefixMatches.add(candidate);
    } else if (candidateLower.contains(lower)) {
      substringMatches.add(candidate);
    }
  }
  return [...prefixMatches, ...substringMatches].take(limit).toList();
}
