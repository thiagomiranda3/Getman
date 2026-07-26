// Unit tests for the history use-case wrappers: each delegates to the
// abstract HistoryRepository with the exact arguments it was given.

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:mocktail/mocktail.dart';

class _MockHistoryRepository extends Mock implements HistoryRepository {}

void main() {
  late _MockHistoryRepository repository;
  const config = HttpRequestConfigEntity(id: 'c1');

  setUp(() => repository = _MockHistoryRepository());

  test('AddToHistoryUseCase delegates the config and limit', () async {
    when(() => repository.addToHistory(config, 25)).thenAnswer((_) async {});

    await AddToHistoryUseCase(repository).call(config, 25);

    verify(() => repository.addToHistory(config, 25)).called(1);
    verifyNoMoreInteractions(repository);
  });

  test('WatchHistoryUseCase returns the repository stream', () {
    when(
      () => repository.watchHistory(),
    ).thenAnswer((_) => Stream.value(const [config]));

    expect(
      WatchHistoryUseCase(repository).call(),
      emits(const [config]),
    );
  });

  test('DeleteHistoryEntryUseCase delegates the entry id', () async {
    when(() => repository.deleteHistoryEntry('h1')).thenAnswer((_) async {});

    await DeleteHistoryEntryUseCase(repository).call('h1');

    verify(() => repository.deleteHistoryEntry('h1')).called(1);
    verifyNoMoreInteractions(repository);
  });

  test('ClearHistoryUseCase delegates', () async {
    when(() => repository.clearHistory()).thenAnswer((_) async {});

    await ClearHistoryUseCase(repository).call();

    verify(() => repository.clearHistory()).called(1);
    verifyNoMoreInteractions(repository);
  });

  test('RestoreHistoryEntriesUseCase delegates the entries', () async {
    when(
      () => repository.restoreHistoryEntries(const [config]),
    ).thenAnswer((_) async {});

    await RestoreHistoryEntriesUseCase(repository).call(const [config]);

    verify(() => repository.restoreHistoryEntries(const [config])).called(1);
    verifyNoMoreInteractions(repository);
  });
}
