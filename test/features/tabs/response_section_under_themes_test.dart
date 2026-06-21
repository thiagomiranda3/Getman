// Overflow guard: render the real ResponseSection (with a 200-responded tab,
// exercising the metadata row, body view, and all new motion wrappers) under
// each LOUD theme at a realistic desktop size.  Each test asserts:
//   • no RenderFlex overflow exception,
//   • no other build/paint exception,
//   • the status-code text is visible.
//
// The full bloc harness (TabsBloc + SettingsBloc + CollectionsBloc +
// HistoryBloc) is borrowed from the per-theme component tests; if those tests
// pass, this harness works.  The four themes exercised are the LOUD ones:
// kGlassThemeId, kRpgThemeId, kBrutalistThemeId, kAurisThemeId — the calm
// themes (Classic/Editorial/Dracula) use the same minimal AppMotion and are
// already covered by the per-theme component overflow guards in
// test/core/theme/themes/*.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
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
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:re_editor/re_editor.dart';

// ---------------------------------------------------------------------------
// Mocks / fakes
// ---------------------------------------------------------------------------

class _MockTabsRepository extends Mock implements TabsRepository {}

class _MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

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

SettingsBloc _settingsBloc() {
  final save = _MockSaveSettingsUseCase();
  when(() => save(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: save,
    initialSettings: const SettingsEntity(),
  );
}

/// Tab with a 200 JSON response — exercises the metadata row (status badge +
/// TIME/SIZE chips) and the body editor inside ResponseSection.
HttpRequestTabEntity _respondedTab(String tabId) => HttpRequestTabEntity(
  tabId: tabId,
  config: HttpRequestConfigEntity(id: tabId),
  response: const HttpResponseEntity(
    statusCode: 200,
    body: '{"ok":true}',
    headers: {'content-type': 'application/json'},
    durationMs: 42,
  ),
);

/// Tab that is mid-send (isSending: true) — exercises the inFlightFrame overlay
/// and any in-flight motion hooks under each loud theme.
HttpRequestTabEntity _inFlightTab(String tabId) => HttpRequestTabEntity(
  tabId: tabId,
  config: HttpRequestConfigEntity(id: tabId),
  isSending: true,
);

Future<TabsBloc> _loadedBloc(
  _MockTabsRepository repository,
  _MockSendRequestUseCase useCase,
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
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(_FakePanel());
    registerFallbackValue(const SettingsEntity());
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
  });

  for (final themeId in [
    kGlassThemeId,
    kRpgThemeId,
    kBrutalistThemeId,
    kAurisThemeId,
  ]) {
    testWidgets(
      'ResponseSection renders without overflow under $themeId '
      '(motion wrappers active, 1400×900 desktop)',
      (tester) async {
        // Realistic desktop size so Expanded / Row layout constraints match
        // production; the physicalSize-based override bypasses the default
        // 800×600 test canvas.
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final tabId = '${themeId}_resp';
        final repository = _MockTabsRepository();
        final sendUseCase = _MockSendRequestUseCase();
        when(() => repository.saveTabs(any())).thenAnswer((_) async {});
        when(() => repository.putTab(any())).thenAnswer((_) async {});
        when(() => repository.putPanel(any())).thenAnswer((_) async {});
        when(
          () => repository.savePanelMeta(any(), any()),
        ).thenAnswer((_) async {});

        final bloc = await _loadedBloc(
          repository,
          sendUseCase,
          _respondedTab(tabId),
        );
        addTearDown(bloc.close);
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);

        final theme = appThemes[themeId]!.builder(Brightness.dark);

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
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
                  BlocProvider<HistoryBloc>(
                    create: (_) => _FakeHistoryBloc(),
                  ),
                ],
                child: ResponseSection(
                  tabId: tabId,
                  responseController: controller,
                ),
              ),
            ),
          ),
        );

        // Let animations settle (motion overlays, pending shimmer, etc.).
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 700));

        // No RenderFlex overflow, no build/paint exception.
        expect(tester.takeException(), isNull);
        // Status code visible (metadata row rendered correctly).
        expect(find.textContaining('200'), findsWidgets);
      },
    );
  }

  // In-flight variants — exercises the inFlightFrame overlay that loud themes
  // render while isSending is true.  Uses a bounded pump (NOT pumpAndSettle)
  // because the frame animates continuously.
  for (final themeId in [
    kGlassThemeId,
    kRpgThemeId,
    kBrutalistThemeId,
    kAurisThemeId,
  ]) {
    testWidgets(
      'ResponseSection (in-flight) renders without overflow under $themeId '
      '(inFlightFrame overlay active, 1400×900 desktop)',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final tabId = '${themeId}_inflight';
        final repository = _MockTabsRepository();
        final sendUseCase = _MockSendRequestUseCase();
        when(() => repository.saveTabs(any())).thenAnswer((_) async {});
        when(() => repository.putTab(any())).thenAnswer((_) async {});
        when(() => repository.putPanel(any())).thenAnswer((_) async {});
        when(
          () => repository.savePanelMeta(any(), any()),
        ).thenAnswer((_) async {});

        final bloc = await _loadedBloc(
          repository,
          sendUseCase,
          _inFlightTab(tabId),
        );
        addTearDown(bloc.close);
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);

        final theme = appThemes[themeId]!.builder(Brightness.dark);

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
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
                  BlocProvider<HistoryBloc>(
                    create: (_) => _FakeHistoryBloc(),
                  ),
                ],
                child: ResponseSection(
                  tabId: tabId,
                  responseController: controller,
                ),
              ),
            ),
          ),
        );

        // Bounded pump — the inFlightFrame overlay animates continuously so
        // pumpAndSettle would hang.  Two ticks are enough to lay out the frame
        // border and verify no RenderFlex overflow.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // No RenderFlex overflow, no build/paint exception.
        expect(tester.takeException(), isNull);
      },
    );
  }
}
