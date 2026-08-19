// TabsBloc time-travel identity + media-downgrade tests:
// - S5: with saveLargeResponsesInHistory false, a superseded history entry
//   carrying bodyBytes (media/binary — short placeholder body, up to 50 MiB
//   of bytes) is downgraded too: bytes nulled + placeholder body; the newest
//   entry always keeps its bytes and body.
// - G2: the viewed history entry is tracked by id (viewedHistoryEntryId),
//   not response value, so time-travelling between value-equal responses
//   still emits; recording a new response clears the id.
// Split out of tabs_bloc_test.dart (function_lines_of_code metric gate).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

void main() {
  late MockTabsRepository repository;
  late MockSendRequestUseCase sendRequestUseCase;
  late TabsBloc bloc;

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(_FakePanel());
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
    when(() => repository.putPanel(any())).thenAnswer((_) async {});
    when(() => repository.deletePanels(any())).thenAnswer((_) async {});
    when(() => repository.savePanelMeta(any(), any())).thenAnswer((_) async {});
    bloc = TabsBloc(
      repository: repository,
      sendRequestUseCase: sendRequestUseCase,
    );
  });

  tearDown(() => bloc.close());

  /// Seed the bloc with a single tab "a" in panel "p1" and drive a load.
  Future<void> loadTab() async {
    const seeded = HttpRequestTabEntity(
      tabId: 'a',
      config: HttpRequestConfigEntity(id: 'a', url: 'https://a.dev'),
    );
    const panel = PanelEntity(
      id: 'p1',
      name: 'Panel 1',
      tabs: [seeded],
      activeTabId: 'a',
    );
    when(() => repository.getPanels()).thenAnswer((_) async => [panel]);
    when(() => repository.getActivePanelId()).thenAnswer((_) async => 'p1');
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

  HttpResponseEntity resp(int code, String body) => HttpResponseEntity(
    statusCode: code,
    body: body,
    headers: const {},
    durationMs: code,
  );

  group('saveLargeResponsesInHistory false + bodyBytes (S5)', () {
    test(
      'a superseded bodyBytes (media) entry drops its bytes and body; the '
      'newest entry keeps them',
      () async {
        await loadTab();
        // A media response: SHORT placeholder body (never crosses the
        // large-viewer char threshold) but a byte buffer — the pre-fix
        // downgrade keyed on body.length only and never fired for these,
        // pinning one buffer per superseded entry.
        var n = 0;
        stubSend(() async {
          n++;
          return HttpResponseEntity(
            statusCode: 200,
            body: '[media body $n]',
            headers: const {'content-type': 'video/mp4'},
            durationMs: 1,
            bodyBytes: Uint8List.fromList(List<int>.filled(64, n)),
          );
        });

        bloc.add(
          const SendRequest(tabId: 'a', saveLargeResponsesInHistory: false),
        );
        await pumpEventQueue();
        expect(
          bloc.state.tabs.single.responseHistory.single.response.bodyBytes,
          isNotNull,
        );

        bloc.add(
          const SendRequest(tabId: 'a', saveLargeResponsesInHistory: false),
        );
        await pumpEventQueue();

        final t = bloc.state.tabs.single;
        expect(t.responseHistory, hasLength(2));
        // Newest entry keeps its bytes and body — it is what "Latest"
        // restores.
        expect(t.responseHistory.first.response.bodyBytes, isNotNull);
        expect(t.responseHistory.first.response.body, '[media body 2]');
        // Superseded media entry: buffer released, metadata-only placeholder.
        expect(t.responseHistory.last.response.bodyBytes, isNull);
        expect(
          t.responseHistory.last.response.body,
          kHistoryBodyNotKeptPlaceholder,
        );
      },
    );

    test(
      'saveLargeResponsesInHistory true keeps superseded media bytes',
      () async {
        await loadTab();
        var n = 0;
        stubSend(() async {
          n++;
          return HttpResponseEntity(
            statusCode: 200,
            body: '[media body $n]',
            headers: const {},
            durationMs: 1,
            bodyBytes: Uint8List.fromList(List<int>.filled(64, n)),
          );
        });

        bloc.add(const SendRequest(tabId: 'a'));
        await pumpEventQueue();
        bloc.add(const SendRequest(tabId: 'a'));
        await pumpEventQueue();

        final t = bloc.state.tabs.single;
        expect(t.responseHistory, hasLength(2));
        expect(t.responseHistory.last.response.bodyBytes, isNotNull);
        expect(t.responseHistory.last.response.body, '[media body 1]');
      },
    );
  });

  group('viewedHistoryEntryId identity tracking (G2)', () {
    test(
      'time-travel to an entry value-equal to the latest still emits — the '
      'viewed entry is tracked by id, not response value',
      () async {
        await loadTab();
        // Every send returns the SAME response value (status/body/headers/
        // duration all identical — trivial against localhost).
        stubSend(() async => resp(200, 'same'));

        bloc.add(const SendRequest(tabId: 'a'));
        await pumpEventQueue();
        bloc.add(const SendRequest(tabId: 'a'));
        await pumpEventQueue();

        final hist = bloc.state.tabs.single.responseHistory;
        expect(hist, hasLength(2));
        expect(hist[0].response, hist[1].response); // value-equal, distinct ids
        expect(bloc.state.tabs.single.viewedHistoryEntryId, isNull);

        bloc.add(ViewResponseHistoryEntry(tabId: 'a', entryId: hist[1].id));
        await pumpEventQueue();

        // Pre-fix this state was value-identical to the previous one, so the
        // emission was suppressed and the timeline stayed on "Latest". The id
        // records the pick even though the displayed response is unchanged.
        final t = bloc.state.tabs.single;
        expect(t.viewedHistoryEntryId, hist[1].id);
        expect(t.response, hist[1].response);
      },
    );

    test('recording a new response clears viewedHistoryEntryId', () async {
      await loadTab();
      var n = 0;
      stubSend(() async => resp(200, 'r${n++}'));

      bloc.add(const SendRequest(tabId: 'a'));
      await pumpEventQueue();
      bloc.add(const SendRequest(tabId: 'a'));
      await pumpEventQueue();

      final hist = bloc.state.tabs.single.responseHistory;
      bloc.add(ViewResponseHistoryEntry(tabId: 'a', entryId: hist[1].id));
      await pumpEventQueue();
      expect(bloc.state.tabs.single.viewedHistoryEntryId, hist[1].id);

      // A fresh send: the tab is viewing the latest response again.
      bloc.add(const SendRequest(tabId: 'a'));
      await pumpEventQueue();
      expect(bloc.state.tabs.single.viewedHistoryEntryId, isNull);
      expect(bloc.state.tabs.single.response?.body, 'r2');
    });
  });
}
