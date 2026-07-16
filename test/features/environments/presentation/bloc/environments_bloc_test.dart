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

    test(
      'keeps the in-session list sorted case-insensitively by name so a '
      'newly added environment lands where it will sit after restart',
      () async {
        bloc.add(AddEnvironment(EnvironmentEntity(id: 'c', name: 'Charlie')));
        await untilCalled(() => mockRepository.putEnvironment(any()));
        bloc.add(AddEnvironment(EnvironmentEntity(id: 'a', name: 'alice')));
        await Future<void>.delayed(Duration.zero);
        bloc.add(AddEnvironment(EnvironmentEntity(id: 'b', name: 'Bob')));
        await Future<void>.delayed(Duration.zero);

        expect(bloc.state.environments.map((e) => e.name).toList(), [
          'alice',
          'Bob',
          'Charlie',
        ]);
      },
    );
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

    test(
      'renaming an environment re-sorts it into its new alphabetical '
      'position',
      () async {
        final a = EnvironmentEntity(id: 'a', name: 'Alpha');
        final b = EnvironmentEntity(id: 'b', name: 'Beta');
        bloc.add(AddEnvironment(a));
        await untilCalled(() => mockRepository.putEnvironment(a));
        bloc.add(AddEnvironment(b));
        await untilCalled(() => mockRepository.putEnvironment(b));

        final renamed = a.copyWith(name: 'Zeta');
        bloc.add(UpdateEnvironment(renamed));
        await untilCalled(() => mockRepository.putEnvironment(renamed));

        expect(bloc.state.environments.map((e) => e.name).toList(), [
          'Beta',
          'Zeta',
        ]);
      },
    );
  });

  group('MergeEnvironmentVariables', () {
    test(
      'two merges dispatched in the same turn both land (atomic against the '
      'live entity, unlike a full-replacement UpdateEnvironment)',
      () async {
        final env = EnvironmentEntity(
          id: 'env-1',
          name: 'Prod',
          variables: const {'base': 'https://api.dev'},
        );
        bloc
          ..add(AddEnvironment(env))
          // Same event-loop turn — e.g. two tabs' captures flushing together.
          ..add(const MergeEnvironmentVariables('env-1', {'tok1': 'a'}))
          ..add(const MergeEnvironmentVariables('env-1', {'tok2': 'b'}));
        await Future<void>.delayed(Duration.zero);

        expect(bloc.state.environments.single.variables, {
          'base': 'https://api.dev',
          'tok1': 'a',
          'tok2': 'b',
        });
      },
    );

    test('is a no-op for an unknown environment id or empty map', () async {
      bloc.add(const MergeEnvironmentVariables('ghost', {'x': '1'}));
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

    test(
      'keeps the merged list sorted case-insensitively by name',
      () async {
        final existing = EnvironmentEntity(id: 'e', name: 'Echo');
        bloc.add(AddEnvironment(existing));
        await untilCalled(() => mockRepository.putEnvironment(existing));

        final imported1 = EnvironmentEntity(id: 'a', name: 'alpha');
        final imported2 = EnvironmentEntity(id: 'd', name: 'Delta');
        bloc.add(ImportEnvironments([imported1, imported2]));
        await untilCalled(() => mockRepository.saveEnvironments(any()));

        expect(bloc.state.environments.map((e) => e.name).toList(), [
          'alpha',
          'Delta',
          'Echo',
        ]);
      },
    );
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
