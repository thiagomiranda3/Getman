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
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsBloc extends Mock implements TabsBloc {}

class MockCollectionsBloc extends Mock implements CollectionsBloc {}

class MockEnvironmentsBloc extends Mock implements EnvironmentsBloc {}

class MockSettingsBloc extends Mock implements SettingsBloc {}

class MockHistoryBloc extends Mock implements HistoryBloc {}

void main() {
  late MockTabsBloc tabs;
  late MockCollectionsBloc collections;
  late MockEnvironmentsBloc environments;
  late MockSettingsBloc settings;
  late MockHistoryBloc history;

  setUpAll(() {
    registerFallbackValue(const AddTab());
    registerFallbackValue(const UpdateThemeId('x'));
  });

  setUp(() {
    tabs = MockTabsBloc();
    collections = MockCollectionsBloc();
    environments = MockEnvironmentsBloc();
    settings = MockSettingsBloc();
    history = MockHistoryBloc();

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
    when(() => history.state).thenReturn(const HistoryState());
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
            historyBloc: history,
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

  testWidgets('request matches by URL fragment, not just name', (tester) async {
    // Seed a leaf whose NAME ('Widgets List') does not contain the URL token
    // 'orders' — only the URL does. Proves the widened match string.
    when(() => collections.state).thenReturn(
      CollectionsState(
        collections: const [
          CollectionNodeEntity(
            id: 'r2',
            name: 'Widgets List',
            isFolder: false,
            config: HttpRequestConfigEntity(
              id: 'c2',
              url: 'https://api.dev/orders',
            ),
          ),
        ],
      ),
    );
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'orders');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    // The displayed label is still the node name — the URL only widened the
    // hidden match text.
    expect(find.text('Widgets List'), findsOneWidget);
  });

  testWidgets('request matches by HTTP method', (tester) async {
    when(() => collections.state).thenReturn(
      CollectionsState(
        collections: const [
          CollectionNodeEntity(
            id: 'r3',
            name: 'Remove User',
            isFolder: false,
            config: HttpRequestConfigEntity(
              id: 'c3',
              method: 'DELETE',
              url: 'https://api.dev/users/1',
            ),
          ),
        ],
      ),
    );
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('Remove User'), findsOneWidget);
  });

  testWidgets(
    'history entry appears with a History subtitle and opens unlinked',
    (tester) async {
      when(() => history.state).thenReturn(
        const HistoryState(
          history: [
            HttpRequestConfigEntity(
              id: 'h1',
              method: 'POST',
              url: 'https://api.example.com/orders',
            ),
          ],
        ),
      );
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'orders');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // The URL is the row label; 'History' is the source-tag subtitle.
      expect(find.text('https://api.example.com/orders'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);

      await tester.tap(find.text('https://api.example.com/orders'));
      await tester.pumpAndSettle();

      final captured =
          verify(
                () => tabs.add(captureAny(that: isA<AddTab>())),
              ).captured.single
              as AddTab;
      expect(captured.config?.url, 'https://api.example.com/orders');
      expect(captured.config?.method, 'POST');
      // Unlinked tab — Locked Decision 4.
      expect(captured.collectionNodeId, isNull);
      expect(captured.collectionName, isNull);
    },
  );

  testWidgets('empty history adds no History row', (tester) async {
    // history.state already stubbed empty in setUp.
    await pump(tester);
    expect(find.text('History'), findsNothing);
    // Existing sources still render.
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
  });

  testWidgets(
    'ArrowDown past the visible fold scrolls the highlighted row into view',
    (tester) async {
      // Seed enough history rows that the (capped maxHeight: 360) results
      // list has to scroll well before the 13th row (index 12) — without
      // ScrollController wiring, this row would never even get built by the
      // lazy ListView.builder, since it sits outside both the viewport and
      // the default cache extent.
      when(() => history.state).thenReturn(
        HistoryState(
          history: [
            for (var i = 0; i < 20; i++)
              HttpRequestConfigEntity(
                id: 'h$i',
                url: 'https://api.example.com/item/$i',
              ),
          ],
        ),
      );
      await pump(tester);

      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      // Let the scroll-into-view animation finish.
      await tester.pumpAndSettle();

      final row12 = find.byKey(const ValueKey('palette_result_12'));
      // Built at all (the lazy ListView had to realize it) AND actually
      // reachable by a tap (not clipped outside the scrollable viewport).
      expect(row12, findsOneWidget);
      expect(row12.hitTestable(), findsOneWidget);
    },
  );
}
