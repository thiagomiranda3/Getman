import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/line_diff.dart';

void main() {
  group('LineDiff.diff', () {
    test('identical inputs are all equal', () {
      final out = LineDiff.diff(['a', 'b', 'c'], ['a', 'b', 'c']);
      expect(out.map((l) => l.kind), everyElement(DiffLineKind.equal));
      expect(out.map((l) => l.text).toList(), ['a', 'b', 'c']);
    });

    test('pure insertion marks the new line added', () {
      final out = LineDiff.diff(['a', 'c'], ['a', 'b', 'c']);
      expect(out, const [
        DiffLine(DiffLineKind.equal, 'a'),
        DiffLine(DiffLineKind.added, 'b'),
        DiffLine(DiffLineKind.equal, 'c'),
      ]);
    });

    test('pure deletion marks the dropped line removed', () {
      final out = LineDiff.diff(['a', 'b', 'c'], ['a', 'c']);
      expect(out, const [
        DiffLine(DiffLineKind.equal, 'a'),
        DiffLine(DiffLineKind.removed, 'b'),
        DiffLine(DiffLineKind.equal, 'c'),
      ]);
    });

    test('replacement emits removed before added (unified order)', () {
      final out = LineDiff.diff(['a', 'x', 'c'], ['a', 'y', 'c']);
      expect(out, const [
        DiffLine(DiffLineKind.equal, 'a'),
        DiffLine(DiffLineKind.removed, 'x'),
        DiffLine(DiffLineKind.added, 'y'),
        DiffLine(DiffLineKind.equal, 'c'),
      ]);
    });

    test('empty left yields all added', () {
      final out = LineDiff.diff(const [], ['a', 'b']);
      expect(out, const [
        DiffLine(DiffLineKind.added, 'a'),
        DiffLine(DiffLineKind.added, 'b'),
      ]);
    });

    test('empty right yields all removed', () {
      final out = LineDiff.diff(['a', 'b'], const []);
      expect(out, const [
        DiffLine(DiffLineKind.removed, 'a'),
        DiffLine(DiffLineKind.removed, 'b'),
      ]);
    });

    test('two empty inputs yield an empty diff', () {
      expect(LineDiff.diff(const [], const []), isEmpty);
    });
  });

  group('LineDiff.diffText', () {
    test('splits on newline and diffs line lists', () {
      final out = LineDiff.diffText('a\nb', 'a\nB');
      expect(out, const [
        DiffLine(DiffLineKind.equal, 'a'),
        DiffLine(DiffLineKind.removed, 'b'),
        DiffLine(DiffLineKind.added, 'B'),
      ]);
    });

    test('a single trailing newline does not add an empty line', () {
      final out = LineDiff.diffText('a\nb\n', 'a\nb\n');
      expect(out.map((l) => l.text).toList(), ['a', 'b']);
      expect(out.map((l) => l.kind), everyElement(DiffLineKind.equal));
    });

    test('empty strings diff to an empty list', () {
      expect(LineDiff.diffText('', ''), isEmpty);
    });
  });
}
