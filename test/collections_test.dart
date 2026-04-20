import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

void main() {
  late MockCollectionsRepository mockRepository;
  late GetCollectionsUseCase getCollectionsUseCase;
  late SaveCollectionsUseCase saveCollectionsUseCase;
  late CollectionsBloc collectionsBloc;

  setUp(() {
    mockRepository = MockCollectionsRepository();
    getCollectionsUseCase = GetCollectionsUseCase(mockRepository);
    saveCollectionsUseCase = SaveCollectionsUseCase(mockRepository);
    collectionsBloc = CollectionsBloc(
      getCollectionsUseCase: getCollectionsUseCase,
      saveCollectionsUseCase: saveCollectionsUseCase,
    );
  });

  tearDown(() {
    collectionsBloc.close();
  });

  const tNode = CollectionNodeEntity(
    id: '1',
    name: 'Folder',
    isFolder: true,
  );

  test('initial state should be CollectionsState with empty list', () {
    expect(collectionsBloc.state, const CollectionsState());
  });

  test('should emit [isLoading: true, collections: [...]] when LoadCollections is added', () async {
    // Arrange
    when(() => mockRepository.getCollections()).thenAnswer((_) async => [tNode]);

    // Act
    collectionsBloc.add(const LoadCollections());

    // Assert
    await expectLater(
      collectionsBloc.stream,
      emitsInOrder([
        const CollectionsState(collections: [], isLoading: true),
        const CollectionsState(collections: [tNode], isLoading: false),
      ]),
    );
  });

  test('should call saveCollections when AddFolder is added', () async {
    // Arrange
    when(() => mockRepository.getCollections()).thenAnswer((_) async => []);
    when(() => mockRepository.saveCollections(any())).thenAnswer((_) async => {});

    // Act
    collectionsBloc.add(const AddFolder('New Folder'));

    // Assert
    await untilCalled(() => mockRepository.saveCollections(any()));
    verify(() => mockRepository.saveCollections(any())).called(1);
  });
}
