import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';
import 'package:mocktail/mocktail.dart';

class _Repository extends Mock implements EnvironmentsRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(ScriptPatch());
    registerFallbackValue(EnvironmentEntity(name: 'fallback'));
  });
  test(
    'legacy variable merges persist a patch rather than a stale entity',
    () async {
      final repository = _Repository();
      when(() => repository.putEnvironment(any())).thenAnswer((_) async {});
      when(
        () => repository.applyVariablePatch(any(), any()),
      ).thenAnswer((_) async {});
      final bloc = EnvironmentsBloc(
        getEnvironmentsUseCase: GetEnvironmentsUseCase(repository),
        saveEnvironmentsUseCase: SaveEnvironmentsUseCase(repository),
        putEnvironmentUseCase: PutEnvironmentUseCase(repository),
        deleteEnvironmentUseCase: DeleteEnvironmentUseCase(repository),
        initialEnvironments: [EnvironmentEntity(id: 'env', name: 'Env')],
      )..add(const MergeEnvironmentVariables('env', {'new': 'value'}));
      await Future<void>.delayed(Duration.zero);
      verify(
        () => repository.applyVariablePatch(
          'env',
          ScriptPatch(sets: const {'new': 'value'}),
        ),
      ).called(1);
      verifyNever(() => repository.putEnvironment(any()));
      await bloc.close();
    },
  );

  test(
    'external commits update the bloc and close cancels its watcher',
    () async {
      var cancelled = false;
      final changes = StreamController<List<EnvironmentEntity>>(
        onCancel: () => cancelled = true,
      );
      final repository = _Repository();
      when(repository.watchEnvironments).thenAnswer((_) => changes.stream);
      final bloc = EnvironmentsBloc(
        getEnvironmentsUseCase: GetEnvironmentsUseCase(repository),
        saveEnvironmentsUseCase: SaveEnvironmentsUseCase(repository),
        putEnvironmentUseCase: PutEnvironmentUseCase(repository),
        deleteEnvironmentUseCase: DeleteEnvironmentUseCase(repository),
        watchEnvironmentsUseCase: WatchEnvironmentsUseCase(repository),
      );
      final updated = EnvironmentEntity(
        id: 'env',
        name: 'Env',
        variables: const {'token': 'new'},
      );
      final nextState = bloc.stream.first;
      changes.add([updated]);
      expect((await nextState).environments, [updated]);
      await bloc.close();
      expect(cancelled, isTrue);
      await changes.close();
    },
  );
}
