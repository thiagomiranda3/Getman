import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:mocktail/mocktail.dart';

class MockEnvironmentsRepository extends Mock
    implements EnvironmentsRepository {}

void main() {
  late MockEnvironmentsRepository mockRepository;
  late EnvironmentsBloc bloc;

  setUpAll(() {
    registerFallbackValue(EnvironmentEntity(id: 'fallback', name: 'fallback'));
  });

  setUp(() {
    mockRepository = MockEnvironmentsRepository();
    when(() => mockRepository.putEnvironment(any())).thenAnswer((_) async {});
    when(
      () => mockRepository.deleteEnvironment(any()),
    ).thenAnswer((_) async {});
    when(() => mockRepository.saveEnvironments(any())).thenAnswer((_) async {});
    bloc = EnvironmentsBloc(
      getEnvironmentsUseCase: GetEnvironmentsUseCase(mockRepository),
      saveEnvironmentsUseCase: SaveEnvironmentsUseCase(mockRepository),
      putEnvironmentUseCase: PutEnvironmentUseCase(mockRepository),
      deleteEnvironmentUseCase: DeleteEnvironmentUseCase(mockRepository),
    );
  });

  tearDown(() => bloc.close());

  group('AddEnvironment', () {
    test(
      'appends the given entity, preserving the caller-supplied id',
      () async {
        final env = EnvironmentEntity(id: 'env-1', name: 'Staging');

        bloc.add(AddEnvironment(env));
        await untilCalled(() => mockRepository.putEnvironment(any()));

        expect(bloc.state.environments, [env]);
        expect(bloc.state.environments.single.id, 'env-1');
      },
    );

    test('persists only the added environment (single keyed put)', () async {
      final env = EnvironmentEntity(id: 'env-1', name: 'Staging');

      bloc.add(AddEnvironment(env));
      await untilCalled(() => mockRepository.putEnvironment(any()));

      verify(() => mockRepository.putEnvironment(env)).called(1);
      verifyNever(() => mockRepository.saveEnvironments(any()));
    });
  });

  group('UpdateEnvironment', () {
    test('replaces the environment with a matching id and puts it', () async {
      final original = EnvironmentEntity(id: 'env-1', name: 'Staging');
      final updated = original.copyWith(
        name: 'Production',
        variables: {'host': 'prod'},
      );

      bloc.add(AddEnvironment(original));
      await untilCalled(() => mockRepository.putEnvironment(original));
      bloc.add(UpdateEnvironment(updated));
      await untilCalled(() => mockRepository.putEnvironment(updated));

      expect(bloc.state.environments, [updated]);
    });

    test('ignores updates for unknown ids', () async {
      bloc.add(
        UpdateEnvironment(EnvironmentEntity(id: 'ghost', name: 'Ghost')),
      );
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.environments, isEmpty);
      verifyNever(() => mockRepository.putEnvironment(any()));
    });
  });

  group('DeleteEnvironment', () {
    test('removes the environment and deletes it by id', () async {
      final env = EnvironmentEntity(id: 'env-1', name: 'Staging');
      bloc.add(AddEnvironment(env));
      await untilCalled(() => mockRepository.putEnvironment(any()));

      bloc.add(const DeleteEnvironment('env-1'));
      await untilCalled(() => mockRepository.deleteEnvironment('env-1'));

      expect(bloc.state.environments, isEmpty);
      verify(() => mockRepository.deleteEnvironment('env-1')).called(1);
    });
  });

  group('ImportEnvironments', () {
    test('appends all imported environments and batch-saves', () async {
      final a = EnvironmentEntity(id: 'a', name: 'A');
      final b = EnvironmentEntity(id: 'b', name: 'B');

      bloc.add(ImportEnvironments([a, b]));
      await untilCalled(() => mockRepository.saveEnvironments(any()));

      expect(bloc.state.environments, [a, b]);
      verify(() => mockRepository.saveEnvironments([a, b])).called(1);
    });
  });

  group('LoadEnvironments', () {
    test('emits loaded environments', () async {
      final env = EnvironmentEntity(id: 'env-1', name: 'Staging');
      when(
        () => mockRepository.getEnvironments(),
      ).thenAnswer((_) async => [env]);

      bloc.add(const LoadEnvironments());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<EnvironmentsState>(
            (s) => s.environments.length == 1 && !s.isLoading,
          ),
        ),
      );
    });

    test(
      'clears isLoading and keeps current list when the read fails',
      () async {
        when(
          () => mockRepository.getEnvironments(),
        ).thenThrow(const PersistenceFailure('corrupted box'));

        bloc.add(const LoadEnvironments());
        await expectLater(
          bloc.stream,
          emitsInOrder([
            predicate<EnvironmentsState>((s) => s.isLoading),
            predicate<EnvironmentsState>(
              (s) => !s.isLoading && s.environments.isEmpty,
            ),
          ]),
        );
      },
    );
  });
}
