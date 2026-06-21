import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_components.dart';
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

// ---------------------------------------------------------------------------
// Helper: pumps a widget under the given theme inside a bounded SizedBox.
// ---------------------------------------------------------------------------

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  Widget Function(BuildContext) build, {
  double width = 400,
  double height = 200,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Builder(builder: build),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late ThemeData dark;
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
    dark = brutalistTheme(Brightness.dark);
  });

  // -------------------------------------------------------------------------
  // Smoke tests — one per slot.
  // -------------------------------------------------------------------------

  testWidgets('methodBadge → BrutalStamp', (tester) async {
    await _pump(
      tester,
      dark,
      (c) => c.appComponents.methodBadge(c, method: 'GET'),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalStamp), findsOneWidget);
  });

  testWidgets('statusBadge → BrutalStamp', (tester) async {
    await _pump(
      tester,
      dark,
      (c) => c.appComponents.statusBadge(c, statusCode: 200),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalStamp), findsWidgets);
  });

  testWidgets('surface (no title) fills + no overflow', (tester) async {
    await _pump(
      tester,
      dark,
      (c) => c.appComponents.surface(c, child: const Text('BODY')),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalSlab), findsOneWidget);
    expect(find.text('BODY'), findsOneWidget);
  });

  testWidgets('surface (title) shows stuck label', (tester) async {
    await _pump(
      tester,
      dark,
      (c) => c.appComponents.surface(c, title: 'PANEL', child: const Text('B')),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('PANEL'), findsOneWidget);
  });

  testWidgets('metric is inline-safe in a tight Wrap', (tester) async {
    await _pump(
      tester,
      dark,
      width: 300,
      height: 60,
      (c) => Wrap(
        children: [
          c.appComponents.statusBadge(c, statusCode: 200),
          c.appComponents.metric(c, label: 'TIME', value: '42', unit: 'ms'),
          c.appComponents.metric(c, label: 'SIZE', value: '1.2', unit: 'KB'),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalTickerChip), findsNWidgets(2));
  });

  testWidgets('toggle → BrutalSwitch (tap flips)', (tester) async {
    var v = false;
    await _pump(
      tester,
      dark,
      (c) => StatefulBuilder(
        builder: (c, setState) => c.appComponents.toggle(
          c,
          value: v,
          label: 'X',
          onChanged: (n) => setState(() => v = n),
        ),
      ),
    );
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
    expect(v, isTrue);
  });

  testWidgets('logView sizes to bounded height (no overflow)', (tester) async {
    await _pump(
      tester,
      dark,
      height: 80,
      (c) => c.appComponents.logView(
        c,
        title: 'LOG',
        lines: const [
          AppLogLine(text: 'a', kind: AppLogLineKind.outgoing),
          AppLogLine(text: 'b', kind: AppLogLineKind.incoming),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalFanfoldLog), findsOneWidget);
  });

  testWidgets('dataRow → BrutalPrintedRow', (tester) async {
    await _pump(
      tester,
      dark,
      (c) => c.appComponents.dataRow(c, label: 'a', value: 'b'),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalPrintedRow), findsOneWidget);
  });

  testWidgets('statusBanner → BrutalStampBanner', (tester) async {
    await _pump(
      tester,
      dark,
      (c) => c.appComponents.statusBanner(
        c,
        state: AppBannerState.success,
        message: 'OK',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BrutalStampBanner), findsOneWidget);
  });

  testWidgets('pendingIndicator animates then disposes cleanly', (
    tester,
  ) async {
    await _pump(tester, dark, (c) => c.appComponents.pendingIndicator(c));
    expect(find.byType(BrutalPressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduceEffects: pending + switch render static (no ticker)', (
    tester,
  ) async {
    final reduced = brutalistTheme(Brightness.dark, reduceEffects: true);
    await _pump(
      tester,
      reduced,
      (c) => Column(
        children: [
          SizedBox(height: 120, child: c.appComponents.pendingIndicator(c)),
          c.appComponents.toggle(c, value: true, onChanged: (_) {}, label: 'X'),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    // Static pending indicator schedules no frames: pumpAndSettle
    // returns at once.
    await tester.pumpAndSettle();
    expect(find.byType(BrutalPressIndicator), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Real-widget render tests (overflow guards).
  // -------------------------------------------------------------------------

  testWidgets(
    'ResponseSection metadata row + body render under brutalist '
    'without overflow',
    (tester) async {
      const tabId = 'brutal_resp';
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

  testWidgets('RealtimePanel renders under brutalist without overflow', (
    tester,
  ) async {
    const tabId = 'brutal_rt';
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
    expect(find.byType(BrutalFanfoldLog), findsOneWidget);
    expect(find.byType(BrutalStampBanner), findsOneWidget);
  });
}
