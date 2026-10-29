import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/domain/usecases/request_rules_usecases.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockGetRequestRulesUseCase extends Mock
    implements GetRequestRulesUseCase {}

/// Observes actual handler completion so race assertions need no timers.
class _ObservedTabsBloc extends TabsBloc {
  _ObservedTabsBloc({
    required super.repository,
    required super.sendRequestUseCase,
    required super.getRequestRulesUseCase,
  });

  final sendDone = Completer<void>();
  final cancelDone = Completer<void>();

  @override
  void onDone(TabsEvent event, [Object? error, StackTrace? stackTrace]) {
    super.onDone(event, error, stackTrace);
    if (event is SendRequest && !sendDone.isCompleted) sendDone.complete();
    if (event is CancelRequest && !cancelDone.isCompleted) {
      cancelDone.complete();
    }
  }
}

void main() {
  late MockTabsRepository repository;
  late MockSendRequestUseCase sendRequestUseCase;
  setUpAll(() {
    registerFallbackValue(const HttpRequestConfigEntity(id: 'fallback'));
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
    registerFallbackValue(
      const PanelEntity(
        id: 'fallback',
        name: 'Panel',
        tabs: [],
        activeTabId: '',
      ),
    );
  });
  setUp(() {
    repository = MockTabsRepository();
    sendRequestUseCase = MockSendRequestUseCase();
    when(() => repository.putTab(any())).thenAnswer((_) async {});
    when(() => repository.putPanel(any())).thenAnswer((_) async {});
    when(() => repository.savePanelMeta(any(), any())).thenAnswer((_) async {});
    when(() => repository.deleteTabs(any())).thenAnswer((_) async {});
  });
  HttpRequestTabEntity tab(String id) => HttpRequestTabEntity(
    tabId: id,
    config: HttpRequestConfigEntity(id: id),
  );
  void stubSend(Future<HttpResponseEntity> Function() answer) {
    when(
      () => sendRequestUseCase.call(
        config: any(named: 'config'),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    ).thenAnswer((_) => answer());
  }

  for (final cancelDuringCompute in [false, true]) {
    test(
      'cancelled rules publish no captures: compute=$cancelDuringCompute',
      () async {
        final rules = MockGetRequestRulesUseCase();
        final pending = Completer<RequestRulesEntity>();
        final started = Completer<void>();
        when(() => rules.call('t1')).thenAnswer((_) {
          started.complete();
          return pending.future;
        });
        final ruleBloc = _ObservedTabsBloc(
          repository: repository,
          sendRequestUseCase: sendRequestUseCase,
          getRequestRulesUseCase: rules,
        );
        addTearDown(ruleBloc.close);
        when(() => repository.getPanels()).thenAnswer(
          (_) async => [
            PanelEntity(
              id: 'p1',
              name: 'Panel',
              tabs: [tab('t1')],
              activeTabId: 't1',
            ),
          ],
        );
        when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');
        ruleBloc.add(const LoadTabs());
        await ruleBloc.stream.firstWhere(
          (s) => !s.isLoading && s.tabs.isNotEmpty,
        );
        final padding = cancelDuringCompute ? ' ' * (65 * 1024) : '';
        stubSend(
          () async => HttpResponseEntity(
            statusCode: 200,
            body: '{"token":"old"}$padding',
            headers: const {},
            durationMs: 1,
          ),
        );
        ruleBloc.add(const SendRequest(tabId: 't1'));
        await started.future;
        expect(ruleBloc.state.tabs.single.isSending, isFalse);
        if (!cancelDuringCompute) {
          ruleBloc.add(const CancelRequest('t1'));
          await ruleBloc.cancelDone.future;
        }
        pending.complete(
          const RequestRulesEntity(
            configId: 't1',
            assertions: [Assertion(id: 'a1', expected: '200')],
            extractionRules: [
              ExtractionRule(
                id: 'r1',
                expression: 'token',
                targetVariable: 'tok',
              ),
            ],
          ),
        );
        if (cancelDuringCompute) {
          // The rule-loading continuation is queued first and starts compute.
          // Cancel runs in the next microtask, before any isolate result event.
          scheduleMicrotask(() => ruleBloc.add(const CancelRequest('t1')));
          await ruleBloc.cancelDone.future;
        }
        await ruleBloc.sendDone.future;
        expect(ruleBloc.state.tabs.single.extractionResults, isEmpty);
        expect(ruleBloc.state.tabs.single.assertionResults, isEmpty);
        expect(ruleBloc.state.tabs.single.isSending, isFalse);
      },
    );
  }

  test('older rules cannot overwrite a newer response capture', () async {
    final rules = MockGetRequestRulesUseCase();
    const ruleSet = RequestRulesEntity(
      configId: 't1',
      extractionRules: [
        ExtractionRule(id: 'r1', expression: 'token', targetVariable: 'tok'),
      ],
    );
    final oldRules = Completer<RequestRulesEntity>();
    final oldStarted = Completer<void>();
    var calls = 0;
    when(() => rules.call('t1')).thenAnswer((_) {
      calls++;
      if (calls == 1) {
        oldStarted.complete();
        return oldRules.future;
      }
      return Future.value(ruleSet);
    });
    final ruleBloc = TabsBloc(
      repository: repository,
      sendRequestUseCase: sendRequestUseCase,
      getRequestRulesUseCase: rules,
    );
    addTearDown(ruleBloc.close);
    when(() => repository.getPanels()).thenAnswer(
      (_) async => [
        PanelEntity(
          id: 'p1',
          name: 'Panel',
          tabs: [tab('t1')],
          activeTabId: 't1',
        ),
      ],
    );
    when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');
    ruleBloc.add(const LoadTabs());
    await ruleBloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
    var sends = 0;
    stubSend(
      () async => HttpResponseEntity(
        statusCode: 200,
        body: '{"token":"${++sends == 1 ? 'old' : 'new'}"}',
        headers: const {},
        durationMs: 1,
      ),
    );
    ruleBloc.add(const SendRequest(tabId: 't1'));
    await oldStarted.future;
    expect(ruleBloc.state.tabs.single.isSending, false);
    ruleBloc.add(const SendRequest(tabId: 't1'));
    await ruleBloc.stream.firstWhere(
      (s) => s.tabs.single.extractionResults.any((r) => r.value == 'new'),
    );
    oldRules.complete(ruleSet);
    await Future<void>.delayed(Duration.zero);
    expect(ruleBloc.state.tabs.single.response!.body, '{"token":"new"}');
    expect(ruleBloc.state.tabs.single.extractionResults.single.value, 'new');
  });

  test('closing and reopening a tab invalidates its pending rules', () async {
    final rules = MockGetRequestRulesUseCase();
    final pending = Completer<RequestRulesEntity>();
    final started = Completer<void>();
    when(() => rules.call('t1')).thenAnswer((_) {
      started.complete();
      return pending.future;
    });
    final ruleBloc = TabsBloc(
      repository: repository,
      sendRequestUseCase: sendRequestUseCase,
      getRequestRulesUseCase: rules,
    );
    addTearDown(ruleBloc.close);
    when(() => repository.getPanels()).thenAnswer(
      (_) async => [
        PanelEntity(
          id: 'p1',
          name: 'Panel',
          tabs: [tab('t1')],
          activeTabId: 't1',
        ),
      ],
    );
    when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');
    ruleBloc.add(const LoadTabs());
    await ruleBloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
    stubSend(
      () async => const HttpResponseEntity(
        statusCode: 200,
        body: '{"token":"old"}',
        headers: {},
        durationMs: 1,
      ),
    );
    ruleBloc.add(const SendRequest(tabId: 't1'));
    await started.future;
    ruleBloc.add(const RemoveTab('t1'));
    await ruleBloc.stream.firstWhere((s) => s.tabs.isEmpty);
    ruleBloc.add(const ReopenClosedTab());
    await ruleBloc.stream.firstWhere((s) => s.tabs.isNotEmpty);
    pending.complete(
      const RequestRulesEntity(
        configId: 't1',
        extractionRules: [
          ExtractionRule(id: 'r1', expression: 'token', targetVariable: 'tok'),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(ruleBloc.state.tabs.single.extractionResults, isEmpty);
    expect(ruleBloc.state.tabs.single.isSending, isFalse);
  });
}
