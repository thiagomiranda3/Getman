// Widget tests for UnresolvedVarsChip: hidden when every {{var}} resolves,
// count face when some do not, popover listing (capped at 10 + "+N more")
// with the Open environment editor… action, and env-resolution through the
// active environment.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/unresolved_vars_chip.dart';
import 'package:mocktail/mocktail.dart';

// FIX I3: UnresolvedVarsChip.debounceDuration must match the debounce window
// used for the keystroke-burst recompute (see the widget's own class doc).
Duration get _debounce => UnresolvedVarsChip.debounceDuration;

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockEnvironmentsBloc extends Mock implements EnvironmentsBloc {}

class MockSettingsBloc extends Mock implements SettingsBloc {}

class MockCollectionsBloc extends Mock implements CollectionsBloc {}

const ValueKey<String> _chipKey = ValueKey('unresolved_vars_chip');

Future<TabsBloc> _loadedBloc(
  MockTabsRepository repository,
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
  final bloc = TabsBloc(
    repository: repository,
    sendRequestUseCase: MockSendRequestUseCase(),
  )..add(const LoadTabs());
  await bloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
  return bloc;
}

Future<void> _pump(
  WidgetTester tester,
  TabsBloc bloc,
  String tabId, {
  List<EnvironmentEntity> environments = const [],
  String? activeEnvironmentId,
}) async {
  final envBloc = MockEnvironmentsBloc();
  when(
    () => envBloc.state,
  ).thenReturn(EnvironmentsState(environments: environments));
  when(() => envBloc.stream).thenAnswer((_) => const Stream.empty());

  final settingsBloc = MockSettingsBloc();
  when(() => settingsBloc.state).thenReturn(
    SettingsState(
      settings: SettingsEntity(activeEnvironmentId: activeEnvironmentId),
    ),
  );
  when(() => settingsBloc.stream).thenAnswer((_) => const Stream.empty());

  final collectionsBloc = MockCollectionsBloc();
  when(() => collectionsBloc.state).thenReturn(CollectionsState());
  when(() => collectionsBloc.stream).thenAnswer((_) => const Stream.empty());

  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<TabsBloc>.value(value: bloc),
            BlocProvider<EnvironmentsBloc>.value(value: envBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<CollectionsBloc>.value(value: collectionsBloc),
          ],
          child: Align(child: UnresolvedVarsChip(tabId: tabId)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late MockTabsRepository repository;

  setUp(() {
    repository = MockTabsRepository();
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

  setUpAll(() {
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
    registerFallbackValue(
      const PanelEntity(id: 'pf', name: 'pf', tabs: [], activeTabId: ''),
    );
  });

  testWidgets('hidden when every {{var}} resolves in the active env', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'v1',
      config: HttpRequestConfigEntity(id: 'v1', url: '{{base}}/users'),
    );
    final bloc = await _loadedBloc(repository, tab);
    addTearDown(bloc.close);
    final env = EnvironmentEntity(
      id: 'e1',
      name: 'Dev',
      variables: const {'base': 'https://api.dev'},
    );

    await _pump(
      tester,
      bloc,
      'v1',
      environments: [env],
      activeEnvironmentId: 'e1',
    );

    expect(find.byKey(_chipKey), findsNothing);
  });

  testWidgets('shows the unresolved count when vars resolve to nothing', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'v2',
      config: HttpRequestConfigEntity(id: 'v2', url: '{{base}}/{{token}}'),
    );
    final bloc = await _loadedBloc(repository, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 'v2');

    expect(find.byKey(_chipKey), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_chipKey), matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('click lists the names plus Open environment editor…', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 'v3',
      config: HttpRequestConfigEntity(id: 'v3', url: '{{base}}/{{token}}'),
    );
    final bloc = await _loadedBloc(repository, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 'v3');
    await tester.tap(find.byKey(_chipKey));
    await tester.pumpAndSettle();

    expect(find.text('{{base}}'), findsOneWidget);
    expect(find.text('{{token}}'), findsOneWidget);
    expect(find.text('Open environment editor…'), findsOneWidget);
  });

  testWidgets('caps the listing at 10 names with a +N more row', (
    tester,
  ) async {
    final url = [
      for (var i = 0; i < 12; i++) '{{var$i}}',
    ].join('/');
    final tab = HttpRequestTabEntity(
      tabId: 'v4',
      config: HttpRequestConfigEntity(id: 'v4', url: url),
    );
    final bloc = await _loadedBloc(repository, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 'v4');
    await tester.tap(find.byKey(_chipKey));
    await tester.pumpAndSettle();

    expect(find.text('{{var0}}'), findsOneWidget);
    expect(find.text('{{var9}}'), findsOneWidget);
    expect(find.text('{{var10}}'), findsNothing);
    expect(find.text('+2 more'), findsOneWidget);
  });

  testWidgets(
    'shows the count immediately on first mount (no debounce lag for an '
    'already-unresolved tab)',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 'v6',
        config: HttpRequestConfigEntity(id: 'v6', url: '{{base}}/users'),
      );
      final bloc = await _loadedBloc(repository, tab);
      addTearDown(bloc.close);

      await _pump(tester, bloc, 'v6');

      expect(
        find.byKey(_chipKey),
        findsOneWidget,
        reason: 'the very first render must not wait out the debounce',
      );
    },
  );

  testWidgets(
    'FIX I3: recompute off a keystroke-style config change is debounced — '
    'the chip lags briefly, then catches up; never blocks/crashes',
    (tester) async {
      const tab = HttpRequestTabEntity(
        tabId: 'v7',
        config: HttpRequestConfigEntity(
          id: 'v7',
          url: 'https://ok.example.com',
        ),
      );
      final bloc = await _loadedBloc(repository, tab);
      addTearDown(bloc.close);

      await _pump(tester, bloc, 'v7');
      expect(find.byKey(_chipKey), findsNothing);

      // Simulate a keystroke editing the URL to add an unresolved var.
      final updated = tab.copyWith(
        config: tab.config.copyWith(
          url: 'https://ok.example.com/{{token}}',
        ),
      );
      bloc.add(UpdateTab(updated));
      await tester.pump(); // let TabsBloc emit; no debounce time has elapsed

      expect(
        find.byKey(_chipKey),
        findsNothing,
        reason:
            'the collector scan must not run synchronously on the '
            'keystroke frame — this is the E3 hot-path regression',
      );

      // Advance past the debounce window in small steps, not one big jump:
      // AutomatedTestWidgetsFlutterBinding.pump(duration) elapses fake time
      // BEFORE building any pending frame that arms the timer, so a single
      // big pump can "use up" the whole window before the debounced
      // callback ever runs. Small steps let the already-armed timer fire
      // mid-elapse on a later step and get built within that same step.
      // (pumpAndSettle doesn't help here either — it stops as soon as one
      // step schedules no further frame, which is exactly what happens
      // while a debounce Timer is still ticking in the background.)
      const step = Duration(milliseconds: 50);
      var elapsed = Duration.zero;
      while (elapsed < _debounce + const Duration(milliseconds: 100)) {
        await tester.pump(step);
        elapsed += step;
      }

      expect(
        find.byKey(_chipKey),
        findsOneWidget,
        reason: 'the chip must catch up once typing quiets down',
      );

      // Flush TabsBloc's own autosave debounce Timer (_scheduleSave, ~10s)
      // so it doesn't trip the "no pending timers" test invariant — same
      // flush other tests in this suite perform after an UpdateTab.
      await tester.pump(const Duration(seconds: 11));
    },
  );
}
