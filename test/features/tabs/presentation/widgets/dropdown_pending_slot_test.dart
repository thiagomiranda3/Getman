// Tests that the response-pending skeleton routes through the pendingIndicator
// slot and fills the panel correctly (no RenderFlex overflow).
//
// RequestKindMethodSelector and PanelSelector are intentionally NOT routed
// through AppDropdown/select — see B7 report for rationale.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_components.dart';
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

/// Creates a [TabsBloc] pre-loaded with a single panel containing [tab].
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

/// Pumps [ResponseSection] inside a themed app with all required blocs.
Future<void> _pump(
  WidgetTester tester, {
  required TabsBloc bloc,
  required String tabId,
  required CodeLineEditingController controller,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
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
            showMetadata: false,
          ),
        ),
      ),
    ),
  );
  // Single pump: build the frame from current bloc state without draining
  // async completions (keeps the isSending:true state visible).
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

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
  // Pending shimmer routes through the pendingIndicator slot.
  //
  // Strategy: dispatch SendRequest with a Completer-backed mock so the tab
  // enters isSending:true. The completer is completed with a NetworkFailure
  // (cancelled) at the END of the test body — before the test framework's
  // tearDown runs bloc.close() — so the bloc's in-flight handler can drain
  // cleanly without hanging.
  //
  // Note: LoadTabs resets isSending→false by design (CLAUDE.md §4.2).
  // -------------------------------------------------------------------------

  testWidgets(
    'isSending tab renders pending skeleton via pendingIndicator slot '
    '(no exception)',
    (tester) async {
      const tabId = 'tabPending';
      final completer = Completer<HttpResponseEntity>();
      when(
        () => sendRequestUseCase(
          config: any(named: 'config'),
          envVars: any(named: 'envVars'),
          cancelHandle: any(named: 'cancelHandle'),
        ),
      ).thenAnswer((_) => completer.future);

      const tab = HttpRequestTabEntity(
        tabId: tabId,
        config: HttpRequestConfigEntity(id: tabId),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      // Trigger isSending:true by dispatching SendRequest.
      bloc.add(const SendRequest(tabId: tabId));
      // Wait for isSending:true to propagate in the stream.
      await bloc.stream.firstWhere((s) {
        final t = s.tabs.firstWhere(
          (x) => x.tabId == tabId,
          orElse: () => const HttpRequestTabEntity(
            tabId: '_none',
            config: HttpRequestConfigEntity(id: '_none'),
          ),
        );
        return t.isSending;
      });

      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);

      await _pump(tester, bloc: bloc, tabId: tabId, controller: controller);

      // The brutalist pendingIndicator slot renders BrutalPressIndicator
      // (ink-press skeleton), not a Shimmer.
      expect(find.byType(BrutalPressIndicator), findsOneWidget);
      // No RenderFlex overflow or other exception.
      expect(tester.takeException(), isNull);

      // Complete the in-flight request before tearDown runs bloc.close() so
      // the bloc can drain without hanging.
      completer.completeError(
        const NetworkFailure(
          'cancelled',
          type: NetworkFailureType.cancelled,
        ),
      );
      // Let the error propagate through the bloc handler.
      await tester.pump();
    },
  );

  testWidgets(
    'isSending tab pending skeleton has Semantics liveRegion label',
    (tester) async {
      const tabId = 'tabPendingSem';
      final completer = Completer<HttpResponseEntity>();
      when(
        () => sendRequestUseCase(
          config: any(named: 'config'),
          envVars: any(named: 'envVars'),
          cancelHandle: any(named: 'cancelHandle'),
        ),
      ).thenAnswer((_) => completer.future);

      const tab = HttpRequestTabEntity(
        tabId: tabId,
        config: HttpRequestConfigEntity(id: tabId),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      bloc.add(const SendRequest(tabId: tabId));
      await bloc.stream.firstWhere((s) {
        final t = s.tabs.firstWhere(
          (x) => x.tabId == tabId,
          orElse: () => const HttpRequestTabEntity(
            tabId: '_none',
            config: HttpRequestConfigEntity(id: '_none'),
          ),
        );
        return t.isSending;
      });

      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);

      await _pump(tester, bloc: bloc, tabId: tabId, controller: controller);

      // Brutalist theme: BrutalPressIndicator wraps the skeleton in Semantics.
      expect(find.byType(BrutalPressIndicator), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(BrutalPressIndicator)),
        matchesSemantics(label: 'PRINTING…', isLiveRegion: true),
      );

      completer.completeError(
        const NetworkFailure(
          'cancelled',
          type: NetworkFailureType.cancelled,
        ),
      );
      await tester.pump();
    },
  );
}
