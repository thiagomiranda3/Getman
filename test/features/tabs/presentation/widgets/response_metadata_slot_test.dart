// Widget tests for the statusBadge / metric component slots as routed from
// ResponseSection. Verifies that the default slot implementations produce the
// correct label text ("STATUS: ", "TIME: ", "SIZE: ") and status-code value,
// with no exceptions, using a real brutalist theme (which uses
// defaultAppComponents).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/response_section.dart';
import 'package:mocktail/mocktail.dart';
import 'package:re_editor/re_editor.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

class _FakeCollectionsBloc extends Bloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {
  _FakeCollectionsBloc() : super(CollectionsState());
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc() : super(const HistoryState());
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SettingsBloc _settingsBloc() {
  final saveUseCase = MockSaveSettingsUseCase();
  when(() => saveUseCase(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: saveUseCase,
    initialSettings: const SettingsEntity(),
  );
}

/// Creates and loads a [TabsBloc] whose active panel contains [tab].
Future<TabsBloc> _loadedBloc(
  MockTabsRepository repository,
  MockSendRequestUseCase useCase,
  HttpRequestTabEntity tab,
) async {
  when(() => repository.getPanels()).thenAnswer(
    (_) async => [
      PanelEntity(
        id: 'p1',
        name: 'Panel 1',
        tabs: [tab],
        activeTabId: tab.tabId,
      ),
    ],
  );
  when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');
  final bloc = TabsBloc(repository: repository, sendRequestUseCase: useCase)
    ..add(const LoadTabs());
  await bloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
  return bloc;
}

// ---------------------------------------------------------------------------
// Slot-level tests: render the default slot closures directly
// ---------------------------------------------------------------------------

/// Wraps a slot widget in a full theme + scaffold without blocs.
Future<void> _pumpSlot(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(body: Center(child: widget)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late MockTabsRepository repository;
  late MockSendRequestUseCase sendRequestUseCase;

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(_FakePanel());
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
    registerFallbackValue(const SettingsEntity());
  });

  setUp(() {
    repository = MockTabsRepository();
    sendRequestUseCase = MockSendRequestUseCase();
    when(() => repository.saveTabs(any())).thenAnswer((_) async {});
    when(() => repository.putTab(any())).thenAnswer((_) async {});
    when(() => repository.deleteTabs(any())).thenAnswer((_) async {});
    when(() => repository.saveTabOrder(any())).thenAnswer((_) async {});
    when(() => repository.putPanel(any())).thenAnswer((_) async {});
    when(() => repository.deletePanels(any())).thenAnswer((_) async {});
    when(
      () => repository.savePanelMeta(any(), any()),
    ).thenAnswer((_) async {});
  });

  // -------------------------------------------------------------------------
  // statusBadge slot — direct render
  // -------------------------------------------------------------------------

  group('statusBadge default slot', () {
    testWidgets(
      'renders STATUS: label and the status code, no exception',
      (tester) async {
        await _pumpSlot(
          tester,
          Builder(
            builder: (context) =>
                Theme.of(context).extension<AppComponents>()!.statusBadge(
                  context,
                  statusCode: 200,
                ),
          ),
        );

        expect(find.text('STATUS: '), findsOneWidget);
        expect(find.text('200'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders a 404 status code correctly',
      (tester) async {
        await _pumpSlot(
          tester,
          Builder(
            builder: (context) =>
                Theme.of(context).extension<AppComponents>()!.statusBadge(
                  context,
                  statusCode: 404,
                ),
          ),
        );

        expect(find.text('STATUS: '), findsOneWidget);
        expect(find.text('404'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // metric slot — direct render
  // -------------------------------------------------------------------------

  group('metric default slot', () {
    testWidgets(
      'renders TIME label and value, no exception',
      (tester) async {
        await _pumpSlot(
          tester,
          Builder(
            builder: (context) =>
                Theme.of(context).extension<AppComponents>()!.metric(
                  context,
                  label: 'TIME',
                  value: '42 ms',
                ),
          ),
        );

        expect(find.text('TIME: '), findsOneWidget);
        expect(find.text('42 ms'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders SIZE label and value, no exception',
      (tester) async {
        await _pumpSlot(
          tester,
          Builder(
            builder: (context) =>
                Theme.of(context).extension<AppComponents>()!.metric(
                  context,
                  label: 'SIZE',
                  value: '1.2 KB',
                ),
          ),
        );

        expect(find.text('SIZE: '), findsOneWidget);
        expect(find.text('1.2 KB'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'appends unit to value when unit is provided',
      (tester) async {
        await _pumpSlot(
          tester,
          Builder(
            builder: (context) =>
                Theme.of(context).extension<AppComponents>()!.metric(
                  context,
                  label: 'TIME',
                  value: '100',
                  unit: 'ms',
                ),
          ),
        );

        expect(find.text('TIME: '), findsOneWidget);
        expect(find.text('100 ms'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // ResponseSection integration — slot output appears in the metadata row
  // -------------------------------------------------------------------------

  group('ResponseSection metadata row via slots', () {
    testWidgets(
      'STATUS, TIME, SIZE labels all appear in the metadata row',
      (tester) async {
        const tabId = 'slotTab1';
        const tab = HttpRequestTabEntity(
          tabId: tabId,
          config: HttpRequestConfigEntity(id: tabId),
          response: HttpResponseEntity(
            statusCode: 201,
            body: '{"ok":true}',
            headers: {},
            durationMs: 55,
          ),
        );
        final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
        addTearDown(bloc.close);
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: brutalistTheme(Brightness.light),
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: bloc),
                  BlocProvider<SettingsBloc>(
                    create: (_) => _settingsBloc(),
                  ),
                  BlocProvider<CollectionsBloc>(
                    create: (_) => _FakeCollectionsBloc(),
                  ),
                  BlocProvider<HistoryBloc>(create: (_) => _FakeHistoryBloc()),
                ],
                child: ResponseSection(
                  tabId: tabId,
                  responseController: controller,
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpAndSettle();

        // The three slot labels must all be present.
        expect(find.text('STATUS: '), findsOneWidget);
        expect(find.text('TIME: '), findsOneWidget);
        expect(find.text('SIZE: '), findsOneWidget);
        // Status code value.
        expect(find.text('201'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
