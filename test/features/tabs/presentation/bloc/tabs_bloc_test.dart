import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/domain/usecases/request_rules_usecases.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class MockGetRequestRulesUseCase extends Mock
    implements GetRequestRulesUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

void main() {
  late MockTabsRepository repository;
  late MockSendRequestUseCase sendRequestUseCase;
  late TabsBloc bloc;

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(
      const HttpRequestTabEntity(
        tabId: 'fallback',
        config: HttpRequestConfigEntity(id: 'fallback'),
      ),
    );
  });

  setUp(() {
    repository = MockTabsRepository();
    sendRequestUseCase = MockSendRequestUseCase();
    when(() => repository.saveTabs(any())).thenAnswer((_) async {});
    when(() => repository.putTab(any())).thenAnswer((_) async {});
    when(() => repository.deleteTabs(any())).thenAnswer((_) async {});
    when(() => repository.saveTabOrder(any())).thenAnswer((_) async {});
    bloc = TabsBloc(
      repository: repository,
      sendRequestUseCase: sendRequestUseCase,
    );
  });

  tearDown(() => bloc.close());

  HttpRequestTabEntity tab(String id, {bool isSending = false}) =>
      HttpRequestTabEntity(
        tabId: id,
        isSending: isSending,
        config: HttpRequestConfigEntity(id: id, url: 'https://$id.dev'),
      );

  Matcher hasTabId(String id) =>
      isA<HttpRequestTabEntity>().having((t) => t.tabId, 'tabId', id);

  Future<void> loadWith(List<HttpRequestTabEntity> tabs) async {
    when(() => repository.getTabs()).thenAnswer((_) async => tabs);
    bloc.add(const LoadTabs());
    await expectLater(
      bloc.stream,
      emitsThrough(predicate<TabsState>((s) => !s.isLoading)),
    );
  }

  void stubSend(Future<HttpResponseEntity> Function() answer) {
    when(
      () => sendRequestUseCase.call(
        config: any(named: 'config'),
        envVars: any(named: 'envVars'),
        cancelHandle: any(named: 'cancelHandle'),
      ),
    ).thenAnswer((_) => answer());
  }

  group('LoadTabs', () {
    test('seeds a single sample request when nothing is persisted', () async {
      await loadWith([]);
      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.activeIndex, 0);
      expect(bloc.state.tabs.single.config.url, 'https://httpbin.org/get');
    });

    test('resets stale isSending flags from a previous session', () async {
      await loadWith([tab('a', isSending: true), tab('b')]);
      expect(bloc.state.tabs.map((t) => t.isSending), everyElement(isFalse));
    });

    test(
      'persists the auto-created tab and its order on a fresh boot',
      () async {
        await loadWith([]);
        await pumpEventQueue();

        final id = bloc.state.tabs.single.tabId;
        verify(() => repository.putTab(any(that: hasTabId(id)))).called(1);
        verify(() => repository.saveTabOrder([id])).called(1);
        verifyNever(() => repository.saveTabs(any()));
      },
    );
  });

  group('incremental persistence', () {
    test(
      'AddTab persists the new tab and the order, never the full list',
      () async {
        await loadWith([tab('a')]);
        bloc.add(const AddTab());
        await pumpEventQueue();

        final newId = bloc.state.tabs.last.tabId;
        verify(() => repository.putTab(any(that: hasTabId(newId)))).called(1);
        verify(() => repository.saveTabOrder(['a', newId])).called(1);
        verifyNever(() => repository.saveTabs(any()));
      },
    );

    test('RemoveTab deletes the tab and rewrites only the order', () async {
      await loadWith([tab('a'), tab('b'), tab('c')]);
      bloc.add(const RemoveTab('c'));
      await pumpEventQueue();

      verify(() => repository.deleteTabs(['c'])).called(1);
      verify(() => repository.saveTabOrder(['a', 'b'])).called(1);
      verifyNever(() => repository.putTab(any()));
      verifyNever(() => repository.saveTabs(any()));
    });

    test('DuplicateTab persists the copy and the order', () async {
      await loadWith([tab('a'), tab('b')]);
      bloc.add(const DuplicateTab('a'));
      await pumpEventQueue();

      final copyId = bloc.state.tabs[1].tabId;
      verify(() => repository.putTab(any(that: hasTabId(copyId)))).called(1);
      verify(() => repository.saveTabOrder(['a', copyId, 'b'])).called(1);
      verifyNever(() => repository.saveTabs(any()));
    });

    test('ReorderTabs persists only the order', () async {
      await loadWith([tab('a'), tab('b'), tab('c')]);
      bloc.add(const ReorderTabs(0, 3));
      await pumpEventQueue();

      verify(() => repository.saveTabOrder(['b', 'c', 'a'])).called(1);
      verifyNever(() => repository.putTab(any()));
      verifyNever(() => repository.deleteTabs(any()));
      verifyNever(() => repository.saveTabs(any()));
    });

    test(
      'CloseOtherTabs deletes the removed tabs and rewrites the order',
      () async {
        await loadWith([tab('a'), tab('b'), tab('c')]);
        bloc.add(const CloseOtherTabs('b'));
        await pumpEventQueue();

        verify(() => repository.deleteTabs(['a', 'c'])).called(1);
        verify(() => repository.saveTabOrder(['b'])).called(1);
        verifyNever(() => repository.putTab(any()));
        verifyNever(() => repository.saveTabs(any()));
      },
    );

    test(
      'CloseTabsToTheRight deletes the removed tabs and rewrites the order',
      () async {
        await loadWith([tab('a'), tab('b'), tab('c')]);
        bloc.add(const CloseTabsToTheRight('a'));
        await pumpEventQueue();

        verify(() => repository.deleteTabs(['b', 'c'])).called(1);
        verify(() => repository.saveTabOrder(['a'])).called(1);
        verifyNever(() => repository.putTab(any()));
        verifyNever(() => repository.saveTabs(any()));
      },
    );

    test(
      'UpdateTab marks the tab dirty and the flush persists only that tab',
      () async {
        await loadWith([tab('a'), tab('b')]);
        final updated = bloc.state.tabs.first.copyWith(
          config: bloc.state.tabs.first.config.copyWith(
            url: 'https://edited.dev',
          ),
        );
        bloc.add(UpdateTab(updated));
        await pumpEventQueue();

        verifyNever(
          () => repository.putTab(any()),
        ); // debounced, not yet flushed
        await bloc.close(); // close() must flush the pending dirty set

        final persisted = verify(
          () => repository.putTab(captureAny()),
        ).captured;
        expect(persisted, hasLength(1));
        expect(persisted.single, hasTabId('a'));
        expect(
          (persisted.single as HttpRequestTabEntity).config.url,
          'https://edited.dev',
        );
        verifyNever(() => repository.saveTabs(any()));
      },
    );

    test('a dirty tab closed before the flush is not persisted', () async {
      await loadWith([tab('a'), tab('b')]);
      final updated = bloc.state.tabs.first.copyWith(
        config: bloc.state.tabs.first.config.copyWith(
          url: 'https://edited.dev',
        ),
      );
      bloc
        ..add(UpdateTab(updated))
        ..add(const RemoveTab('a'));
      await pumpEventQueue();

      await bloc.close();

      verifyNever(() => repository.putTab(any(that: hasTabId('a'))));
      verify(() => repository.deleteTabs(['a'])).called(1);
    });

    test(
      'a received response marks the tab dirty so the flush persists it',
      () async {
        await loadWith([tab('a')]);
        stubSend(
          () async => const HttpResponseEntity(
            statusCode: 200,
            body: '{"ok":true}',
            headers: {},
            durationMs: 1,
          ),
        );

        bloc.add(const SendRequest(tabId: 'a'));
        await expectLater(
          bloc.stream,
          emitsThrough(
            predicate<TabsState>((s) => s.tabs.single.response != null),
          ),
        );
        await bloc.close();

        final persisted = verify(
          () => repository.putTab(captureAny()),
        ).captured;
        expect(persisted, hasLength(1));
        expect(persisted.single, hasTabId('a'));
        expect(
          (persisted.single as HttpRequestTabEntity).response?.statusCode,
          200,
        );
      },
    );
  });

  group('tab management', () {
    test('RemoveTab drops the tab by id and clamps the active index', () async {
      await loadWith([tab('a'), tab('b'), tab('c')]);
      bloc.add(const SetActiveIndex(2));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const RemoveTab('c'));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.tabs.map((t) => t.tabId), ['a', 'b']);
      expect(bloc.state.activeIndex, 1);
    });

    test('RemoveTab for an unknown id is a no-op', () async {
      await loadWith([tab('a')]);
      bloc.add(const RemoveTab('ghost'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.tabs, hasLength(1));
    });

    test('CloseOtherTabs keeps only the addressed tab', () async {
      await loadWith([tab('a'), tab('b'), tab('c')]);
      bloc.add(const CloseOtherTabs('b'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.tabs.map((t) => t.tabId), ['b']);
      expect(bloc.state.activeIndex, 0);
    });

    test(
      'CloseTabsToTheRight keeps the addressed tab and everything left of it',
      () async {
        await loadWith([tab('a'), tab('b'), tab('c')]);
        bloc.add(const SetActiveIndex(2));
        await Future<void>.delayed(Duration.zero);

        bloc.add(const CloseTabsToTheRight('a'));
        await Future<void>.delayed(Duration.zero);

        expect(bloc.state.tabs.map((t) => t.tabId), ['a']);
        expect(bloc.state.activeIndex, 0);
      },
    );

    test(
      'DuplicateTab inserts an unsaved copy right after the source',
      () async {
        await loadWith([tab('a'), tab('b')]);
        bloc.add(const DuplicateTab('a'));
        await Future<void>.delayed(Duration.zero);

        expect(bloc.state.tabs, hasLength(3));
        final copy = bloc.state.tabs[1];
        expect(copy.tabId, isNot('a'));
        expect(copy.config.url, 'https://a.dev');
        expect(copy.collectionNodeId, isNull);
        expect(bloc.state.activeIndex, 1);
      },
    );

    test(
      'AddTab focuses an existing tab for the same collection node instead of '
      'duplicating',
      () async {
        await loadWith([]);
        bloc.add(
          const AddTab(
            config: HttpRequestConfigEntity(id: 'n1'),
            collectionNodeId: 'node-1',
            collectionName: 'Login',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.tabs, hasLength(2));

        bloc.add(const SetActiveIndex(0));
        await Future<void>.delayed(Duration.zero);
        bloc.add(
          const AddTab(
            config: HttpRequestConfigEntity(id: 'n1'),
            collectionNodeId: 'node-1',
            collectionName: 'Login',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          bloc.state.tabs,
          hasLength(2),
          reason: 'no duplicate tab for the same node',
        );
        expect(bloc.state.activeIndex, 1);
      },
    );
  });

  group('SetActiveIndex', () {
    test(
      'ignores out-of-range indices so widgets can index tabs safely',
      () async {
        await loadWith([]);
        expect(bloc.state.activeIndex, 0);

        bloc
          ..add(const SetActiveIndex(99))
          ..add(const SetActiveIndex(-1));
        await Future<void>.delayed(Duration.zero);

        expect(bloc.state.activeIndex, 0);
      },
    );
  });

  group('SendRequest', () {
    const response = HttpResponseEntity(
      statusCode: 200,
      body: '{"ok":true}',
      headers: {'content-type': 'application/json'},
      durationMs: 42,
    );

    test('applies the response to the addressed tab', () async {
      await loadWith([tab('a')]);
      stubSend(() async => response);

      bloc.add(const SendRequest(tabId: 'a'));
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<TabsState>(
            (s) =>
                !s.tabs.single.isSending && s.tabs.single.response == response,
          ),
        ),
      );
    });

    test('targets the tab by id even when another tab is active', () async {
      await loadWith([tab('a'), tab('b')]);
      bloc.add(const SetActiveIndex(1));
      stubSend(() async => response);

      bloc.add(const SendRequest(tabId: 'a'));
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<TabsState>(
            (s) =>
                s.tabs.byId('a')?.response == response &&
                s.tabs.byId('b')?.response == null,
          ),
        ),
      );
    });

    test(
      'a cancelled request clears isSending without recording a response',
      () async {
        await loadWith([tab('a')]);
        stubSend(
          () async => throw const NetworkFailure(
            'cancelled',
            type: NetworkFailureType.cancelled,
          ),
        );

        bloc.add(const SendRequest(tabId: 'a'));
        await expectLater(
          bloc.stream,
          emitsThrough(
            predicate<TabsState>(
              (s) => !s.tabs.single.isSending && s.tabs.single.response == null,
            ),
          ),
        );
      },
    );

    test(
      'a network failure materializes as an error response on the tab',
      () async {
        await loadWith([tab('a')]);
        stubSend(
          () async => throw const NetworkFailure(
            'connection refused',
            type: NetworkFailureType.connection,
          ),
        );

        bloc.add(const SendRequest(tabId: 'a'));
        await expectLater(
          bloc.stream,
          emitsThrough(
            predicate<TabsState>((s) {
              final r = s.tabs.single.response;
              return !s.tabs.single.isSending &&
                  r != null &&
                  r.statusCode == 0 &&
                  r.body == 'connection refused';
            }),
          ),
        );
      },
    );

    test(
      'resets isSending when the use case throws a non-NetworkFailure error',
      () async {
        await loadWith([]);
        final tabId = bloc.state.tabs.single.tabId;
        when(
          () => sendRequestUseCase.call(
            config: any(named: 'config'),
            envVars: any(named: 'envVars'),
            cancelHandle: any(named: 'cancelHandle'),
          ),
        ).thenThrow(StateError('boom'));

        bloc.add(SendRequest(tabId: tabId));
        await expectLater(
          bloc.stream,
          emitsThrough(
            predicate<TabsState>(
              (s) => s.tabs.single.tabId == tabId && !s.tabs.single.isSending,
            ),
          ),
        );
      },
    );
  });

  group('post-response rules', () {
    test(
      'runs extraction + assertions after a send and stashes results',
      () async {
        final rules = MockGetRequestRulesUseCase();
        when(() => rules.call('t1')).thenAnswer(
          (_) async => const RequestRulesEntity(
            configId: 't1',
            extractionRules: [
              ExtractionRule(
                id: 'e1',
                expression: 'token',
                targetVariable: 'tok',
              ),
            ],
            assertions: [
              Assertion(id: 'a1', expected: '200'),
            ],
          ),
        );
        final ruleBloc = TabsBloc(
          repository: repository,
          sendRequestUseCase: sendRequestUseCase,
          getRequestRulesUseCase: rules,
        );
        addTearDown(ruleBloc.close);

        when(() => repository.getTabs()).thenAnswer((_) async => [tab('t1')]);
        ruleBloc.add(const LoadTabs());
        await ruleBloc.stream.firstWhere(
          (s) => !s.isLoading && s.tabs.isNotEmpty,
        );

        stubSend(
          () async => const HttpResponseEntity(
            statusCode: 200,
            body: '{"token":"abc"}',
            headers: {},
            durationMs: 5,
          ),
        );
        ruleBloc.add(const SendRequest(tabId: 't1'));
        await ruleBloc.stream.firstWhere(
          (s) => s.tabs.byId('t1')?.assertionResults.isNotEmpty ?? false,
        );

        final tabState = ruleBloc.state.tabs.byId('t1')!;
        expect(tabState.assertionResults.single.passed, isTrue);
        expect(tabState.extractionResults.single.variable, 'tok');
        expect(tabState.extractionResults.single.value, 'abc');
      },
    );

    test(
      'large bodies run rules off the isolate (compute) and still land',
      () async {
        final rules = MockGetRequestRulesUseCase();
        when(() => rules.call('t1')).thenAnswer(
          (_) async => const RequestRulesEntity(
            configId: 't1',
            extractionRules: [
              ExtractionRule(
                id: 'e1',
                expression: 'token',
                targetVariable: 'tok',
              ),
            ],
            assertions: [
              Assertion(id: 'a1', expected: '200'),
            ],
          ),
        );
        final ruleBloc = TabsBloc(
          repository: repository,
          sendRequestUseCase: sendRequestUseCase,
          getRequestRulesUseCase: rules,
        );
        addTearDown(ruleBloc.close);

        when(() => repository.getTabs()).thenAnswer((_) async => [tab('t1')]);
        ruleBloc.add(const LoadTabs());
        await ruleBloc.stream.firstWhere(
          (s) => !s.isLoading && s.tabs.isNotEmpty,
        );

        // > 64 KiB body so _applyRules takes the compute() branch.
        final pad = 'x' * (70 * 1024);
        stubSend(
          () async => HttpResponseEntity(
            statusCode: 200,
            body: '{"token":"abc","pad":"$pad"}',
            headers: const {},
            durationMs: 5,
          ),
        );
        ruleBloc.add(const SendRequest(tabId: 't1'));
        await ruleBloc.stream.firstWhere(
          (s) => s.tabs.byId('t1')?.assertionResults.isNotEmpty ?? false,
        );

        final tabState = ruleBloc.state.tabs.byId('t1')!;
        expect(tabState.assertionResults.single.passed, isTrue);
        expect(tabState.extractionResults.single.value, 'abc');
      },
    );
  });
}
