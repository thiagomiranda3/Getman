import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/plain_text_find.dart';

void main() {
  group('findMatchOffsets', () {
    test('finds every case-insensitive occurrence', () {
      const args = PlainTextFindArgs(
        haystack: 'Alpha beta ALPHA alphabet',
        query: 'alpha',
      );
      expect(findMatchOffsets(args), [0, 11, 17]);
    });

    test('empty query yields no matches', () {
      const args = PlainTextFindArgs(haystack: 'anything', query: '');
      expect(findMatchOffsets(args), isEmpty);
    });

    test('no occurrence yields no matches', () {
      const args = PlainTextFindArgs(haystack: 'aaa', query: 'zzz');
      expect(findMatchOffsets(args), isEmpty);
    });

    test('matches are non-overlapping', () {
      const args = PlainTextFindArgs(haystack: 'aaaa', query: 'aa');
      expect(findMatchOffsets(args), [0, 2]);
    });
  });

  group('buildPlainTextFindWindow', () {
    test('small haystack: whole text, no clipping, relative highlights', () {
      final w = buildPlainTextFindWindow(
        haystack: 'one two one',
        offsets: const [0, 8],
        currentMatch: 1,
        matchLength: 3,
      );
      expect(w.text, 'one two one');
      expect(w.windowStart, 0);
      expect(w.clippedStart, isFalse);
      expect(w.clippedEnd, isFalse);
      expect(w.highlights, const [
        TextRange(start: 0, end: 3),
        TextRange(start: 8, end: 11),
      ]);
      expect(w.activeHighlight, 1);
    });

    test('large haystack: window is centered on the current match and '
        'excludes far-away matches', () {
      final haystack =
          'N${'a' * 10000}N${'b' * 10000}N'; // matches at 0, 10001, 20002
      final w = buildPlainTextFindWindow(
        haystack: haystack,
        offsets: const [0, 10001, 20002],
        currentMatch: 1,
        matchLength: 1,
      );
      expect(w.text.length, 4096);
      expect(w.clippedStart, isTrue);
      expect(w.clippedEnd, isTrue);
      // Only the middle match is inside the window; it is the active one.
      expect(w.highlights.length, 1);
      expect(w.activeHighlight, 0);
      // The match sits at its offset relative to the window.
      final h = w.highlights.single;
      expect(w.windowStart + h.start, 10001);
      expect(w.text.substring(h.start, h.end), 'N');
    });

    test('window clamps at the start of the haystack', () {
      final w = buildPlainTextFindWindow(
        haystack: 'M${'x' * 9999}',
        offsets: const [0],
        currentMatch: 0,
        matchLength: 1,
      );
      expect(w.windowStart, 0);
      expect(w.clippedStart, isFalse);
      expect(w.clippedEnd, isTrue);
      expect(w.highlights.single, const TextRange(start: 0, end: 1));
    });

    test('window clamps at the end of the haystack', () {
      final haystack = '${'x' * 9999}M';
      final w = buildPlainTextFindWindow(
        haystack: haystack,
        offsets: const [9999],
        currentMatch: 0,
        matchLength: 1,
      );
      expect(w.windowStart, haystack.length - 4096);
      expect(w.clippedStart, isTrue);
      expect(w.clippedEnd, isFalse);
      final h = w.highlights.single;
      expect(w.windowStart + h.start, 9999);
    });
  });

  group('buildPlainTextFindSpans', () {
    const base = TextStyle(fontSize: 12);
    const match = Color(0x4D0000FF);
    const active = Color(0xA60000FF);

    test('partitions the window text and colors matches', () {
      final w = buildPlainTextFindWindow(
        haystack: 'one two one',
        offsets: const [0, 8],
        currentMatch: 1,
        matchLength: 3,
      );
      final spans = buildPlainTextFindSpans(
        w,
        baseStyle: base,
        matchColor: match,
        activeMatchColor: active,
      );
      final texts = spans.map((s) => (s as TextSpan).text).toList();
      expect(texts.join(), 'one two one');
      expect(texts, ['one', ' two ', 'one']);
      expect(
        (spans[0] as TextSpan).style?.backgroundColor,
        match,
        reason: 'non-current match uses the normal highlight',
      );
      expect((spans[1] as TextSpan).style?.backgroundColor, isNull);
      expect(
        (spans[2] as TextSpan).style?.backgroundColor,
        active,
        reason: 'the current match uses the active highlight',
      );
    });

    test('no highlights yields one base span', () {
      const w = PlainTextFindWindow(
        text: 'abc',
        windowStart: 0,
        highlights: [],
        activeHighlight: 0,
        clippedStart: false,
        clippedEnd: false,
      );
      final spans = buildPlainTextFindSpans(
        w,
        baseStyle: base,
        matchColor: match,
        activeMatchColor: active,
      );
      expect(spans.length, 1);
      expect((spans.single as TextSpan).text, 'abc');
    });
  });
}
