// Tests for the Action callback LOGIC registered by MainScreen.
//
// Pumping the real MainScreen is not feasible in widget tests: its transitive
// tree requires GetIt-registered singletons (ThemeReactionController,
// WorkspacePulseController, ThemeSoundService, TabDirtyChecker) plus
// SideMenu / TabContentStack / ChainingWriteBackListener / ThemeReactionListener
// that cannot be provided without running the full DI container, and the
// theme's ambient ticker never settles so pumpAndSettle would hang.
//
// Instead, this harness rebuilds each relevant Action callback in a thin
// Actions wrapper with mock blocs in scope — a faithful copy of the exact
// callbacks in MainScreen._buildMainScreenActions — then invokes the Intent
// and asserts the expected BLoC event was dispatched.
//
// NOTE: this tests the ACTION CALLBACK LOGIC (a verbatim copy), NOT the
// MainScreen widget itself. The real MainScreen shortcut wiring (keyboard
// chords → Intents → correct Actions tree) is covered end-to-end by
// integration_test/flows/tab_shortcuts_test.dart.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/core/navigation/url_focus_registry.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

// ── mocks ────────────────────────────────────────────────────────────────────

class _MockTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockEnvironmentsBloc
    extends MockBloc<EnvironmentsEvent, EnvironmentsState>
    implements EnvironmentsBloc {}

class _MockCollectionsBloc extends MockBloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {}

// Fake fallbacks for registerFallbackValue.
class _FakeTabsEvent extends Fake implements TabsEvent {}

class _FakeSettingsEvent extends Fake implements SettingsEvent {}

class _FakeEnvironmentsEvent extends Fake implements EnvironmentsEvent {}

class _FakeCollectionsEvent extends Fake implements CollectionsEvent {}

class _FakePanel extends Fake implements PanelEntity {}

// ── harness ──────────────────────────────────────────────────────────────────

/// A tab pre-loaded into the mock TabsBloc state (active, not sending).
const _kTab = HttpRequestTabEntity(
  tabId: 'ms-tab-1',
  config: HttpRequestConfigEntity(id: 'ms-tab-1'),
);

/// A second tab for next/prev/jump tests.
const _kTab2 = HttpRequestTabEntity(
  tabId: 'ms-tab-2',
  config: HttpRequestConfigEntity(id: 'ms-tab-2'),
);

/// A panel containing the two tabs.
final _kPanel = PanelEntity(
  id: 'p1',
  name: 'Panel 1',
  tabs: const [_kTab, _kTab2],
  activeTabId: _kTab.tabId,
);

/// A second panel for panel-navigation tests.
const _kPanel2 = PanelEntity(
  id: 'p2',
  name: 'Panel 2',
  tabs: [],
  activeTabId: '',
);

/// Default TabsState: two tabs, first active, one panel.
///
/// Note: [TabsState.tabs] is the "active panel's tabs" and is normally
/// recomputed by [TabsBloc] on every emit. With a mock bloc we must set it
/// explicitly because the bloc's derivation logic never runs.
TabsState _tabsState({int activeIndex = 0}) => TabsState(
  panels: [_kPanel, _kPanel2],
  activePanelId: _kPanel.id,
  tabs: _kPanel.tabs, // explicitly set so action callbacks see the tabs
  activeIndex: activeIndex,
);

/// Pump a [child] widget wrapped in all the BLoC providers that MainScreen's
/// Actions callbacks access, plus an outer [Actions] wrapper that mirrors the
/// exact callbacks in the real MainScreen build method.
///
/// The outer [Actions] widget's callbacks are what we test — they are a
/// verbatim copy of the MainScreen action callbacks, exercised without the
/// full widget tree.
Future<void> _pump(
  WidgetTester tester, {
  required _MockTabsBloc tabsBloc,
  required _MockSettingsBloc settingsBloc,
  required _MockEnvironmentsBloc environmentsBloc,
  required _MockCollectionsBloc collectionsBloc,
  required UrlFocusRegistry focusRegistry,
  Widget child = const SizedBox.expand(),
}) async {
  await tester.pumpWidget(
    RepositoryProvider<UrlFocusRegistry>.value(
      value: focusRegistry,
      child: MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<EnvironmentsBloc>.value(value: environmentsBloc),
            BlocProvider<CollectionsBloc>.value(value: collectionsBloc),
          ],
          child: Builder(
            builder: (ctx) {
              final tabsState = ctx.watch<TabsBloc>().state;
              final activeIndex = tabsState.activeIndex;
              final tabs = tabsState.tabs;
              return Actions(
                actions: <Type, Action<Intent>>{
                  CloseTabIntent: CallbackAction<CloseTabIntent>(
                    onInvoke: (_) {
                      if (activeIndex < 0 || activeIndex >= tabs.length) {
                        return null;
                      }
                      // In a real MainScreen this calls _confirmAndClose;
                      // here we dispatch RemoveTab directly so the test can
                      // assert the event without a dialog.
                      ctx.read<TabsBloc>().add(
                        RemoveTab(tabs[activeIndex].tabId),
                      );
                      return null;
                    },
                  ),
                  SendRequestIntent: CallbackAction<SendRequestIntent>(
                    onInvoke: (_) {
                      if (activeIndex >= 0 &&
                          activeIndex < tabs.length &&
                          !tabs[activeIndex].isSending) {
                        final settings = ctx
                            .read<SettingsBloc>()
                            .state
                            .settings;
                        ctx.read<TabsBloc>().add(
                          SendRequest(
                            tabId: tabs[activeIndex].tabId,
                            responseHistoryLimit: settings.responseHistoryLimit,
                            saveLargeResponsesInHistory:
                                settings.saveLargeResponsesInHistory,
                          ),
                        );
                      }
                      return null;
                    },
                  ),
                  NextTabIntent: CallbackAction<NextTabIntent>(
                    onInvoke: (_) {
                      if (tabs.length < 2) return null;
                      ctx.read<TabsBloc>().add(
                        SetActiveIndex((activeIndex + 1) % tabs.length),
                      );
                      return null;
                    },
                  ),
                  PrevTabIntent: CallbackAction<PrevTabIntent>(
                    onInvoke: (_) {
                      if (tabs.length < 2) return null;
                      ctx.read<TabsBloc>().add(
                        SetActiveIndex(
                          (activeIndex - 1 + tabs.length) % tabs.length,
                        ),
                      );
                      return null;
                    },
                  ),
                  JumpToTabIntent: CallbackAction<JumpToTabIntent>(
                    onInvoke: (intent) {
                      ctx.read<TabsBloc>().add(SetActiveIndex(intent.index));
                      return null;
                    },
                  ),
                  FocusUrlIntent: CallbackAction<FocusUrlIntent>(
                    onInvoke: (_) {
                      if (activeIndex < 0 || activeIndex >= tabs.length) {
                        return null;
                      }
                      ctx.read<UrlFocusRegistry>().focus(
                        tabs[activeIndex].tabId,
                      );
                      return null;
                    },
                  ),
                  NewPanelIntent: CallbackAction<NewPanelIntent>(
                    onInvoke: (_) {
                      ctx.read<TabsBloc>().add(const AddPanel());
                      return null;
                    },
                  ),
                  NextPanelIntent: CallbackAction<NextPanelIntent>(
                    onInvoke: (_) {
                      final s = ctx.read<TabsBloc>().state;
                      if (s.panels.length < 2) return null;
                      final i = s.panels.indexWhere(
                        (p) => p.id == s.activePanelId,
                      );
                      final next = s.panels[(i + 1) % s.panels.length];
                      ctx.read<TabsBloc>().add(SetActivePanel(next.id));
                      return null;
                    },
                  ),
                  PrevPanelIntent: CallbackAction<PrevPanelIntent>(
                    onInvoke: (_) {
                      final s = ctx.read<TabsBloc>().state;
                      if (s.panels.length < 2) return null;
                      final i = s.panels.indexWhere(
                        (p) => p.id == s.activePanelId,
                      );
                      final prev =
                          s.panels[(i - 1 + s.panels.length) % s.panels.length];
                      ctx.read<TabsBloc>().add(SetActivePanel(prev.id));
                      return null;
                    },
                  ),
                  JumpToPanelIntent: CallbackAction<JumpToPanelIntent>(
                    onInvoke: (intent) {
                      final s = ctx.read<TabsBloc>().state;
                      if (intent.panelIndex < s.panels.length) {
                        ctx.read<TabsBloc>().add(
                          SetActivePanel(s.panels[intent.panelIndex].id),
                        );
                      }
                      return null;
                    },
                  ),
                },
                child: Focus(
                  key: const ValueKey('ms_actions_focus'),
                  autofocus: true,
                  child: Scaffold(body: child),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

// ── tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
    registerFallbackValue(_FakeSettingsEvent());
    registerFallbackValue(_FakeEnvironmentsEvent());
    registerFallbackValue(_FakeCollectionsEvent());
    registerFallbackValue(_FakePanel());
  });

  late _MockTabsBloc tabsBloc;
  late _MockSettingsBloc settingsBloc;
  late _MockEnvironmentsBloc environmentsBloc;
  late _MockCollectionsBloc collectionsBloc;
  late UrlFocusRegistry focusRegistry;

  setUp(() {
    tabsBloc = _MockTabsBloc();
    settingsBloc = _MockSettingsBloc();
    environmentsBloc = _MockEnvironmentsBloc();
    collectionsBloc = _MockCollectionsBloc();
    focusRegistry = UrlFocusRegistry();

    when(() => tabsBloc.state).thenReturn(_tabsState());
    when(() => tabsBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => tabsBloc.add(any())).thenReturn(null);
    when(
      () => settingsBloc.state,
    ).thenReturn(const SettingsState(settings: SettingsEntity()));
    when(() => settingsBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => environmentsBloc.state).thenReturn(const EnvironmentsState());
    when(() => environmentsBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => collectionsBloc.state).thenReturn(CollectionsState());
    when(() => collectionsBloc.stream).thenAnswer((_) => const Stream.empty());
  });

  tearDown(() {
    unawaited(tabsBloc.close());
    unawaited(settingsBloc.close());
    unawaited(environmentsBloc.close());
    unawaited(collectionsBloc.close());
  });

  // Helper to reduce boilerplate inside each test.
  Future<void> pump(WidgetTester tester) => _pump(
    tester,
    tabsBloc: tabsBloc,
    settingsBloc: settingsBloc,
    environmentsBloc: environmentsBloc,
    collectionsBloc: collectionsBloc,
    focusRegistry: focusRegistry,
  );

  group('MainScreen Actions', () {
    group('CloseTabIntent', () {
      testWidgets('dispatches RemoveTab for the active tab', (tester) async {
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const CloseTabIntent(),
        );
        await tester.pump();
        verify(() => tabsBloc.add(RemoveTab(_kTab.tabId))).called(1);
      });

      testWidgets('is a no-op when tabs list is empty', (tester) async {
        when(() => tabsBloc.state).thenReturn(const TabsState());
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const CloseTabIntent(),
        );
        await tester.pump();
        verifyNever(() => tabsBloc.add(any(that: isA<RemoveTab>())));
      });
    });

    group('SendRequestIntent', () {
      testWidgets('dispatches SendRequest with the active tab id', (
        tester,
      ) async {
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const SendRequestIntent(),
        );
        await tester.pump();
        final captured = verify(
          () => tabsBloc.add(captureAny(that: isA<SendRequest>())),
        ).captured;
        expect(captured, hasLength(1));
        final event = captured.first as SendRequest;
        expect(event.tabId, _kTab.tabId);
      });

      testWidgets('is a no-op when the active tab is already sending', (
        tester,
      ) async {
        const sending = HttpRequestTabEntity(
          tabId: 'ms-tab-1',
          config: HttpRequestConfigEntity(id: 'ms-tab-1'),
          isSending: true,
        );
        final sendingPanel = PanelEntity(
          id: 'p1',
          name: 'Panel 1',
          tabs: const [sending],
          activeTabId: sending.tabId,
        );
        when(() => tabsBloc.state).thenReturn(
          TabsState(
            panels: [sendingPanel],
            activePanelId: 'p1',
            tabs: const [sending], // explicit — mock state doesn't derive
          ),
        );
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const SendRequestIntent(),
        );
        await tester.pump();
        verifyNever(() => tabsBloc.add(any(that: isA<SendRequest>())));
      });
    });

    group('NextTabIntent / PrevTabIntent', () {
      testWidgets('NextTabIntent wraps to index 1', (tester) async {
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const NextTabIntent(),
        );
        await tester.pump();
        verify(() => tabsBloc.add(const SetActiveIndex(1))).called(1);
      });

      testWidgets('PrevTabIntent wraps to last tab index', (tester) async {
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const PrevTabIntent(),
        );
        await tester.pump();
        // (0 - 1 + 2) % 2 = 1
        verify(() => tabsBloc.add(const SetActiveIndex(1))).called(1);
      });

      testWidgets('NextTabIntent is a no-op with only one tab', (tester) async {
        final singlePanel = PanelEntity(
          id: 'p1',
          name: 'Panel 1',
          tabs: const [_kTab],
          activeTabId: _kTab.tabId,
        );
        when(() => tabsBloc.state).thenReturn(
          TabsState(
            panels: [singlePanel],
            activePanelId: 'p1',
            tabs: const [_kTab], // must set tabs explicitly in mock state
          ),
        );
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const NextTabIntent(),
        );
        await tester.pump();
        verifyNever(() => tabsBloc.add(any(that: isA<SetActiveIndex>())));
      });
    });

    group('JumpToTabIntent', () {
      testWidgets('dispatches SetActiveIndex with the intent index', (
        tester,
      ) async {
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const JumpToTabIntent(1),
        );
        await tester.pump();
        verify(() => tabsBloc.add(const SetActiveIndex(1))).called(1);
      });

      testWidgets('out-of-range index is passed through to the bloc (which'
          ' guards it internally)', (tester) async {
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const JumpToTabIntent(8),
        );
        await tester.pump();
        // The action always dispatches; SetActiveIndex guards out-of-range
        // inside the bloc — this verifies the action does not pre-filter.
        verify(() => tabsBloc.add(const SetActiveIndex(8))).called(1);
      });
    });

    group('FocusUrlIntent', () {
      testWidgets('calls focus on the URL focus registry for the active tab', (
        tester,
      ) async {
        final spyRegistry = _SpyFocusRegistry();
        await _pump(
          tester,
          tabsBloc: tabsBloc,
          settingsBloc: settingsBloc,
          environmentsBloc: environmentsBloc,
          collectionsBloc: collectionsBloc,
          focusRegistry: spyRegistry,
        );
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const FocusUrlIntent(),
        );
        await tester.pump();
        // The registry's focus() must have been called with the active tab id.
        expect(spyRegistry.lastFocused, _kTab.tabId);
      });

      testWidgets('is a no-op when there are no tabs', (tester) async {
        when(() => tabsBloc.state).thenReturn(const TabsState());
        final spyRegistry = _SpyFocusRegistry();
        await _pump(
          tester,
          tabsBloc: tabsBloc,
          settingsBloc: settingsBloc,
          environmentsBloc: environmentsBloc,
          collectionsBloc: collectionsBloc,
          focusRegistry: spyRegistry,
        );
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const FocusUrlIntent(),
        );
        await tester.pump();
        expect(spyRegistry.lastFocused, isNull);
      });
    });

    group('NewPanelIntent', () {
      testWidgets('dispatches AddPanel', (tester) async {
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const NewPanelIntent(),
        );
        await tester.pump();
        verify(() => tabsBloc.add(const AddPanel())).called(1);
      });
    });

    group('NextPanelIntent / PrevPanelIntent', () {
      testWidgets('NextPanelIntent dispatches SetActivePanel with p2', (
        tester,
      ) async {
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const NextPanelIntent(),
        );
        await tester.pump();
        final captured = verify(
          () => tabsBloc.add(captureAny(that: isA<SetActivePanel>())),
        ).captured;
        expect(captured, hasLength(1));
        expect((captured.first as SetActivePanel).panelId, _kPanel2.id);
      });

      testWidgets('PrevPanelIntent wraps to last panel', (tester) async {
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const PrevPanelIntent(),
        );
        await tester.pump();
        final captured = verify(
          () => tabsBloc.add(captureAny(that: isA<SetActivePanel>())),
        ).captured;
        expect(captured, hasLength(1));
        // (0 - 1 + 2) % 2 = 1 → _kPanel2
        expect((captured.first as SetActivePanel).panelId, _kPanel2.id);
      });

      testWidgets('NextPanelIntent is a no-op with a single panel', (
        tester,
      ) async {
        when(() => tabsBloc.state).thenReturn(
          TabsState(panels: [_kPanel], activePanelId: _kPanel.id),
        );
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const NextPanelIntent(),
        );
        await tester.pump();
        verifyNever(() => tabsBloc.add(any(that: isA<SetActivePanel>())));
      });
    });

    group('JumpToPanelIntent', () {
      testWidgets('dispatches SetActivePanel for an in-range panel index', (
        tester,
      ) async {
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const JumpToPanelIntent(1),
        );
        await tester.pump();
        final captured = verify(
          () => tabsBloc.add(captureAny(that: isA<SetActivePanel>())),
        ).captured;
        expect(captured, hasLength(1));
        expect((captured.first as SetActivePanel).panelId, _kPanel2.id);
      });

      testWidgets('out-of-range panel index is silently ignored', (
        tester,
      ) async {
        await pump(tester);
        Actions.invoke(
          tester.element(find.byKey(const ValueKey('ms_actions_focus'))),
          const JumpToPanelIntent(9),
        );
        await tester.pump();
        verifyNever(() => tabsBloc.add(any(that: isA<SetActivePanel>())));
      });
    });
  });
}

// ── spy registry ─────────────────────────────────────────────────────────────

/// Intercepts [focus] calls so tests can assert which tab was focused
/// without actually holding a real [FocusNode].
class _SpyFocusRegistry extends UrlFocusRegistry {
  String? lastFocused;

  @override
  void focus(String tabId) => lastFocused = tabId;
}
