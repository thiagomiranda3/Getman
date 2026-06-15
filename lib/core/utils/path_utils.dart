/// Filesystem path helpers that work for both POSIX (`/`) and Windows (`\`)
/// separators — Getman runs on macOS, Linux and Windows.
class PathUtils {
  PathUtils._();

  static final RegExp _sep = RegExp(r'[/\\]');

  /// The final path segment (the file name). Trailing separators are trimmed
  /// first, so a directory-like path (e.g. `/a/b/`) returns `b`, not `''`.
  static String basename(String path) {
    var p = path;
    while (p.isNotEmpty && (p.endsWith('/') || p.endsWith(r'\'))) {
      p = p.substring(0, p.length - 1);
    }
    if (p.isEmpty) return '';
    return p.split(_sep).last;
  }
}
