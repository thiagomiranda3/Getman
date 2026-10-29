// Exact LCS unified line diff with a fixed work/memory budget. Common prefixes
// (including identical inputs) bypass the matrix; changed ranges exceeding
// one million cells throw LineDiffBudgetExceeded before allocating.

import 'dart:typed_data';

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

/// Signals that an exact diff would exceed the bounded LCS work budget.
class LineDiffBudgetExceeded implements Exception {
  const LineDiffBudgetExceeded();
}

/// An exact LCS line diff with at most one million uint32 matrix cells.
class LineDiff {
  const LineDiff._();

  /// LCS-based unified line diff. [leftInput] lines absent from the LCS are
  /// [DiffLineKind.removed]; [rightInput] lines absent from the LCS are
  /// [DiffLineKind.added]; LCS lines are [DiffLineKind.equal]. Within a changed
  /// hunk, all removed lines precede added lines (unified-diff convention).
  static List<DiffLine> diff(List<String> leftInput, List<String> rightInput) {
    var prefix = 0;
    while (prefix < leftInput.length &&
        prefix < rightInput.length &&
        leftInput[prefix] == rightInput[prefix]) {
      prefix++;
    }
    final out = <DiffLine>[
      for (var i = 0; i < prefix; i++)
        DiffLine(DiffLineKind.equal, leftInput[i]),
    ];
    final left = leftInput.sublist(prefix);
    final right = rightInput.sublist(prefix);
    final n = left.length;
    final m = right.length;

    if (n == 0 || m == 0) {
      return out
        ..addAll(left.map((s) => DiffLine(DiffLineKind.removed, s)))
        ..addAll(right.map((s) => DiffLine(DiffLineKind.added, s)));
    }
    const maxCells = 1000000;
    if ((n + 1) * (m + 1) > maxCells) {
      throw const LineDiffBudgetExceeded();
    }

    // Flattened LCS table: one allocation, including highly asymmetric input.
    final width = m + 1;
    final lcs = Uint32List((n + 1) * width);
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        if (left[i] == right[j]) {
          lcs[i * width + j] = lcs[(i + 1) * width + j + 1] + 1;
        } else {
          final down = lcs[(i + 1) * width + j];
          final across = lcs[i * width + j + 1];
          lcs[i * width + j] = down >= across ? down : across;
        }
      }
    }

    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (left[i] == right[j]) {
        out.add(DiffLine(DiffLineKind.equal, left[i]));
        i++;
        j++;
      } else if (lcs[(i + 1) * width + j] >= lcs[i * width + j + 1]) {
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
