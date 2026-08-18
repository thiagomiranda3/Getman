import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/bulk_kv_codec.dart';

void main() {
  group('BulkKvCodec.serialize', () {
    test('empty list serializes to empty string', () {
      expect(BulkKvCodec.serialize(const []), '');
    });

    test('rows become one "key: value" line each, canonical order', () {
      final text = BulkKvCodec.serialize(const [
        ('Accept', '*/*'),
        ('Authorization', 'Bearer abc'),
      ]);
      expect(text, 'Accept: */*\nAuthorization: Bearer abc');
    });

    test('value is emitted verbatim (no trimming on serialize)', () {
      expect(
        BulkKvCodec.serialize(const [('X', '  spaced  ')]),
        'X:   spaced  ',
      );
    });

    test('empty-key rows are skipped', () {
      expect(BulkKvCodec.serialize(const [('', 'orphan'), ('K', 'v')]), 'K: v');
    });

    test('a key with an empty value still emits "key: "', () {
      expect(BulkKvCodec.serialize(const [('Accept', '')]), 'Accept: ');
    });
  });

  group('BulkKvCodec.parse', () {
    test('empty / whitespace-only input yields no rows', () {
      expect(BulkKvCodec.parse(''), const <(String, String)>[]);
      expect(BulkKvCodec.parse('   \n\t\n  '), const <(String, String)>[]);
    });

    test('splits on the first colon and trims both sides (D2)', () {
      expect(BulkKvCodec.parse('Accept :  */*  '), const [('Accept', '*/*')]);
    });

    test(
      'value containing a colon keeps everything after the first one (D2)',
      () {
        expect(
          BulkKvCodec.parse('Authorization: Bearer a:b'),
          const [('Authorization', 'Bearer a:b')],
        );
      },
    );

    test('a line with no colon becomes (key, "") (D3)', () {
      expect(BulkKvCodec.parse('Accept'), const [('Accept', '')]);
    });

    test('blank lines between pairs are dropped (D4)', () {
      expect(
        BulkKvCodec.parse('A: 1\n\n   \nB: 2'),
        const [('A', '1'), ('B', '2')],
      );
    });

    test('a line whose key trims to empty is dropped (D5)', () {
      expect(BulkKvCodec.parse(': value'), const <(String, String)>[]);
      expect(BulkKvCodec.parse('   : x'), const <(String, String)>[]);
    });

    test('trailing newline produces no phantom pair (D4)', () {
      expect(BulkKvCodec.parse('A: 1\n'), const [('A', '1')]);
    });

    test('duplicate keys are preserved in order', () {
      expect(
        BulkKvCodec.parse('tag: a\ntag: b'),
        const [('tag', 'a'), ('tag', 'b')],
      );
    });
  });

  group('round-trip parse(serialize(rows)) == rows', () {
    test('representative canonical rows survive a round-trip', () {
      const rows = [
        ('Accept', '*/*'),
        ('Authorization', 'Bearer a:b'),
        ('Empty', ''),
        ('tag', 'a'),
        ('tag', 'b'),
      ];
      expect(BulkKvCodec.parse(BulkKvCodec.serialize(rows)), rows);
    });
  });

  group('BulkKvCodec.serializeRows / parseRows — // disabled rows (B1)', () {
    test('a disabled row serializes with a leading //', () {
      final text = BulkKvCodec.serializeRows(const [
        (key: 'A', value: '1', disabled: false),
        (key: 'B', value: '2', disabled: true),
      ]);
      expect(text, 'A: 1\n//B: 2');
    });

    test('a leading // parses as a disabled row, prefix stripped', () {
      expect(BulkKvCodec.parseRows('A: 1\n//B: 2'), const [
        (key: 'A', value: '1', disabled: false),
        (key: 'B', value: '2', disabled: true),
      ]);
    });

    test('whitespace after // is tolerated', () {
      expect(BulkKvCodec.parseRows('//  B : 2 '), const [
        (key: 'B', value: '2', disabled: true),
      ]);
    });

    test('a bare // line or //-only key is dropped', () {
      expect(BulkKvCodec.parseRows('//'), isEmpty);
      expect(BulkKvCodec.parseRows('//: v'), isEmpty);
    });

    test('a disabled line with no colon keeps an empty value', () {
      expect(BulkKvCodec.parseRows('//JustKey'), const [
        (key: 'JustKey', value: '', disabled: true),
      ]);
    });

    test('round-trip preserves disabled flags and order', () {
      const rows = [
        (key: 'A', value: '1', disabled: false),
        (key: 'B', value: '2', disabled: true),
        (key: 'tag', value: 'x', disabled: true),
        (key: 'tag', value: 'y', disabled: false),
      ];
      expect(
        BulkKvCodec.parseRows(BulkKvCodec.serializeRows(rows)),
        rows,
      );
    });

    test('legacy parse strips // and keeps the row (enabled-only view)', () {
      expect(BulkKvCodec.parse('//B: 2'), const [('B', '2')]);
    });
  });

  group('value escaping — newline / backslash round-trips (I12)', () {
    test('a newline-bearing value serializes to ONE escaped line', () {
      final text = BulkKvCodec.serializeRows(const [
        (key: 'X-Note', value: 'line1\nline2: tail', disabled: false),
      ]);
      expect(text, r'X-Note: line1\nline2: tail');
      expect(text.contains('\n'), isFalse);
    });

    test('edit→bulk→edit is identity for a newline-bearing value', () {
      const rows = [
        (key: 'X-Note', value: 'line1\nline2: tail', disabled: false),
      ];
      expect(BulkKvCodec.parseRows(BulkKvCodec.serializeRows(rows)), rows);
    });

    test('backslash-bearing values round-trip (escape/unescape inverse)', () {
      const rows = [
        (key: 'Path', value: r'C:\new\folder', disabled: false),
        (key: 'Regex', value: r'\d+\\n', disabled: true),
        (key: 'Trail', value: r'ends-with\', disabled: false),
      ];
      expect(BulkKvCodec.parseRows(BulkKvCodec.serializeRows(rows)), rows);
    });

    test('a disabled newline-bearing row keeps its // prefix and value', () {
      const rows = [(key: 'B', value: 'v1\nv2', disabled: true)];
      final text = BulkKvCodec.serializeRows(rows);
      expect(text, r'//B: v1\nv2');
      expect(BulkKvCodec.parseRows(text), rows);
    });

    test('leading/trailing newlines survive the D2 trim via escaping', () {
      const rows = [(key: 'K', value: '\nx\n', disabled: false)];
      expect(BulkKvCodec.parseRows(BulkKvCodec.serializeRows(rows)), rows);
    });

    test('legacy bulk text without escape sequences parses unchanged', () {
      // `\t`-like pairs and a trailing lone backslash are not escapes the
      // grammar defines — they pass through verbatim.
      expect(BulkKvCodec.parseRows(r'K: path\to\x'), const [
        (key: 'K', value: r'path\to\x', disabled: false),
      ]);
      expect(BulkKvCodec.parseRows(r'K2: raw\'), const [
        (key: 'K2', value: r'raw\', disabled: false),
      ]);
      expect(BulkKvCodec.parse('A: plain value'), const [
        ('A', 'plain value'),
      ]);
    });

    test(r'a typed \n in bulk text is the documented newline escape', () {
      expect(BulkKvCodec.parseRows(r'X: a\nb'), const [
        (key: 'X', value: 'a\nb', disabled: false),
      ]);
      expect(BulkKvCodec.parseRows(r'X: a\\nb'), const [
        (key: 'X', value: r'a\nb', disabled: false),
      ]);
    });
  });
}
