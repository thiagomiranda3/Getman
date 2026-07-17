// Widget tests for UnifiedRequestPanel's auto-jump-to-RESPONSE listener.
//
// Regression guard (A4): the listenWhen used to treat any isSending
// true→false transition with a non-null response as "send completed", but a
// cancelled request also flips isSending false while leaving the *same*
// (unchanged) response in place — tabs_bloc only clears isSending on cancel.
// That wrongly auto-jumped the phone layout to RESPONSE on cancel. The fix
// additionally requires the response instance to have changed
// (`!identical(prev?.response, next?.response)`).
//
// Uses a fake TabsBloc whose state can be pushed directly (bypassing the real
// send/cancel machinery) so the exact prev/next response identity can be
// controlled precisely.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/domain/usecases/request_rules_usecases.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';
import 'package:getman/features/tabs/presentation/widgets/unified_request_panel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

class _MockSaveSettingsUseCase extends Mock implements SaveSettingsUseCase {}

class _MockGetEnvironmentsUseCase extends Mock
    implements GetEnvironmentsUseCase {}

class _MockSaveEnvironmentsUseCase extends Mock
    implements SaveEnvironmentsUseCase {}

class _MockPutEnvironmentUseCase extends Mock
    implements PutEnvironmentUseCase {}

class _MockDeleteEnvironmentUseCase extends Mock
    implements DeleteEnvironmentUseCase {}

class _MockGetRequestRulesUseCase extends Mock
    implements GetRequestRulesUseCase {}

class _MockSaveRequestRulesUseCase extends Mock
    implements SaveRequestRulesUseCase {}

class _FakeRules extends Fake implements RequestRulesEntity {}

class _FakeCollectionsBloc extends Bloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {
  _FakeCollectionsBloc() : super(CollectionsState());
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc() : super(const HistoryState());
}

/// A controllable fake TabsBloc: tests push states directly instead of going
/// through the real send/cancel machinery, so the exact prev/next response
/// identity is fully under test control.
class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initialState);

  void push(TabsState next) => emit(next);
}

SettingsBloc _settingsBloc() {
  final save = _MockSaveSettingsUseCase();
  when(() => save(any())).thenAnswer((_) async {});
  return SettingsBloc(
    saveSettingsUseCase: save,
    initialSettings: const SettingsEntity(),
  );
}

EnvironmentsBloc _environmentsBloc() {
  final get = _MockGetEnvironmentsUseCase();
  when(get.call).thenAnswer((_) async => const <EnvironmentEntity>[]);
  return EnvironmentsBloc(
    getEnvironmentsUseCase: get,
    saveEnvironmentsUseCase: _MockSaveEnvironmentsUseCase(),
    putEnvironmentUseCase: _MockPutEnvironmentUseCase(),
    deleteEnvironmentUseCase: _MockDeleteEnvironmentUseCase(),
  );
}

RulesBloc _rulesBloc(String tabId) {
  final get = _MockGetRequestRulesUseCase();
  final save = _MockSaveRequestRulesUseCase();
  when(() => get.call(any())).thenAnswer(
    (_) async => RequestRulesEntity(configId: tabId),
  );
  when(() => save.call(any())).thenAnswer((_) async {});
  return RulesBloc(getRequestRulesUseCase: get, saveRequestRulesUseCase: save);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeRules());
    registerFallbackValue(const SettingsEntity());
  });

  const tabId = 'panel_a4';
  const respA = HttpResponseEntity(
    statusCode: 200,
    body: 'first',
    headers: {},
    durationMs: 5,
  );

  HttpRequestTabEntity tabWith({
    required bool isSending,
    HttpResponseEntity? response,
  }) => HttpRequestTabEntity(
    tabId: tabId,
    config: const HttpRequestConfigEntity(id: tabId),
    isSending: isSending,
    response: response,
  );

  Future<_FakeTabsBloc> pumpPanel(
    WidgetTester tester,
    _FakeTabsBloc tabsBloc,
  ) async {
    final rulesBloc = _rulesBloc(tabId);
    addTearDown(rulesBloc.close);
    final bodyController = CodeLineEditingController();
    addTearDown(bodyController.dispose);
    final variablesController = CodeLineEditingController();
    addTearDown(variablesController.dispose);
    final responseController = CodeLineEditingController();
    addTearDown(responseController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<TabsBloc>.value(value: tabsBloc),
              BlocProvider<SettingsBloc>(create: (_) => _settingsBloc()),
              BlocProvider<EnvironmentsBloc>(
                create: (_) => _environmentsBloc(),
              ),
              BlocProvider<CollectionsBloc>(
                create: (_) => _FakeCollectionsBloc(),
              ),
              BlocProvider<HistoryBloc>(create: (_) => _FakeHistoryBloc()),
              BlocProvider<RulesBloc>.value(value: rulesBloc),
            ],
            child: ChangeNotifierProvider<RequestSectionIndex>(
              create: (_) => RequestSectionIndex(),
              child: UnifiedRequestPanel(
                tabId: tabId,
                bodyController: bodyController,
                variablesController: variablesController,
                responseController: responseController,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    return tabsBloc;
  }

  // Nested tab strips exist inside RESPONSE (ResponseSection has its own
  // TabBarView) — the outer one (this panel's PARAMS/AUTH/.../RESPONSE
  // strip) is the first in the tree.
  int tabControllerIndex(WidgetTester tester) => tester
      .widget<TabBarView>(find.byType(TabBarView).first)
      .controller!
      .index;

  testWidgets(
    'cancelling a request (isSending true→false, response unchanged) does '
    'NOT auto-jump to RESPONSE — regression guard (A4)',
    (tester) async {
      final tabsBloc = _FakeTabsBloc(
        TabsState(tabs: [tabWith(isSending: false, response: respA)]),
      );
      addTearDown(tabsBloc.close);

      await pumpPanel(tester, tabsBloc);
      expect(tabControllerIndex(tester), 0, reason: 'starts on PARAMS');

      // Send starts: isSending flips true, response stays the same instance.
      tabsBloc.push(
        TabsState(tabs: [tabWith(isSending: true, response: respA)]),
      );
      await tester.pump();

      // Cancelled: isSending flips back to false, response is STILL the same
      // instance (tabs_bloc's cancel path only clears isSending).
      tabsBloc.push(
        TabsState(tabs: [tabWith(isSending: false, response: respA)]),
      );
      await tester.pumpAndSettle();

      expect(
        tabControllerIndex(tester),
        0,
        reason: 'a cancelled send must not steal focus to RESPONSE',
      );
    },
  );

  testWidgets(
    'a genuinely completed send (new response instance) DOES auto-jump to '
    'RESPONSE',
    (tester) async {
      final tabsBloc = _FakeTabsBloc(
        TabsState(tabs: [tabWith(isSending: false)]),
      );
      addTearDown(tabsBloc.close);

      await pumpPanel(tester, tabsBloc);
      expect(tabControllerIndex(tester), 0, reason: 'starts on PARAMS');

      tabsBloc.push(TabsState(tabs: [tabWith(isSending: true)]));
      await tester.pump();

      // Completed: a brand-new HttpResponseEntity instance is recorded.
      tabsBloc.push(
        TabsState(
          tabs: [
            tabWith(
              isSending: false,
              response: const HttpResponseEntity(
                statusCode: 200,
                body: 'done',
                headers: {},
                durationMs: 5,
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tabControllerIndex(tester),
        5,
        reason: 'a real completed send must still auto-jump to RESPONSE',
      );
    },
  );
}
