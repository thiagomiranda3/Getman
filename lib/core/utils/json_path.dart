// A deliberately small JSONPath subset (optional leading `$`, dot member
// access, bracket-quoted keys, array indices — no wildcards/filters/
// recursive descent/negative indices/slices) for no-code response extraction
// and assertions. Pure Dart; never throws, a miss or parse failure yields
// null/false.

import 'dart:convert';

/// A deliberately small JSONPath subset for no-code response extraction and
/// assertions. Pure; never throws — a miss or a parse failure returns null.
///
/// Supported:
///   - optional leading `$`
///   - dot member access:        `a.b.c`
///   - bracket-quoted keys:       `a["k with space"]`, `a['k.with.dots']`
///   - array index:              `a[0]`, `a.b[2].c`
///
/// NOT supported (documented limitations): wildcards `*`, filters `?(...)`,
/// recursive descent `..`, negative indices, slices.
class JsonPath {
  JsonPath._();

  /// Reads the value at [path] within already-decoded JSON [root], or null if
  /// the path is invalid or doesn't resolve.
  ///
  /// A legitimately-null leaf is indistinguishable from a miss here — callers
  /// that must tell them apart (exists assertions, extraction) use [lookup].
  static Object? read(Object? root, String path) {
    final r = lookup(root, path);
    return r.found ? r.value : null;
  }

  /// Like [read], but reports whether the path actually RESOLVED: a JSON
  /// `null` leaf is `(found: true, value: null)`, a missing/invalid path is
  /// `(found: false, value: null)`.
  static ({bool found, Object? value}) lookup(Object? root, String path) {
    const miss = (found: false, value: null);
    final segments = _parse(path);
    if (segments == null) return miss;
    var current = root;
    for (final seg in segments) {
      if (seg is int) {
        if (current is List && seg < current.length) {
          current = current[seg];
        } else {
          return miss;
        }
      } else {
        final key = seg as String;
        if (current is Map && current.containsKey(key)) {
          current = current[key];
        } else {
          return miss;
        }
      }
    }
    return (found: true, value: current);
  }

  /// Decodes [rawJson] then reads [path]. Null on parse failure or miss.
  static Object? readFromString(String rawJson, String path) =>
      read(tryDecode(rawJson), path);

  /// Decodes [rawJson] to a JSON object/array/scalar, or null on parse failure.
  /// Lets callers decode a body **once** and run many [read]s against the
  /// result (instead of re-decoding per path).
  static Object? tryDecode(String rawJson) {
    try {
      return jsonDecode(rawJson);
    } on Object catch (_) {
      return null;
    }
  }

  /// Whether [path] is syntactically valid (distinguishes "bad path" from
  /// "valid path that didn't resolve" for the rule editor).
  static bool isValid(String path) => _parse(path) != null;

  /// Parses [path] into key (String) / index (int) segments, or null if the
  /// syntax is invalid. `$` alone parses to an empty segment list (whole doc).
  static List<Object>? _parse(String path) {
    var p = path.trim();
    if (p.isEmpty) return null;
    if (p == r'$') return const [];
    if (p.startsWith(r'$')) p = p.substring(1);

    final segments = <Object>[];
    var i = 0;
    while (i < p.length) {
      final ch = p[i];
      if (ch == '[') {
        final end = p.indexOf(']', i);
        if (end == -1) return null;
        final inner = p.substring(i + 1, end).trim();
        if (inner.isEmpty) return null;
        if ((inner.startsWith('"') &&
                inner.endsWith('"') &&
                inner.length >= 2) ||
            (inner.startsWith("'") &&
                inner.endsWith("'") &&
                inner.length >= 2)) {
          segments.add(inner.substring(1, inner.length - 1));
        } else {
          final idx = int.tryParse(inner);
          if (idx == null || idx < 0) return null;
          segments.add(idx);
        }
        i = end + 1;
      } else {
        // Skip a leading/separating dot.
        if (ch == '.') {
          i++;
          if (i >= p.length) return null; // trailing dot
        }
        final start = i;
        while (i < p.length && p[i] != '.' && p[i] != '[') {
          i++;
        }
        final key = p.substring(start, i);
        if (key.isEmpty) return null; // e.g. `a..b`
        segments.add(key);
      }
    }
    return segments;
  }
}
