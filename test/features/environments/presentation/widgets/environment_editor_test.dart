// Widget tests for EnvironmentEditor: editing the name field dispatches
// UpdateEnvironment; adding a variable round-trips through KeyValueListEditor;
// marking a key secret adds it to secretKeys.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/widgets/environment_editor.dart';
import 'package:mocktail/mocktail.dart';

class MockEnvironmentsRepository extends Mock
    implements EnvironmentsRepository {}

EnvironmentsBloc _makeBloc(
  MockEnvironmentsRepository repo,
  List<EnvironmentEntity> initial,
) {
  return EnvironmentsBloc(
    getEnvironmentsUseCase: GetEnvironmentsUseCase(repo),
    saveEnvironmentsUseCase: SaveEnvironmentsUseCase(repo),
    putEnvironmentUseCase: PutEnvironmentUseCase(repo),
    deleteEnvironmentUseCase: DeleteEnvironmentUseCase(repo),
    initialEnvironments: initial,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required EnvironmentsBloc bloc,
  required EnvironmentEntity environment,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: BlocProvider.value(
          value: bloc,
          child: EnvironmentEditor(environment: environment),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late MockEnvironmentsRepository repo;

  setUpAll(() {
    registerFallbackValue(EnvironmentEntity(id: 'fallback', name: 'fallback'));
    registerFallbackValue(<EnvironmentEntity>[]);
  });

  setUp(() {
    repo = MockEnvironmentsRepository();
    when(() => repo.putEnvironment(any())).thenAnswer((_) async {});
    when(() => repo.deleteEnvironment(any())).thenAnswer((_) async {});
    when(() => repo.saveEnvironments(any())).thenAnswer((_) async {});
  });

  testWidgets('renders env name in the name field', (tester) async {
    final env = EnvironmentEntity(id: 'e1', name: 'Production');
    final bloc = _makeBloc(repo, [env]);
    addTearDown(bloc.close);

    await _pump(tester, bloc: bloc, environment: env);

    expect(find.widgetWithText(TextField, 'Production'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing the name field dispatches UpdateEnvironment', (
    tester,
  ) async {
    final env = EnvironmentEntity(id: 'e1', name: 'Production');
    final bloc = _makeBloc(repo, [env]);
    addTearDown(bloc.close);

    await _pump(tester, bloc: bloc, environment: env);

    final nameField = find.byKey(const ValueKey('env_name_field'));
    expect(nameField, findsOneWidget);

    await tester.enterText(nameField, 'Staging');
    await tester.pump(const Duration(milliseconds: 50));

    // putEnvironment should have been called (UpdateEnvironment persists).
    await untilCalled(() => repo.putEnvironment(any()));

    // The environment in the bloc's state should now have name='Staging'.
    expect(bloc.state.environments.first.name, 'Staging');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'typing into the trailing empty row adds a variable and '
    'dispatches UpdateEnvironment',
    (tester) async {
      final env = EnvironmentEntity(id: 'e1', name: 'Dev');
      final bloc = _makeBloc(repo, [env]);
      addTearDown(bloc.close);

      await _pump(tester, bloc: bloc, environment: env);

      // The editor starts with one empty trailing row (the add-row affordance):
      // key at index 0 (fieldPrefix='env_var' so key = 'env_var_key_0').
      final keyField = find.byKey(const ValueKey('env_var_key_0'));
      expect(keyField, findsOneWidget);

      await tester.enterText(keyField, 'BASE_URL');
      await tester.pump(const Duration(milliseconds: 50));

      // Typing a non-empty key into the trailing row causes a new trailing row
      // to appear. Now set the value.
      final valField = find.byKey(const ValueKey('env_var_val_0'));
      expect(valField, findsOneWidget);
      await tester.enterText(valField, 'https://api.dev');
      await tester.pump(const Duration(milliseconds: 50));

      await untilCalled(() => repo.putEnvironment(any()));

      expect(
        bloc.state.environments.first.variables,
        containsPair('BASE_URL', 'https://api.dev'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'secret lock toggle adds key to secretKeys in UpdateEnvironment',
    (tester) async {
      final env = EnvironmentEntity(
        id: 'e1',
        name: 'Dev',
        variables: const {'API_KEY': 'secret-val'},
      );
      final bloc = _makeBloc(repo, [env]);
      addTearDown(bloc.close);

      await _pump(tester, bloc: bloc, environment: env);

      // The row for 'API_KEY' is at index 0. Its lock icon has tooltip
      // 'Mark secret'. There is also a trailing empty row with 'Mark secret',
      // so use .first to hit the API_KEY row.
      final lockBtns = find.byTooltip('Mark secret');
      expect(lockBtns, findsWidgets);

      await tester.tap(lockBtns.first);
      await tester.pump(const Duration(milliseconds: 50));

      await untilCalled(() => repo.putEnvironment(any()));

      expect(bloc.state.environments.first.secretKeys, contains('API_KEY'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'removing a variable prunes its key from secretKeys in UpdateEnvironment',
    (tester) async {
      // Start with 'TOKEN' pre-flagged as secret.
      final env = EnvironmentEntity(
        id: 'e1',
        name: 'Dev',
        variables: const {'TOKEN': 'abc'},
        secretKeys: const {'TOKEN'},
      );
      final bloc = _makeBloc(repo, [env]);
      addTearDown(bloc.close);

      await _pump(tester, bloc: bloc, environment: env);

      // Delete the 'TOKEN' row.
      final deleteBtn = find.byIcon(Icons.delete_outline).first;
      expect(deleteBtn, findsOneWidget);

      await tester.tap(deleteBtn);
      await tester.pump(const Duration(milliseconds: 50));

      await untilCalled(() => repo.putEnvironment(any()));

      // After deletion secretKeys must NOT contain 'TOKEN' anymore.
      expect(
        bloc.state.environments.first.secretKeys,
        isNot(contains('TOKEN')),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
