// Converts key/value editor rows to/from a Postman-style `key: value` text
// block for bulk-edit mode; shared by ParamsTabView and HeadersTabView.

/// Converts between the key/value editor's row currency
/// `List<(String, String)>` and a Postman-style `key: value` text block.
///
/// Pure Dart — no Flutter, no bloc — so both `ParamsTabView` and
/// `HeadersTabView` reuse it and it is unit-testable in isolation. It deals
/// only in `(key, value)` rows; the per-tab `encode`/`decode` closures
/// convert rows ↔ the canonical value (`List<QueryParamEntity>` /
/// `Map<String,String>`) exactly as the row editor already does, so bulk and
/// row paths produce identical canonical values.
class BulkKvCodec {
  const BulkKvCodec._();

  /// Rows → text block. One `key: value` line per pair, canonical order, value
  /// emitted verbatim (no trimming). Empty-key pairs are skipped — they never
  /// reach canonical state anyway (both tab `encode`s drop empty keys).
  static String serialize(List<(String, String)> rows) {
    final buffer = StringBuffer();
    var first = true;
    for (final (key, value) in rows) {
      if (key.isEmpty) continue;
      if (!first) buffer.write('\n');
      buffer
        ..write(key)
        ..write(': ')
        ..write(value);
      first = false;
    }
    return buffer.toString();
  }

  /// Text block → rows. Each line is split on the FIRST `:`.
  ///   - blank / whitespace-only line  → dropped (D4)
  ///   - no colon                      → (trimmedLine, '')          (D3)
  ///   - colon present                 → (key.trim(), value.trim()) (D2)
  ///   - empty key after trim          → dropped                    (D5)
  static List<(String, String)> parse(String text) {
    final rows = <(String, String)>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue; // D4
      final colon = line.indexOf(':');
      if (colon < 0) {
        rows.add((line, '')); // D3 — line is already trimmed and non-empty
        continue;
      }
      final key = line.substring(0, colon).trim();
      if (key.isEmpty) continue; // D5
      final value = line.substring(colon + 1).trim(); // D2
      rows.add((key, value));
    }
    return rows;
  }
}
