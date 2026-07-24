import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/parked_param_entity.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/utils/param_row_composer.dart';

void main() {
  QueryParamEntity q(String k, String v) => QueryParamEntity(key: k, value: v);
  ParkedParamEntity p(String k, String v, int i) =>
      ParkedParamEntity(key: k, value: v, rowIndex: i);
  ParamRow en(String k, String v) => ParamRow(key: k, value: v, enabled: true);
  ParamRow pk(String k, String v) => ParamRow(key: k, value: v, enabled: false);

  group('compose', () {
    test('empty inputs compose to an empty row list', () {
      expect(
        ParamRowComposer.compose(params: const [], parked: const []),
        isEmpty,
      );
    });

    test('parked rows interleave at their remembered rowIndex', () {
      final rows = ParamRowComposer.compose(
        params: [q('a', '1'), q('c', '3')],
        parked: [p('b', '2', 1)],
      );
      expect(rows, [en('a', '1'), pk('b', '2'), en('c', '3')]);
    });

    test('a rowIndex beyond the end clamps to the last position', () {
      final rows = ParamRowComposer.compose(
        params: [q('a', '1')],
        parked: [p('z', '9', 99)],
      );
      expect(rows, [en('a', '1'), pk('z', '9')]);
    });

    test('equal rowIndexes keep original parked-list order (stable)', () {
      final rows = ParamRowComposer.compose(
        params: const [],
        parked: [p('p', '1', 0), p('q', '2', 0)],
      );
      expect(rows, [pk('p', '1'), pk('q', '2')]);
    });

    test('duplicate keys are preserved in both populations', () {
      final rows = ParamRowComposer.compose(
        params: [q('tag', 'a'), q('tag', 'b')],
        parked: [p('tag', 'c', 1)],
      );
      expect(rows, [en('tag', 'a'), pk('tag', 'c'), en('tag', 'b')]);
    });

    test('tied rowIndex with clamping maintains stable sort order', () {
      // Regression: both m and n clamp to position 1 but must appear in
      // sorted order [m, n], not reversed [n, m].
      final rows = ParamRowComposer.compose(
        params: [q('a', '1')],
        parked: [p('m', '0', 99), p('n', '9', 99)],
      );
      expect(rows, [en('a', '1'), pk('m', '0'), pk('n', '9')]);
    });
  });

  group('park', () {
    test('parks the row at displayIndex and removes it from params', () {
      final result = ParamRowComposer.park(
        params: [q('a', '1'), q('b', '2'), q('c', '3')],
        parked: const [],
        displayIndex: 1,
      );
      expect(result.params, [q('a', '1'), q('c', '3')]);
      expect(result.parked, [p('b', '2', 1)]);
      // Round-trip: composing the result reproduces the visual sequence.
      expect(
        ParamRowComposer.compose(params: result.params, parked: result.parked),
        [en('a', '1'), pk('b', '2'), en('c', '3')],
      );
    });

    test('parking below an existing parked row targets the right param', () {
      // Composed view: [a(en), x(pk@1), b(en)] — display 2 is param b.
      final result = ParamRowComposer.park(
        params: [q('a', '1'), q('b', '2')],
        parked: [p('x', '0', 1)],
        displayIndex: 2,
      );
      expect(result.params, [q('a', '1')]);
      expect(result.parked, [p('x', '0', 1), p('b', '2', 2)]);
      expect(
        ParamRowComposer.compose(params: result.params, parked: result.parked),
        [en('a', '1'), pk('x', '0'), pk('b', '2')],
      );
    });

    test('is a no-op for an out-of-range or already-parked index', () {
      final params = [q('a', '1')];
      final parked = [p('x', '0', 1)];
      expect(
        ParamRowComposer.park(params: params, parked: parked, displayIndex: 9),
        (params: params, parked: parked),
      );
      expect(
        ParamRowComposer.park(params: params, parked: parked, displayIndex: 1),
        (params: params, parked: parked),
      );
    });
  });

  group('unpark', () {
    test(
      're-inserts into params at the position implied by the display slot',
      () {
        final result = ParamRowComposer.unpark(
          params: [q('a', '1'), q('c', '3')],
          parked: [p('b', '2', 1)],
          displayIndex: 1,
        );
        expect(result.params, [q('a', '1'), q('b', '2'), q('c', '3')]);
        expect(result.parked, isEmpty);
      },
    );

    test('clamps a stale out-of-range rowIndex on re-insert', () {
      // z was parked at 99; composed view is [a, z] so display 1 unparks it.
      final result = ParamRowComposer.unpark(
        params: [q('a', '1')],
        parked: [p('z', '9', 99)],
        displayIndex: 1,
      );
      expect(result.params, [q('a', '1'), q('z', '9')]);
      expect(result.parked, isEmpty);
    });

    test('unparks the right entity when several are parked', () {
      // Composed: [a(en), x(pk@1), b(en), y(pk@3)] — display 3 is y.
      final result = ParamRowComposer.unpark(
        params: [q('a', '1'), q('b', '2')],
        parked: [p('x', '0', 1), p('y', '9', 3)],
        displayIndex: 3,
      );
      expect(result.params, [q('a', '1'), q('b', '2'), q('y', '9')]);
      expect(result.parked, [p('x', '0', 1)]);
    });

    test('is a no-op for an enabled or out-of-range index', () {
      final params = [q('a', '1')];
      final parked = [p('x', '0', 1)];
      expect(
        ParamRowComposer.unpark(
          params: params,
          parked: parked,
          displayIndex: 0,
        ),
        (params: params, parked: parked),
      );
      expect(
        ParamRowComposer.unpark(
          params: params,
          parked: parked,
          displayIndex: -1,
        ),
        (params: params, parked: parked),
      );
    });

    test('unpark on tied+clamped input removes the correct entity', () {
      // Regression: unparking displayIndex 1 should remove m, not n.
      final result = ParamRowComposer.unpark(
        params: [q('a', '1')],
        parked: [p('m', '0', 99), p('n', '9', 99)],
        displayIndex: 1,
      );
      expect(result.params, [q('a', '1'), q('m', '0')]);
      expect(result.parked, [p('n', '9', 99)]);
    });

    test('park/unpark round-trip is lossless on tied+clamped input', () {
      // Regression: compose with tied+clamped parked items must be reversible.
      final initial = (
        params: [q('a', '1')],
        parked: [p('m', '0', 99), p('n', '9', 99)],
      );
      // Compose: [a(en), m(pk@1), n(pk@2)]
      final composed = ParamRowComposer.compose(
        params: initial.params,
        parked: initial.parked,
      );
      expect(composed, [en('a', '1'), pk('m', '0'), pk('n', '9')]);

      // Unpark displayIndex 1 (m): should remove m from parked, add to params.
      final unparked = ParamRowComposer.unpark(
        params: initial.params,
        parked: initial.parked,
        displayIndex: 1,
      );
      expect(unparked.params, [q('a', '1'), q('m', '0')]);
      expect(unparked.parked, [p('n', '9', 99)]);

      // Verify the unpark result recomposes correctly.
      final recomposed = ParamRowComposer.compose(
        params: unparked.params,
        parked: unparked.parked,
      );
      expect(recomposed, [en('a', '1'), en('m', '0'), pk('n', '9')]);
    });
  });

  group('decompose', () {
    test('a text edit on an enabled row keeps the parked row parked', () {
      final result = ParamRowComposer.decompose(
        rows: [('a', '9'), ('b', '2'), ('', '')],
        parked: [p('b', '2', 1)],
      );
      expect(result.params, [q('a', '9')]);
      expect(result.parked, [p('b', '2', 1)]);
    });

    test('deleting an enabled row shifts the parked rowIndex down', () {
      // Was [a(en), b(pk@1), c(en)]; the user deleted a.
      final result = ParamRowComposer.decompose(
        rows: [('b', '2'), ('c', '3'), ('', '')],
        parked: [p('b', '2', 1)],
      );
      expect(result.params, [q('c', '3')]);
      expect(result.parked, [p('b', '2', 0)]);
    });

    test('deleting a parked row drops its entity', () {
      final result = ParamRowComposer.decompose(
        rows: [('a', '1'), ('c', '3'), ('', '')],
        parked: [p('b', '2', 1)],
      );
      expect(result.params, [q('a', '1'), q('c', '3')]);
      expect(result.parked, isEmpty);
    });

    test(
      'surviving parked rows still match when an earlier one was deleted',
      () {
        final result = ParamRowComposer.decompose(
          rows: [('y', '2'), ('', '')],
          parked: [p('x', '1', 0), p('y', '2', 2)],
        );
        expect(result.params, isEmpty);
        expect(result.parked, [p('y', '2', 0)]);
      },
    );

    test(
      'duplicate content stays parked at the nearest remembered position',
      () {
        // parked (a,1)@2; an identical enabled (a,1) sits at display 0.
        final result = ParamRowComposer.decompose(
          rows: [('a', '1'), ('x', '0'), ('a', '1'), ('', '')],
          parked: [p('a', '1', 2)],
        );
        expect(result.params, [q('a', '1'), q('x', '0')]);
        expect(result.parked, [p('a', '1', 2)]);
      },
    );

    test('empty-key rows are dropped and take no display slot', () {
      final result = ParamRowComposer.decompose(
        rows: [('a', '1'), ('', 'orphan'), ('b', '2')],
        parked: [p('b', '2', 1)],
      );
      expect(result.params, [q('a', '1')]);
      expect(result.parked, [p('b', '2', 1)]);
    });

    test('new rows (no content match) become enabled params', () {
      final result = ParamRowComposer.decompose(
        rows: [('a', '1'), ('new', 'row'), ('', '')],
        parked: const [],
      );
      expect(result.params, [q('a', '1'), q('new', 'row')]);
      expect(result.parked, isEmpty);
    });
  });
}
