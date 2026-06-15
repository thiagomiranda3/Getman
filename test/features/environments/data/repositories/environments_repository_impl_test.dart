import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/environments/data/datasources/environments_local_data_source.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:getman/features/environments/data/repositories/environments_repository_impl.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';

class _FakeEnvironmentsDataSource implements EnvironmentsLocalDataSource {
  _FakeEnvironmentsDataSource([this.stored = const []]);
  List<EnvironmentModel> stored;
  EnvironmentModel? putModel;
  String? deletedId;
  List<EnvironmentModel>? savedList;
  bool throwOnGet = false;

  @override
  Future<List<EnvironmentModel>> getEnvironments() async {
    if (throwOnGet) throw PersistenceException('boom');
    return stored;
  }

  @override
  Future<void> putEnvironment(EnvironmentModel environment) async =>
      putModel = environment;

  @override
  Future<void> deleteEnvironment(String id) async => deletedId = id;

  @override
  Future<void> saveEnvironments(List<EnvironmentModel> environments) async =>
      savedList = environments;
}

void main() {
  test('getEnvironments maps each model to an entity', () async {
    final ds = _FakeEnvironmentsDataSource([
      EnvironmentModel.fromEntity(
        EnvironmentEntity(id: 'e1', name: 'Prod', variables: const {'k': 'v'}),
      ),
    ]);
    final repo = EnvironmentsRepositoryImpl(ds);

    final result = await repo.getEnvironments();
    expect(result, hasLength(1));
    expect(result.single.name, 'Prod');
    expect(result.single.variables['k'], 'v');
  });

  test('putEnvironment forwards a single converted model', () async {
    final ds = _FakeEnvironmentsDataSource();
    final repo = EnvironmentsRepositoryImpl(ds);

    await repo.putEnvironment(EnvironmentEntity(id: 'e2', name: 'Staging'));

    expect(ds.putModel?.id, 'e2');
    expect(ds.putModel?.name, 'Staging');
  });

  test('deleteEnvironment forwards the id', () async {
    final ds = _FakeEnvironmentsDataSource();
    final repo = EnvironmentsRepositoryImpl(ds);

    await repo.deleteEnvironment('e3');

    expect(ds.deletedId, 'e3');
  });

  test('saveEnvironments converts the whole list', () async {
    final ds = _FakeEnvironmentsDataSource();
    final repo = EnvironmentsRepositoryImpl(ds);

    await repo.saveEnvironments([
      EnvironmentEntity(id: 'a', name: 'A'),
      EnvironmentEntity(id: 'b', name: 'B'),
    ]);

    expect(ds.savedList?.map((m) => m.id), ['a', 'b']);
  });

  test('translates a PersistenceException into a PersistenceFailure', () async {
    final ds = _FakeEnvironmentsDataSource()..throwOnGet = true;
    final repo = EnvironmentsRepositoryImpl(ds);

    expect(repo.getEnvironments(), throwsA(isA<PersistenceFailure>()));
  });
}
