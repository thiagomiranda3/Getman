// D1 TDD: verifies the AURIS theme's component slots map each AppComponents
// surface onto the matching `Auris*` widget (from package:auris), render
// without exception under the AURIS theme, and — critically — that NO `Auris*`
// widget is constructed under a non-AURIS theme (the guard test).
//
// The per-slot tests pump a single slot via `context.appComponents` under
// `aurisTheme(Brightness.dark)` and assert (a) no exception and (b) the
// expected Auris* widget type is found. The render tests pump the real
// ResponseSection (metadata row + a responded tab) and RealtimePanel under
// AURIS to catch layout overflow. The guard test pumps the same surfaces under
// the brutalist theme and asserts every Auris* type is absent.

import 'package:auris/auris_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';
import 'package:getman/core/theme/themes/auris/auris_theme.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';
import 'package:getman/features/realtime/presentation/widgets/realtime_panel.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response_section.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:re_editor/re_editor.dart';

// ---------------------------------------------------------------------------
// Mocks / fakes for the render tests.
// ---------------------------------------------------------------------------

class _MockTabsRepository extends Mock implements TabsRepository {}

class _MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockRealtimeBloc extends Mock implements RealtimeBloc {}

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

/// A tab carrying a completed 200 response so ResponseSection renders the
/// metadata row (statusBadge + TIME/SIZE metric chips).
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

/// Pumps [build]'s widget under [theme] inside a sized box; the caller asserts
/// on `find.byType(...)`.
Future<void> _pumpSlot(
  WidgetTester tester,
  ThemeData theme,
  Widget Function(BuildContext context) build,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: Builder(builder: build),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

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

  final dark = aurisTheme(Brightness.dark);

  // -------------------------------------------------------------------------
  // Per-slot mapping tests.
  // -------------------------------------------------------------------------

  testWidgets('surface (no title) → AurisContainer (not AurisPanel)', (
    tester,
  ) async {
    await _pumpSlot(
      tester,
      dark,
      (context) => context.appComponents.surface(
        context,
        child: const Text('BODY'),
      ),
    );
    expect(tester.takeException(), isNull);
    // Without a title, surface must produce an AurisContainer but NOT wrap it
    // in AurisPanel (which would indicate the title path was taken).
    expect(find.byType(AurisPanel), findsNothing);
    expect(find.byType(AurisContainer), findsWidgets);
    expect(find.text('BODY'), findsOneWidget);
  });

  testWidgets('surface (with title) → AurisPanel', (tester) async {
    await _pumpSlot(
      tester,
      dark,
      (context) => context.appComponents.surface(
        context,
        title: 'PANEL',
        child: const Text('BODY'),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(AurisPanel), findsOneWidget);
  });

  testWidgets('methodBadge → AurisBadge', (tester) async {
    await _pumpSlot(
      tester,
      dark,
      (context) => context.appComponents.methodBadge(context, method: 'GET'),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(AurisBadge), findsOneWidget);
  });

  testWidgets('statusBadge → status-tinted AurisContainer chip', (
    tester,
  ) async {
    await _pumpSlot(
      tester,
      dark,
      (context) => context.appComponents.statusBadge(context, statusCode: 200),
    );
    expect(tester.takeException(), isNull);
    // Sized to match the TIME/SIZE metric chips (AurisContainer), not the small
    // AurisBadge tag — see _aurisStatusBadge.
    expect(find.byType(AurisContainer), findsWidgets);
    expect(find.textContaining('STATUS'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
  });

  testWidgets('metric → an auris widget (Card or fallback Badge/Container)', (
    tester,
  ) async {
    await _pumpSlot(
      tester,
      dark,
      (context) => context.appComponents.metric(
        context,
        label: 'TIME',
        value: '42 ms',
      ),
    );
    expect(tester.takeException(), isNull);
    // metric maps to AurisStatCard OR (if it overflows inline) a compact
    // auris-styled fallback — in either case an Auris* widget must appear.
    final anyAuris =
        find.byType(AurisStatCard).evaluate().isNotEmpty ||
        find.byType(AurisBadge).evaluate().isNotEmpty ||
        find.byType(AurisContainer).evaluate().isNotEmpty;
    expect(anyAuris, isTrue);
  });

  testWidgets('toggle → AurisSwitch', (tester) async {
    await _pumpSlot(
      tester,
      dark,
      (context) => context.appComponents.toggle(
        context,
        value: true,
        onChanged: (_) {},
        label: 'PRETTY',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(AurisSwitch), findsOneWidget);
  });

  testWidgets('logView → AurisTerminal', (tester) async {
    await _pumpSlot(
      tester,
      dark,
      (context) => context.appComponents.logView(
        context,
        lines: const [
          AppLogLine(text: 'ping', kind: AppLogLineKind.outgoing),
          AppLogLine(text: 'pong', kind: AppLogLineKind.incoming),
        ],
        title: 'STREAM',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(AurisTerminal), findsOneWidget);
  });

  testWidgets('dataRow → AurisDataRow', (tester) async {
    await _pumpSlot(
      tester,
      dark,
      (context) => context.appComponents.dataRow(
        context,
        label: 'content-type',
        value: 'application/json',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(AurisDataRow), findsOneWidget);
  });

  testWidgets('select → AurisSelect', (tester) async {
    await _pumpSlot(
      tester,
      dark,
      (context) => context.appComponents.select(
        context,
        AppSelectSpec(
          items: const [
            AppSelectItem(label: 'ALPHA'),
            AppSelectItem(label: 'BETA'),
          ],
          selectedIndex: 1,
          onSelected: (_) {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(AurisSelect<int>), findsOneWidget);
  });

  testWidgets('statusBanner → AurisNotification', (tester) async {
    await _pumpSlot(
      tester,
      dark,
      (context) => context.appComponents.statusBanner(
        context,
        state: AppBannerState.success,
        message: 'CONNECTED',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(AurisNotification), findsOneWidget);
  });

  testWidgets('pendingIndicator → AurisProgressBar (animated, looping)', (
    tester,
  ) async {
    await _pumpSlot(
      tester,
      dark,
      (context) => context.appComponents.pendingIndicator(context),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(AurisProgressBar), findsOneWidget);
    // Let the looping controller advance a couple of frames, then confirm no
    // exception and clean disposal on unmount.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  // -------------------------------------------------------------------------
  // Real-widget render tests (overflow guards).
  // -------------------------------------------------------------------------

  testWidgets(
    'ResponseSection metadata row + body render under AURIS without overflow',
    (tester) async {
      const tabId = 'auris_resp';
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

      await tester.pumpWidget(
        MaterialApp(
          theme: dark,
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: bloc),
                BlocProvider<SettingsBloc>(create: (_) => _settingsBloc()),
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
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));

      // No overflow / build exception; the status code is visible.
      expect(tester.takeException(), isNull);
      expect(find.textContaining('200'), findsWidgets);
    },
  );

  testWidgets('RealtimePanel renders under AURIS without overflow', (
    tester,
  ) async {
    const tabId = 'auris_rt';
    final tabsBloc = _MockTabsBloc();
    final realtimeBloc = _MockRealtimeBloc();
    when(() => tabsBloc.state).thenReturn(
      const TabsState(
        tabs: [
          HttpRequestTabEntity(
            tabId: tabId,
            config: HttpRequestConfigEntity(
              id: tabId,
              kind: RequestKind.webSocket,
            ),
          ),
        ],
      ),
    );
    when(() => realtimeBloc.state).thenReturn(
      RealtimeState(
        sessions: {
          tabId: RealtimeSession(
            connected: true,
            frames: [
              RealtimeFrame.incoming('server hello'),
              RealtimeFrame.outgoing('client ping'),
            ],
          ),
        },
      ),
    );
    when(
      () => realtimeBloc.stream,
    ).thenAnswer((_) => const Stream<RealtimeState>.empty());
    when(
      () => tabsBloc.stream,
    ).thenAnswer((_) => const Stream<TabsState>.empty());

    await tester.pumpWidget(
      MaterialApp(
        theme: dark,
        home: Scaffold(
          body: BlocProvider<TabsBloc>.value(
            value: tabsBloc,
            child: BlocProvider<RealtimeBloc>.value(
              value: realtimeBloc,
              child: const RealtimePanel(tabId: tabId),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byType(AurisTerminal), findsOneWidget);
    expect(find.byType(AurisNotification), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // GUARD TEST — under a NON-AURIS theme, NO Auris* widget is ever constructed.
  // -------------------------------------------------------------------------

  testWidgets('guard: non-AURIS theme constructs NO Auris* widget', (
    tester,
  ) async {
    final brutalist = brutalistTheme(Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalist,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final c = context.appComponents;
              return Column(
                children: [
                  c.methodBadge(context, method: 'GET'),
                  c.statusBadge(context, statusCode: 200),
                  c.metric(context, label: 'TIME', value: '42 ms'),
                  c.toggle(
                    context,
                    value: true,
                    onChanged: (_) {},
                    label: 'X',
                  ),
                  c.dataRow(context, label: 'a', value: 'b'),
                  Expanded(
                    child: c.surface(context, child: const Text('S')),
                  ),
                  c.statusBanner(
                    context,
                    state: AppBannerState.info,
                    message: 'I',
                  ),
                  SizedBox(
                    height: 60,
                    child: c.logView(
                      context,
                      lines: const [
                        AppLogLine(text: 'ping', kind: AppLogLineKind.outgoing),
                      ],
                      title: 'LOG',
                    ),
                  ),
                  c.select(
                    context,
                    AppSelectSpec(
                      items: const [AppSelectItem(label: 'ONE')],
                      selectedIndex: 0,
                      onSelected: (_) {},
                    ),
                  ),
                  SizedBox(height: 60, child: c.pendingIndicator(context)),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.byType(AurisContainer), findsNothing);
    expect(find.byType(AurisPanel), findsNothing);
    expect(find.byType(AurisBadge), findsNothing);
    expect(find.byType(AurisStatCard), findsNothing);
    expect(find.byType(AurisSwitch), findsNothing);
    expect(find.byType(AurisTerminal), findsNothing);
    expect(find.byType(AurisDataRow), findsNothing);
    expect(find.byType(AurisSelect<int>), findsNothing);
    expect(find.byType(AurisNotification), findsNothing);
    expect(find.byType(AurisProgressBar), findsNothing);
  });
}
