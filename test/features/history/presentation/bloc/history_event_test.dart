// Equality/props tests for every HistoryBloc event: equal instances compare
// equal, and each constructor field participates in Equatable props.

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';

void main() {
  const a = HttpRequestConfigEntity(id: 'a');
  const b = HttpRequestConfigEntity(id: 'b');

  group('HistoryUpdated', () {
    test('equal instances compare equal', () {
      expect(
        const HistoryUpdated([a, b]),
        equals(const HistoryUpdated([a, b])),
      );
      expect(
        const HistoryUpdated([a]).hashCode,
        const HistoryUpdated([a]).hashCode,
      );
    });

    test('differs when the history list differs', () {
      expect(const HistoryUpdated([a]), isNot(const HistoryUpdated([b])));
      expect(const HistoryUpdated([a]), isNot(const HistoryUpdated([a, b])));
    });

    test('props expose the history list', () {
      expect(const HistoryUpdated([a]).props, [
        const [a],
      ]);
    });
  });

  group('DeleteHistoryEntry', () {
    test('equal instances compare equal, differs by id', () {
      expect(
        const DeleteHistoryEntry('h1'),
        equals(const DeleteHistoryEntry('h1')),
      );
      expect(
        const DeleteHistoryEntry('h1'),
        isNot(const DeleteHistoryEntry('h2')),
      );
    });

    test('props expose the id', () {
      expect(const DeleteHistoryEntry('h1').props, ['h1']);
    });
  });

  group('ClearHistory', () {
    test('all instances compare equal (no fields)', () {
      expect(const ClearHistory(), equals(const ClearHistory()));
      expect(const ClearHistory().props, isEmpty);
    });

    test('is not equal to a different event type', () {
      expect(const ClearHistory(), isNot(const DeleteHistoryEntry('h1')));
    });
  });

  group('RestoreHistoryEntries', () {
    test('equal instances compare equal', () {
      expect(
        const RestoreHistoryEntries([a]),
        equals(const RestoreHistoryEntries([a])),
      );
    });

    test('differs when the entries differ', () {
      expect(
        const RestoreHistoryEntries([a]),
        isNot(const RestoreHistoryEntries([b])),
      );
      expect(
        const RestoreHistoryEntries([a]),
        isNot(const RestoreHistoryEntries([a, b])),
      );
    });

    test('props expose the entries', () {
      expect(const RestoreHistoryEntries([a, b]).props, [
        const [a, b],
      ]);
    });
  });
}
