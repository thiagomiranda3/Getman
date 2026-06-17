/// Builds JSONPath strings in the exact grammar that `JsonPath` accepts
/// (see `json_path.dart`): optional leading `$`, dot member access, array
/// indices, and bracket-quoted keys for anything not identifier-safe.
///
/// Pair with `JsonPath.isValid` at call sites — a key containing a `]` cannot
/// be represented by the grammar, so guard before offering copy/extract.
class JsonPathBuilder {
  JsonPathBuilder._();

  /// The whole-document selector; children are appended onto this.
  static const String root = r'$';

  /// Identifier-safe keys (letters, digits, `_`, `$`, not starting with a
  /// digit) can use dot notation; everything else is bracket-quoted.
  static final RegExp _dotSafe = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  /// Appends object member [key] to [parentPath].
  static String appendKey(String parentPath, String key) {
    if (_dotSafe.hasMatch(key)) return '$parentPath.$key';
    // A double quote in the key would collide with the default quoting, so
    // fall back to single quotes for those (the parser strips outer quotes
    // without un-escaping).
    final quote = key.contains('"') ? "'" : '"';
    return '$parentPath[$quote$key$quote]';
  }

  /// Appends array [index] to [parentPath].
  static String appendIndex(String parentPath, int index) =>
      '$parentPath[$index]';
}
