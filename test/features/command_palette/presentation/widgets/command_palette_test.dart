// Widget tests for CommandPalette: typing filters, and selecting a row
// dispatches the right event. The four blocs are mocked (the palette holds
// them directly and only reads .state / calls .add).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/command_palette/presentation/widgets/command_palette.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsBloc extends Mock implements TabsBloc {}

class MockCollectionsBloc extends Mock implements CollectionsBloc {}

class MockEnvironmentsBloc extends Mock implements EnvironmentsBloc {}

class MockSettingsBloc extends Mock implements SettingsBloc {}

void main() {
  late MockTabsBloc tabs;
  late MockCollectionsBloc collections;
  late MockEnvironmentsBloc environments;
  late MockSettingsBloc settings;

  setUpAll(() {
    registerFallbackValue(const AddTab());
    registerFallbackValue(const UpdateThemeId('x'));
  });

  setUp(() {
    tabs = MockTabsBloc();
    collections = MockCollectionsBloc();
    environments = MockEnvironmentsBloc();
    settings = MockSettingsBloc();

    when(() => collections.state).thenReturn(
      CollectionsState(
        collections: const [
          CollectionNodeEntity(
            id: 'f1',
            name: 'Auth',
            children: [
              CollectionNodeEntity(
                id: 'r1',
                name: 'Login',
                isFolder: false,
                config: HttpRequestConfigEntity(
                  id: 'c1',
                  method: 'POST',
                  url: 'https://api.dev/login',
                ),
              ),
            ],
          ),
        ],
      ),
    );
    when(() => environments.state).thenReturn(
      EnvironmentsState(
        environments: [EnvironmentEntity(id: 'e1', name: 'Production')],
      ),
    );
    when(() => tabs.add(any())).thenReturn(null);
    when(() => settings.add(any())).thenReturn(null);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: CommandPalette(
            tabsBloc: tabs,
            collectionsBloc: collections,
            environmentsBloc: environments,
            settingsBloc: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists requests, environments and themes', (tester) async {
    await pump(tester);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('No Environment'), findsOneWidget);
  });

  testWidgets('typing filters the list', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'login');
    // Search is debounced (~220ms) — advance past the window so the query
    // lands.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Production'), findsNothing);
  });

  testWidgets('Enter submits the top match without waiting for the debounce', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'login');
    // No debounce wait — onSubmitted recomputes synchronously.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    verify(() => tabs.add(any(that: isA<AddTab>()))).called(1);
  });

  testWidgets('arrow keys move the highlight; Enter runs the highlighted row', (
    tester,
  ) async {
    await pump(tester);
    // With an empty query the order is: Login (request), No Environment,
    // Production, themes…
    // ArrowDown once highlights "No Environment", so Enter must switch the
    // environment, NOT open the top request as a tab.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    verify(
      () => settings.add(any(that: isA<UpdateActiveEnvironmentId>())),
    ).called(1);
    verifyNever(() => tabs.add(any()));
  });

  testWidgets('tapping a request opens it as a tab', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    verify(() => tabs.add(any(that: isA<AddTab>()))).called(1);
  });

  testWidgets('tapping an environment switches it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Production'));
    await tester.pumpAndSettle();
    verify(
      () => settings.add(any(that: isA<UpdateActiveEnvironmentId>())),
    ).called(1);
  });
}
