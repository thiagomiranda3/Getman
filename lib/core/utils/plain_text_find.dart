// Pure helpers for finding text in large plain-text response bodies (C1
// "find everywhere"): a compute()-friendly case-insensitive offset scan plus
// windowed snippet slicing/span building, so highlight cost stays independent
// of total body size. Consumed by LargeBodyFindView
// (features/tabs/.../response/large_body_find_view.dart); highlight colors
// come from AppPalette.findMatchHighlight/-ActiveHighlight at the call site.
import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

/// Total characters of the snippet window sliced around the current match.
/// 4 KiB keeps RichText span building trivially cheap regardless of body size.
const int kPlainTextFindWindowChars = 4 * 1024;

/// Argument object for [findMatchOffsets] — a single value so the scan can
/// run off the UI isolate via `compute()` (one-argument entry point).
class PlainTextFindArgs extends Equatable {
  const PlainTextFindArgs({required this.haystack, required this.query});

  /// The full verbatim body text to scan.
  final String haystack;

  /// The literal (non-regex) query; matching is case-insensitive.
  final String query;

  @override
  List<Object?> get props => [haystack, query];
}

/// Scans [PlainTextFindArgs.haystack] for every non-overlapping,
/// case-insensitive occurrence of [PlainTextFindArgs.query] and returns the
/// match start offsets in ascending order.
///
/// Top-level (not a method) so callers can run it via `compute()` — the scan
/// over a multi-MiB body must stay off the UI isolate.
List<int> findMatchOffsets(PlainTextFindArgs args) {
  final query = args.query.toLowerCase();
  if (query.isEmpty) return const [];
  final haystack = args.haystack.toLowerCase();
  final out = <int>[];
  var i = haystack.indexOf(query);
  while (i != -1) {
    out.add(i);
    i = haystack.indexOf(query, i + query.length);
  }
  return out;
}

/// A snippet window over the full body, centered on the current match, with
/// match ranges rebased to the window text — everything a highlight-span
/// renderer needs without touching the full body again.
class PlainTextFindWindow extends Equatable {
  const PlainTextFindWindow({
    required this.text,
    required this.windowStart,
    required this.highlights,
    required this.activeHighlight,
    required this.clippedStart,
    required this.clippedEnd,
  });

  /// The window substring (at most `windowChars` characters).
  final String text;

  /// Offset of [text]'s first character within the full haystack.
  final int windowStart;

  /// Match ranges **relative to [text]**, clamped to the window, ascending.
  final List<TextRange> highlights;

  /// Index into [highlights] of the current (n/N) match.
  final int activeHighlight;

  /// True when body text exists before the window (render a leading "…").
  final bool clippedStart;

  /// True when body text exists after the window (render a trailing "…").
  final bool clippedEnd;

  @override
  List<Object?> get props => [
    text,
    windowStart,
    highlights,
    activeHighlight,
    clippedStart,
    clippedEnd,
  ];
}

/// Slices a [PlainTextFindWindow] out of [haystack], centered on
/// `offsets[currentMatch]` (a match of [matchLength] characters), clamped to
/// the haystack bounds. All matches that intersect the window are rebased
/// into window-relative [PlainTextFindWindow.highlights].
PlainTextFindWindow buildPlainTextFindWindow({
  required String haystack,
  required List<int> offsets,
  required int currentMatch,
  required int matchLength,
  int windowChars = kPlainTextFindWindowChars,
}) {
  assert(offsets.isNotEmpty, 'need at least one match to build a window');
  assert(
    currentMatch >= 0 && currentMatch < offsets.length,
    'currentMatch out of range',
  );
  final length = haystack.length;
  final center = offsets[currentMatch] + matchLength ~/ 2;
  var start = center - windowChars ~/ 2;
  if (start < 0) start = 0;
  var end = start + windowChars;
  if (end > length) {
    end = length;
    start = end - windowChars;
    if (start < 0) start = 0;
  }

  final text = haystack.substring(start, end);
  final highlights = <TextRange>[];
  var active = 0;
  for (var i = 0; i < offsets.length; i++) {
    final o = offsets[i];
    if (o + matchLength <= start || o >= end) continue;
    if (i == currentMatch) active = highlights.length;
    highlights.add(
      TextRange(
        start: (o - start).clamp(0, text.length),
        end: (o + matchLength - start).clamp(0, text.length),
      ),
    );
  }
  return PlainTextFindWindow(
    text: text,
    windowStart: start,
    highlights: highlights,
    activeHighlight: active,
    clippedStart: start > 0,
    clippedEnd: end < length,
  );
}

/// Builds the highlight spans for a window: base-styled text with
/// [matchColor] behind every match and [activeMatchColor] behind the current
/// one. The concatenated span text always equals [PlainTextFindWindow.text].
List<InlineSpan> buildPlainTextFindSpans(
  PlainTextFindWindow window, {
  required TextStyle baseStyle,
  required Color matchColor,
  required Color activeMatchColor,
}) {
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (var i = 0; i < window.highlights.length; i++) {
    final h = window.highlights[i];
    if (h.start > cursor) {
      spans.add(
        TextSpan(
          text: window.text.substring(cursor, h.start),
          style: baseStyle,
        ),
      );
    }
    spans.add(
      TextSpan(
        text: window.text.substring(h.start, h.end),
        style: baseStyle.copyWith(
          backgroundColor: i == window.activeHighlight
              ? activeMatchColor
              : matchColor,
        ),
      ),
    );
    cursor = h.end;
  }
  if (cursor < window.text.length) {
    spans.add(TextSpan(text: window.text.substring(cursor), style: baseStyle));
  }
  return spans;
}
