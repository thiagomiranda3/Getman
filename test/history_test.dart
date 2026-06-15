import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:mocktail/mocktail.dart';

class MockHistoryRepository extends Mock implements HistoryRepository {}

void main() {
  late MockHistoryRepository mockRepository;
  late StreamController<List<HttpRequestConfigEntity>> watchController;

  HistoryBloc buildBloc() =>
      HistoryBloc(watchHistoryUseCase: WatchHistoryUseCase(mockRepository));

  setUp(() {
    mockRepository = MockHistoryRepository();
    watchController = StreamController<List<HttpRequestConfigEntity>>();
    when(
      () => mockRepository.watchHistory(),
    ).thenAnswer((_) => watchController.stream);
  });

  tearDown(() => watchController.close());

  const tConfig = HttpRequestConfigEntity(
    id: '1',
    url: 'https://example.com',
  );

  test(
    'starts loading until the watch stream delivers the initial list',
    () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      expect(bloc.state.isLoading, isTrue);

      watchController.add(const [tConfig]);
      await expectLater(
        bloc.stream,
        emits(const HistoryState(history: [tConfig])),
      );
    },
  );

  test(
    'updates state on every subsequent watch emission, newest list winning',
    () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      watchController
        ..add(const [tConfig])
        ..add(const []);

      await expectLater(
        bloc.stream,
        emitsInOrder([
          const HistoryState(history: [tConfig]),
          const HistoryState(),
        ]),
      );
    },
  );

  test('ignores emissions arriving after close instead of throwing', () async {
    final bloc = buildBloc();
    await bloc.close();
    // Must not throw "Cannot add new events after calling close".
    watchController.add(const [tConfig]);
    await Future<void>.delayed(Duration.zero);
  });
}
