// Converts key/value editor rows to/from a Postman-style `key: value` text
// block for bulk-edit mode; shared by ParamsTabView and HeadersTabView.
// A leading `//` marks a disabled row (Postman's convention), carried by
// the BulkKvRow record API (serializeRows/parseRows); the legacy
// serialize/parse pair is an enabled-only view over the same grammar.

/// A bulk-editor line: key/value plus whether the row is disabled
/// (Postman's leading-`//` convention).
typedef BulkKvRow = ({String key, String value, bool disabled});

/// Converts between the key/value editor's row currency and a Postman-style
/// `key: value` text block, with a leading `//` marking a disabled row.
///
/// Pure Dart — no Flutter, no bloc — so both `ParamsTabView` and
/// `HeadersTabView` reuse it and it is unit-testable in isolation. It deals
/// only in rows; the per-tab `encode`/`decode` closures convert rows ↔ the
/// canonical value exactly as the row editor already does, so bulk and row
/// paths produce identical canonical values.
class BulkKvCodec {
  const BulkKvCodec._();

  static const String _disabledPrefix = '//';

  /// Rows → text block. One `key: value` line per pair (disabled rows
  /// prefixed `//`), canonical order, value emitted verbatim (no trimming).
  /// Empty-key rows are skipped — they never reach canonical state anyway.
  static String serializeRows(List<BulkKvRow> rows) {
    final buffer = StringBuffer();
    var first = true;
    for (final row in rows) {
      if (row.key.isEmpty) continue;
      if (!first) buffer.write('\n');
      if (row.disabled) buffer.write(_disabledPrefix);
      buffer
        ..write(row.key)
        ..write(': ')
        ..write(row.value);
      first = false;
    }
    return buffer.toString();
  }

  /// Text block → rows. A leading `//` (after trimming) marks the row
  /// disabled and is stripped before the usual split on the FIRST `:`:
  ///   - blank / whitespace-only line  → dropped (D4)
  ///   - no colon                      → (trimmedLine, '')          (D3)
  ///   - colon present                 → (key.trim(), value.trim()) (D2)
  ///   - empty key after trim          → dropped                    (D5)
  static List<BulkKvRow> parseRows(String text) {
    final rows = <BulkKvRow>[];
    for (final rawLine in text.split('\n')) {
      var line = rawLine.trim();
      if (line.isEmpty) continue; // D4
      final disabled = line.startsWith(_disabledPrefix);
      if (disabled) {
        line = line.substring(_disabledPrefix.length).trim();
        if (line.isEmpty) continue; // a bare `//` line
      }
      final colon = line.indexOf(':');
      if (colon < 0) {
        rows.add((key: line, value: '', disabled: disabled)); // D3
        continue;
      }
      final key = line.substring(0, colon).trim();
      if (key.isEmpty) continue; // D5
      rows.add((
        key: key,
        value: line.substring(colon + 1).trim(), // D2
        disabled: disabled,
      ));
    }
    return rows;
  }

  /// Enabled-only view: like [serializeRows] with every row enabled.
  static String serialize(List<(String, String)> rows) => serializeRows([
    for (final (key, value) in rows) (key: key, value: value, disabled: false),
  ]);

  /// Enabled-only view over [parseRows]: disabled rows are kept but their
  /// `//` prefix and flag are dropped. Hosts that care about the flag use
  /// [parseRows] directly.
  static List<(String, String)> parse(String text) => [
    for (final row in parseRows(text)) (row.key, row.value),
  ];
}
