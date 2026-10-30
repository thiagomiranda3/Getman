import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/environments/data/datasources/environments_local_data_source.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:getman/features/environments/data/repositories/environments_repository_impl.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';
import 'package:hive_ce/hive.dart';

class _FailingWrites extends EnvironmentsLocalDataSourceImpl {
  bool fail = true;
  @override
  Future<void> putEnvironment(EnvironmentModel environment) {
    if (fail) throw PersistenceException('write failed');
    return super.putEnvironment(environment);
  }
}

void main() {
  late Directory directory;
  late EnvironmentsRepositoryImpl repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('getman_script_patch');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(EnvironmentModelAdapter());
    }
    await Hive.openBox<EnvironmentModel>(HiveBoxes.environments);
    repository = EnvironmentsRepositoryImpl(EnvironmentsLocalDataSourceImpl());
    await repository.putEnvironment(EnvironmentEntity(id: 'env', name: 'Env'));
  });
  tearDown(() async {
    await Hive.deleteFromDisk();
    await directory.delete(recursive: true);
  });

  test('concurrent independent patches both persist', () async {
    await Future.wait([
      repository.applyVariablePatch(
        'env',
        ScriptPatch(sets: const {'token': 'abc'}),
      ),
      repository.applyVariablePatch(
        'env',
        ScriptPatch(sets: const {'session': '42'}),
      ),
    ]);
    expect((await repository.getEnvironments()).single.variables, {
      'token': 'abc',
      'session': '42',
    });
  });
  test(
    'watcher starts with live state and reports committed patches',
    () async {
      final emissions = <List<EnvironmentEntity>>[];
      final subscription = repository.watchEnvironments().listen(emissions.add);
      await Future<void>.delayed(Duration.zero);
      await repository.applyVariablePatch(
        'env',
        ScriptPatch(sets: const {'a': '1'}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emissions.first.single.variables, isEmpty);
      expect(emissions.last.single.variables, {'a': '1'});
      await subscription.cancel();
    },
  );

  test(
    'ordinary editor change preserves a patch committed after its snapshot',
    () async {
      final base = (await repository.getEnvironments()).single;
      await repository.applyVariablePatch(
        'env',
        ScriptPatch(sets: const {'token': 'new'}),
      );
      await repository.updateEnvironment(
        base.copyWith(name: 'Renamed', variables: {'host': 'localhost'}),
        previous: base,
      );
      final current = (await repository.getEnvironments()).single;
      expect(current.name, 'Renamed');
      expect(current.variables, {'token': 'new', 'host': 'localhost'});
    },
  );

  test(
    'import admits only incoming records and preserves live existing fields',
    () async {
      await Future.wait([
        repository.applyVariablePatch(
          'env',
          ScriptPatch(sets: const {'token': 'new'}),
        ),
        repository.importEnvironments([
          EnvironmentEntity(id: 'imported', name: 'Imported'),
        ]),
      ]);
      final all = await repository.getEnvironments();
      expect(all, hasLength(2));
      expect(all.firstWhere((env) => env.id == 'env').variables, {
        'token': 'new',
      });
    },
  );

  test(
    'same-key patches use admission order and unset removes the key',
    () async {
      await Future.wait([
        repository.applyVariablePatch(
          'env',
          ScriptPatch(sets: const {'key': 'first'}),
        ),
        repository.applyVariablePatch(
          'env',
          ScriptPatch(sets: const {'key': 'last'}),
        ),
      ]);
      expect(
        (await repository.getEnvironments()).single.variables['key'],
        'last',
      );
      await repository.applyVariablePatch(
        'env',
        ScriptPatch(unsets: const {'key'}),
      );
      expect((await repository.getEnvironments()).single.variables, isEmpty);
    },
  );

  test(
    'existing secret flags survive sets and are pruned only on unset',
    () async {
      await repository.putEnvironment(
        EnvironmentEntity(
          id: 'env',
          name: 'Env',
          variables: const {'secret': 'old', 'removed': 'old'},
          secretKeys: const {'secret', 'removed'},
        ),
      );
      await repository.applyVariablePatch(
        'env',
        ScriptPatch(
          sets: const {'secret': 'new', 'public': 'value'},
          unsets: const {'removed'},
        ),
      );
      final current = (await repository.getEnvironments()).single;
      expect(current.secretKeys, {'secret'});
      expect(current.variables, {'secret': 'new', 'public': 'value'});
    },
  );

  test(
    'delete admitted before a patch rejects it '
    'without recreating the environment',
    () async {
      final deletion = repository.deleteEnvironment('env');
      final patch = repository.applyVariablePatch(
        'env',
        ScriptPatch(sets: const {'a': '1'}),
      );
      await expectLater(patch, throwsA(isA<PersistenceFailure>()));
      await deletion;
      expect(await repository.getEnvironments(), isEmpty);
    },
  );

  test('delete admitted after patch wins and missing patch fails', () async {
    await Future.wait([
      repository.applyVariablePatch('env', ScriptPatch(sets: const {'a': '1'})),
      repository.deleteEnvironment('env'),
    ]);
    await expectLater(
      repository.applyVariablePatch('env', ScriptPatch()),
      throwsA(isA<PersistenceFailure>()),
    );
    expect(await repository.getEnvironments(), isEmpty);
  });

  test(
    'write failure propagates and a later admitted write can succeed',
    () async {
      final storage = _FailingWrites();
      final failingRepository = EnvironmentsRepositoryImpl(storage);
      await expectLater(
        failingRepository.applyVariablePatch(
          'env',
          ScriptPatch(sets: const {'a': '1'}),
        ),
        throwsA(isA<PersistenceFailure>()),
      );
      expect((await repository.getEnvironments()).single.variables, isEmpty);
      storage.fail = false;
      await failingRepository.applyVariablePatch(
        'env',
        ScriptPatch(sets: const {'b': '2'}),
      );
      expect((await repository.getEnvironments()).single.variables, {'b': '2'});
    },
  );

  test(
    'a stale editor update cannot resurrect an environment after deletion',
    () async {
      final previous = (await repository.getEnvironments()).single;
      await repository.deleteEnvironment('env');
      await expectLater(
        repository.updateEnvironment(
          previous.copyWith(name: 'new'),
          previous: previous,
        ),
        throwsA(isA<PersistenceFailure>()),
      );
      expect(await repository.getEnvironments(), isEmpty);
    },
  );

  test('editor toggles and deletes merge with current script values', () async {
    final previous = EnvironmentEntity(
      id: 'env',
      name: 'Env',
      variables: const {
        'secret': 'old',
        'deleted': 'value',
      },
      secretKeys: const {'deleted'},
    );
    await repository.putEnvironment(previous);
    await repository.applyVariablePatch(
      'env',
      ScriptPatch(sets: const {'secret': 'new', 'extra': 'script'}),
    );
    await repository.updateEnvironment(
      previous.copyWith(
        variables: {'secret': 'old'},
        secretKeys: {'secret'},
      ),
      previous: previous,
    );
    final current = (await repository.getEnvironments()).single;
    expect(current.variables, {'secret': 'new', 'extra': 'script'});
    expect(current.secretKeys, {'secret'});
  });

  test(
    'watcher suppresses equal snapshots and cancels before later writes',
    () async {
      final emissions = <List<EnvironmentEntity>>[];
      final subscription = repository.watchEnvironments().listen(emissions.add);
      await Future<void>.delayed(Duration.zero);
      final unchanged = (await repository.getEnvironments()).single;
      await repository.putEnvironment(unchanged);
      await Future<void>.delayed(Duration.zero);
      expect(emissions, hasLength(1));
      await subscription.cancel();
      await repository.applyVariablePatch(
        'env',
        ScriptPatch(sets: const {'after': 'cancel'}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emissions, hasLength(1));
    },
  );
}
