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

  group('UTF-16 surrogate boundary safety', () {
    test(
      'window start landing on LOW surrogate is nudged off boundary',
      () {
        // Repro: emoji at position 500 (code units 500–501,
        // high=0xD83D low=0xDE00). If windowStart is computed to land on the
        // LOW surrogate (501), the window must be shifted to avoid slicing
        // mid-emoji.
        const emoji = '😀'; // 2 code units: D83D DE00
        final haystack = 'x' * 500 + emoji + 'y' * 5000;
        const offset = 500; // The emoji starts here
        final w = buildPlainTextFindWindow(
          haystack: haystack,
          offsets: [offset],
          currentMatch: 0,
          matchLength: emoji.length,
          windowChars: 256, // Small enough to force boundary case
        );
        // Assert: window.text never starts with a lone LOW surrogate.
        if (w.text.isNotEmpty) {
          final firstCodeUnit = w.text.codeUnitAt(0);
          expect(
            firstCodeUnit < 0xDC00 || firstCodeUnit > 0xDFFF,
            isTrue,
            reason: 'window.text[0] must not be a lone LOW surrogate',
          );
        }
        // Assert: window.text never ends with a lone HIGH surrogate.
        if (w.text.isNotEmpty) {
          final lastCodeUnit = w.text.codeUnitAt(w.text.length - 1);
          expect(
            lastCodeUnit < 0xD800 || lastCodeUnit > 0xDBFF,
            isTrue,
            reason: 'window.text[-1] must not be a lone HIGH surrogate',
          );
        }
        // Assert: the highlight text still matches the true match.
        if (w.highlights.isNotEmpty) {
          final h = w.highlights.first;
          final highlightText = w.text.substring(h.start, h.end);
          expect(highlightText, emoji);
        }
      },
    );

    test(
      'emoji-dense haystack: all windows stay off surrogate boundaries',
      () {
        // Build haystack with emoji at regular intervals.
        const emoji = '🎉'; // 2 code units each
        const pattern = 'ab🎉';
        final haystackBuffer = StringBuffer();
        final offsets = <int>[];
        for (var i = 0; i < 50; i++) {
          offsets.add(haystackBuffer.length + 2); // Mark emoji start
          haystackBuffer.write(pattern);
        }
        final haystack = haystackBuffer.toString();
        // Test several match positions to ensure boundary safety everywhere.
        for (var idx = 0; idx < offsets.length; idx += 5) {
          final w = buildPlainTextFindWindow(
            haystack: haystack,
            offsets: offsets,
            currentMatch: idx,
            matchLength: emoji.length,
            windowChars: 128,
          );
          // Assert no lone surrogates at window boundaries.
          if (w.text.isNotEmpty) {
            final firstCodeUnit = w.text.codeUnitAt(0);
            expect(
              firstCodeUnit < 0xDC00 || firstCodeUnit > 0xDFFF,
              isTrue,
              reason: 'Match $idx: window.text[0] is a lone LOW surrogate',
            );
            final lastCodeUnit = w.text.codeUnitAt(w.text.length - 1);
            expect(
              lastCodeUnit < 0xD800 || lastCodeUnit > 0xDBFF,
              isTrue,
              reason: 'Match $idx: window.text[-1] is a lone HIGH surrogate',
            );
          }
        }
      },
    );
  });
}
