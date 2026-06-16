import 'package:equatable/equatable.dart';

/// Whether a line is unchanged, present only on the right (added), or present
/// only on the left (removed) in a unified line diff.
enum DiffLineKind { equal, added, removed }

/// One line of a unified line diff: its [kind] and content (no trailing
/// newline).
class DiffLine extends Equatable {
  const DiffLine(this.kind, this.text);

  final DiffLineKind kind;
  final String text;

  @override
  List<Object?> get props => [kind, text];
}

/// A small, dependency-free LCS line diff. The table is over line *lists*
/// (line counts, not characters, drive its size), which is ample for response
/// bodies and keeps the logic pure and testable.
class LineDiff {
  const LineDiff._();

  /// LCS-based unified line diff. [left] lines absent from the LCS are
  /// [DiffLineKind.removed]; [right] lines absent from the LCS are
  /// [DiffLineKind.added]; LCS lines are [DiffLineKind.equal]. Within a changed
  /// hunk, all removed lines precede added lines (unified-diff convention).
  static List<DiffLine> diff(List<String> left, List<String> right) {
    final n = left.length;
    final m = right.length;

    // LCS length DP table. lcs[i][j] = LCS length of left[i..] and right[j..].
    final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        if (left[i] == right[j]) {
          lcs[i][j] = lcs[i + 1][j + 1] + 1;
        } else {
          lcs[i][j] = lcs[i + 1][j] >= lcs[i][j + 1]
              ? lcs[i + 1][j]
              : lcs[i][j + 1];
        }
      }
    }

    final out = <DiffLine>[];
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (left[i] == right[j]) {
        out.add(DiffLine(DiffLineKind.equal, left[i]));
        i++;
        j++;
      } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        // Dropping left[i] keeps the LCS at least as long -> it was removed.
        out.add(DiffLine(DiffLineKind.removed, left[i]));
        i++;
      } else {
        out.add(DiffLine(DiffLineKind.added, right[j]));
        j++;
      }
    }
    while (i < n) {
      out.add(DiffLine(DiffLineKind.removed, left[i]));
      i++;
    }
    while (j < m) {
      out.add(DiffLine(DiffLineKind.added, right[j]));
      j++;
    }
    return out;
  }

  /// Splits both inputs on `\n` and diffs. A single trailing newline is dropped
  /// so `"a\nb\n"` diffs as `["a", "b"]`, matching what the body viewer shows.
  static List<DiffLine> diffText(String left, String right) {
    return diff(_lines(left), _lines(right));
  }

  static List<String> _lines(String text) {
    if (text.isEmpty) return const [];
    final parts = text.split('\n');
    if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
    return parts;
  }
}
