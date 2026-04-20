import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';

class MockHistoryRepository extends Mock implements HistoryRepository {}

class _FakeHttpRequestConfigEntity extends Fake implements HttpRequestConfigEntity {}

void main() {
  late MockHistoryRepository mockRepository;
  late GetHistoryUseCase getHistoryUseCase;
  late AddToHistoryUseCase addToHistoryUseCase;
  late ClearHistoryUseCase clearHistoryUseCase;
  late WatchHistoryUseCase watchHistoryUseCase;
  late HistoryBloc historyBloc;

  setUpAll(() {
    registerFallbackValue(_FakeHttpRequestConfigEntity());
  });

  setUp(() {
    mockRepository = MockHistoryRepository();
    when(() => mockRepository.watchHistory()).thenAnswer((_) => const Stream.empty());
    getHistoryUseCase = GetHistoryUseCase(mockRepository);
    addToHistoryUseCase = AddToHistoryUseCase(mockRepository);
    clearHistoryUseCase = ClearHistoryUseCase(mockRepository);
    watchHistoryUseCase = WatchHistoryUseCase(mockRepository);
    historyBloc = HistoryBloc(
      getHistoryUseCase: getHistoryUseCase,
      addToHistoryUseCase: addToHistoryUseCase,
      clearHistoryUseCase: clearHistoryUseCase,
      watchHistoryUseCase: watchHistoryUseCase,
    );
  });

  tearDown(() {
    historyBloc.close();
  });

  const tConfig = HttpRequestConfigEntity(
    id: '1',
    method: 'GET',
    url: 'https://example.com',
  );

  test('initial state should be HistoryState with empty list', () {
    expect(historyBloc.state, const HistoryState());
  });

  test('should emit [isLoading: true, history: [...]] when LoadHistory is added', () async {
    // Arrange
    when(() => mockRepository.getHistory()).thenAnswer((_) async => [tConfig]);

    // Act
    historyBloc.add(const LoadHistory());

    // Assert
    await expectLater(
      historyBloc.stream,
      emitsInOrder([
        const HistoryState(history: [], isLoading: true),
        const HistoryState(history: [tConfig], isLoading: false),
      ]),
    );
  });

  test('should call addToHistory when AddRequestToHistory is added', () async {
    // Arrange
    when(() => mockRepository.addToHistory(any(), any())).thenAnswer((_) async => {});
    when(() => mockRepository.getHistory()).thenAnswer((_) async => [tConfig]);

    // Act
    historyBloc.add(const AddRequestToHistory(tConfig, 10));

    // Assert
    await untilCalled(() => mockRepository.addToHistory(any(), any()));
    verify(() => mockRepository.addToHistory(tConfig, 10)).called(1);
  });
}
