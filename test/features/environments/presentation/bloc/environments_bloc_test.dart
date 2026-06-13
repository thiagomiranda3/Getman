import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:mocktail/mocktail.dart';

class MockEnvironmentsRepository extends Mock implements EnvironmentsRepository {}

void main() {
  late MockEnvironmentsRepository mockRepository;
  late EnvironmentsBloc bloc;

  setUp(() {
    mockRepository = MockEnvironmentsRepository();
    when(() => mockRepository.saveEnvironments(any())).thenAnswer((_) async {});
    bloc = EnvironmentsBloc(
      getEnvironmentsUseCase: GetEnvironmentsUseCase(mockRepository),
      saveEnvironmentsUseCase: SaveEnvironmentsUseCase(mockRepository),
    );
  });

  tearDown(() => bloc.close());

  group('AddEnvironment', () {
    test('appends the given entity, preserving the caller-supplied id', () async {
      final env = EnvironmentEntity(id: 'env-1', name: 'Staging');

      bloc.add(AddEnvironment(env));
      await untilCalled(() => mockRepository.saveEnvironments(any()));

      expect(bloc.state.environments, [env]);
      expect(bloc.state.environments.single.id, 'env-1');
    });

    test('persists the new list', () async {
      final env = EnvironmentEntity(id: 'env-1', name: 'Staging');

      bloc.add(AddEnvironment(env));
      await untilCalled(() => mockRepository.saveEnvironments(any()));

      verify(() => mockRepository.saveEnvironments([env])).called(1);
    });
  });

  group('UpdateEnvironment', () {
    test('replaces the environment with a matching id', () async {
      final original = EnvironmentEntity(id: 'env-1', name: 'Staging');
      final updated = original.copyWith(name: 'Production', variables: {'host': 'prod'});

      bloc.add(AddEnvironment(original));
      await untilCalled(() => mockRepository.saveEnvironments(any()));
      bloc.add(UpdateEnvironment(updated));
      await untilCalled(() => mockRepository.saveEnvironments([updated]));

      expect(bloc.state.environments, [updated]);
    });

    test('ignores updates for unknown ids', () async {
      bloc.add(UpdateEnvironment(EnvironmentEntity(id: 'ghost', name: 'Ghost')));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.environments, isEmpty);
      verifyNever(() => mockRepository.saveEnvironments(any()));
    });
  });

  group('DeleteEnvironment', () {
    test('removes the environment with the given id', () async {
      final env = EnvironmentEntity(id: 'env-1', name: 'Staging');
      bloc.add(AddEnvironment(env));
      await untilCalled(() => mockRepository.saveEnvironments(any()));

      bloc.add(const DeleteEnvironment('env-1'));
      await untilCalled(() => mockRepository.saveEnvironments([]));

      expect(bloc.state.environments, isEmpty);
    });
  });

  group('ImportEnvironments', () {
    test('appends all imported environments', () async {
      final a = EnvironmentEntity(id: 'a', name: 'A');
      final b = EnvironmentEntity(id: 'b', name: 'B');

      bloc.add(ImportEnvironments([a, b]));
      await untilCalled(() => mockRepository.saveEnvironments(any()));

      expect(bloc.state.environments, [a, b]);
    });
  });

  group('LoadEnvironments', () {
    test('emits loaded environments', () async {
      final env = EnvironmentEntity(id: 'env-1', name: 'Staging');
      when(() => mockRepository.getEnvironments()).thenAnswer((_) async => [env]);

      bloc.add(const LoadEnvironments());
      await expectLater(
        bloc.stream,
        emitsThrough(predicate<dynamic>((s) => s.environments.length == 1 && !s.isLoading)),
      );
    });

    test('clears isLoading and keeps current list when the read fails', () async {
      when(() => mockRepository.getEnvironments())
          .thenThrow(const PersistenceFailure('corrupted box'));

      bloc.add(const LoadEnvironments());
      await expectLater(
        bloc.stream,
        emitsInOrder([
          predicate<dynamic>((s) => s.isLoading == true),
          predicate<dynamic>((s) => s.isLoading == false && s.environments.isEmpty),
        ]),
      );
    });
  });
}
