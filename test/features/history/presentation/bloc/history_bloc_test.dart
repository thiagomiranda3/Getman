import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:mocktail/mocktail.dart';

class MockHistoryRepository extends Mock implements HistoryRepository {}

void main() {
  late MockHistoryRepository repo;
  late StreamController<List<HttpRequestConfigEntity>> controller;

  HttpRequestConfigEntity req(String url) =>
      HttpRequestConfigEntity(id: url, url: url);

  setUpAll(() {
    registerFallbackValue(<HttpRequestConfigEntity>[]);
  });

  setUp(() {
    repo = MockHistoryRepository();
    controller = StreamController<List<HttpRequestConfigEntity>>();
    when(() => repo.watchHistory()).thenAnswer((_) => controller.stream);
    when(() => repo.deleteHistoryEntry(any())).thenAnswer((_) async {});
    when(() => repo.clearHistory()).thenAnswer((_) async {});
    when(() => repo.restoreHistoryEntries(any())).thenAnswer((_) async {});
  });

  tearDown(() => controller.close());

  HistoryBloc build() => HistoryBloc(
    watchHistoryUseCase: WatchHistoryUseCase(repo),
    deleteHistoryEntryUseCase: DeleteHistoryEntryUseCase(repo),
    clearHistoryUseCase: ClearHistoryUseCase(repo),
    restoreHistoryEntriesUseCase: RestoreHistoryEntriesUseCase(repo),
  );

  test('starts loading, then mirrors the watched history', () async {
    final bloc = build();
    addTearDown(bloc.close);
    expect(bloc.state.isLoading, isTrue);

    controller.add([req('https://a.com')]);
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(bloc.state.isLoading, isFalse);
    expect(bloc.state.history.map((e) => e.url), ['https://a.com']);
  });

  test('updates on each subsequent emission', () async {
    final bloc = build();
    addTearDown(bloc.close);

    controller.add([req('https://a.com')]);
    await bloc.stream.firstWhere((s) => s.history.length == 1);
    controller.add([req('https://a.com'), req('https://b.com')]);
    await bloc.stream.firstWhere((s) => s.history.length == 2);

    expect(bloc.state.history.map((e) => e.url), [
      'https://a.com',
      'https://b.com',
    ]);
  });

  test(
    'close() cancels the subscription so later emissions are ignored',
    () async {
      final bloc = build();
      controller.add([req('https://a.com')]);
      await bloc.stream.firstWhere((s) => !s.isLoading);

      await bloc.close();

      // Emitting after close must not throw (the subscription is cancelled and
      // the listener also guards on isClosed).
      expect(() => controller.add([req('https://c.com')]), returnsNormally);
      expect(bloc.state.history.map((e) => e.url), ['https://a.com']);
    },
  );

  blocTest<HistoryBloc, HistoryState>(
    'DeleteHistoryEntry optimistically drops the entry and calls the use case',
    build: build,
    seed: () => HistoryState(
      history: [req('https://a.com'), req('https://b.com')],
    ),
    act: (bloc) => bloc.add(const DeleteHistoryEntry('https://a.com')),
    expect: () => [
      HistoryState(history: [req('https://b.com')]),
    ],
    verify: (_) =>
        verify(() => repo.deleteHistoryEntry('https://a.com')).called(1),
  );

  blocTest<HistoryBloc, HistoryState>(
    'ClearHistory optimistically empties the list and calls the use case',
    build: build,
    seed: () => HistoryState(history: [req('https://a.com')]),
    act: (bloc) => bloc.add(const ClearHistory()),
    expect: () => [const HistoryState()],
    verify: (_) => verify(() => repo.clearHistory()).called(1),
  );

  blocTest<HistoryBloc, HistoryState>(
    'RestoreHistoryEntries calls the use case and emits nothing itself '
    '(the watch stream pushes the merged list)',
    build: build,
    act: (bloc) => bloc.add(RestoreHistoryEntries([req('https://a.com')])),
    expect: () => <HistoryState>[],
    verify: (_) => verify(
      () => repo.restoreHistoryEntries(
        any(that: equals([req('https://a.com')])),
      ),
    ).called(1),
  );

  blocTest<HistoryBloc, HistoryState>(
    'a failed delete is logged, not thrown (optimistic state stands until '
    'the next watch emission)',
    build: () {
      when(() => repo.deleteHistoryEntry(any())).thenThrow(Exception('boom'));
      return build();
    },
    seed: () => HistoryState(history: [req('https://a.com')]),
    act: (bloc) => bloc.add(const DeleteHistoryEntry('https://a.com')),
    expect: () => [const HistoryState()],
    errors: List<Matcher>.empty,
  );
}
