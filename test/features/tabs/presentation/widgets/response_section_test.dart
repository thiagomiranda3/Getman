// Widget tests for _ResponseBodyView large-response rendering.
//
// _ResponseBodyView is not exported; we exercise it through ResponseSection
// (which wraps it) with a real TabsBloc fed by a mocked repository and use
// case — the same construction pattern as tabs_bloc_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
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

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _body(int chars) => 'x' * chars;

HttpRequestTabEntity _tabWithBody(String tabId, String body) =>
    HttpRequestTabEntity(
      tabId: tabId,
      config: HttpRequestConfigEntity(id: tabId),
      response: HttpResponseEntity(
        statusCode: 200,
        body: body,
        headers: const {},
        durationMs: 10,
      ),
    );

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Pumps a [ResponseSection] inside a fully themed [MaterialApp] with a
/// [BlocProvider<TabsBloc>] pre-loaded with [initialTabs].
///
/// Uses [runAsync] so that the compute isolate's message can land on the
/// Dart event loop while we wait for it.
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
        body: BlocProvider.value(
          value: bloc,
          child: ResponseSection(
            tabId: tabId,
            responseController: controller,
            showMetadata: false,
          ),
        ),
      ),
    ),
  );
  // Allow async _syncBody (compute round-trip) to complete.
  // runAsync lets real async IO (isolate messages) settle; pumpAndSettle
  // drains the resulting frame queue.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
}

/// Creates and loads a [TabsBloc] whose state contains [tab].
/// Uses [LoadTabs] + a mocked [repository.getTabs] — same pattern as
/// tabs_bloc_test.dart.
Future<TabsBloc> _loadedBloc(
  MockTabsRepository repository,
  MockSendRequestUseCase useCase,
  HttpRequestTabEntity tab,
) async {
  when(() => repository.getTabs()).thenAnswer((_) async => [tab]);
  final bloc = TabsBloc(repository: repository, sendRequestUseCase: useCase);
  bloc.add(const LoadTabs());
  // Wait until loading finishes.
  await bloc.stream
      .firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
  return bloc;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  late MockTabsRepository repository;
  late MockSendRequestUseCase sendRequestUseCase;

  setUpAll(() {
    registerFallbackValue(_FakeConfig());
    registerFallbackValue(const HttpRequestTabEntity(
      tabId: 'fallback',
      config: HttpRequestConfigEntity(id: 'fallback'),
    ));
  });

  setUp(() {
    repository = MockTabsRepository();
    sendRequestUseCase = MockSendRequestUseCase();
    when(() => repository.saveTabs(any())).thenAnswer((_) async {});
    when(() => repository.putTab(any())).thenAnswer((_) async {});
    when(() => repository.deleteTabs(any())).thenAnswer((_) async {});
    when(() => repository.saveTabOrder(any())).thenAnswer((_) async {});
  });

  // -------------------------------------------------------------------------
  // Test 1: Large body → banner + SelectableText, no CodeEditor
  // -------------------------------------------------------------------------
  testWidgets(
    'response over threshold shows banner and SelectableText, not CodeEditor',
    (tester) async {
      const tabId = 'tab1';
      final body = _body(kLargeResponseViewerChars + 1);
      final tab = _tabWithBody(tabId, body);
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);

      await _pump(tester, bloc: bloc, tabId: tabId, controller: controller);

      // Banner must be present.
      expect(find.textContaining('LARGE RESPONSE'), findsOneWidget);
      expect(find.textContaining('HIGHLIGHTING DISABLED'), findsOneWidget);

      // Plain SelectableText must be present.
      expect(find.byType(SelectableText), findsOneWidget);

      // The re_editor CodeEditor must NOT be present.
      expect(find.byType(CodeEditor), findsNothing);
    },
  );

  // -------------------------------------------------------------------------
  // Test 2: Body over preview limit is truncated; SHOW FULL reveals the rest
  // -------------------------------------------------------------------------
  testWidgets(
    'body over preview limit is truncated until SHOW FULL is tapped',
    (tester) async {
      const tabId = 'tab2';
      // Exceed both thresholds: body > viewer threshold, and body > preview limit.
      final body = _body(kLargeResponseViewerChars + 1024);
      final tab = _tabWithBody(tabId, body);
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);

      await _pump(tester, bloc: bloc, tabId: tabId, controller: controller);

      // Before SHOW FULL: truncated text is rendered.
      final selectableTextBefore =
          tester.widget<SelectableText>(find.byType(SelectableText));
      expect(
        selectableTextBefore.data!.length,
        lessThanOrEqualTo(kLargeResponsePreviewChars),
      );

      // SHOW FULL button must be present.
      expect(find.text('SHOW FULL'), findsOneWidget);

      // Tap SHOW FULL.
      await tester.tap(find.text('SHOW FULL'));
      await tester.pumpAndSettle();

      // After SHOW FULL: full body length is rendered.
      final selectableTextAfter =
          tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectableTextAfter.data!.length, equals(body.length));

      // SHOW FULL button gone after full body is shown.
      expect(find.text('SHOW FULL'), findsNothing);
    },
  );

  // -------------------------------------------------------------------------
  // Test 3: PRETTIFY ANYWAY switches to editor path (CodeEditor appears)
  // -------------------------------------------------------------------------
  testWidgets(
    'tapping PRETTIFY ANYWAY shows the CodeEditor',
    (tester) async {
      const tabId = 'tab3';
      final body = _body(kLargeResponseViewerChars + 1);
      final tab = _tabWithBody(tabId, body);
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);

      await _pump(tester, bloc: bloc, tabId: tabId, controller: controller);

      // Sanity: we start in large mode.
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byType(CodeEditor), findsNothing);

      // Tap PRETTIFY ANYWAY.
      expect(find.text('PRETTIFY ANYWAY'), findsOneWidget);
      await tester.tap(find.text('PRETTIFY ANYWAY'));
      // runAsync lets the compute isolate message land before we pump frames.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();

      // After opt-in: CodeEditor should be visible.
      expect(find.byType(CodeEditor), findsOneWidget);

      // SelectableText should be gone.
      expect(find.byType(SelectableText), findsNothing);
    },
  );

  // -------------------------------------------------------------------------
  // Test 4: Small response renders the editor directly (no banner)
  // -------------------------------------------------------------------------
  testWidgets(
    'small response renders CodeEditor directly with no large-mode banner',
    (tester) async {
      const tabId = 'tab4';
      const body = '{"ok": true}';
      final tab = _tabWithBody(tabId, body);
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);

      await _pump(tester, bloc: bloc, tabId: tabId, controller: controller);

      // CodeEditor must be present.
      expect(find.byType(CodeEditor), findsOneWidget);

      // No banner, no SelectableText.
      expect(find.textContaining('LARGE RESPONSE'), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
    },
  );

  // -------------------------------------------------------------------------
  // Test 5: small response exposes the Pretty/Raw toggle and stays an editor
  // -------------------------------------------------------------------------
  testWidgets('small response shows the Pretty/Raw toggle', (tester) async {
    const tabId = 'tab5';
    final tab = _tabWithBody(tabId, '{"ok":true}');
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);
    final controller = CodeLineEditingController();
    addTearDown(controller.dispose);

    await _pump(tester, bloc: bloc, tabId: tabId, controller: controller);

    expect(find.text('PRETTY'), findsOneWidget);
    expect(find.text('RAW'), findsOneWidget);

    await tester.tap(find.text('RAW'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    // Still an editor after switching to raw.
    expect(find.byType(CodeEditor), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Test 6: COOKIES tab lists cookies parsed from the set-cookie header
  // -------------------------------------------------------------------------
  testWidgets('COOKIES tab lists parsed cookies', (tester) async {
    const tabId = 'tab6';
    const tab = HttpRequestTabEntity(
      tabId: tabId,
      config: HttpRequestConfigEntity(id: tabId),
      response: HttpResponseEntity(
        statusCode: 200,
        body: '{"ok":true}',
        headers: {'set-cookie': 'sid=abc123; Path=/; HttpOnly'},
        durationMs: 5,
      ),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);
    final controller = CodeLineEditingController();
    addTearDown(controller.dispose);

    await _pump(tester, bloc: bloc, tabId: tabId, controller: controller);

    await tester.tap(find.text('COOKIES'));
    await tester.pumpAndSettle();

    expect(find.text('sid'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Test 7: the SIZE metadata item renders when metadata is shown
  // -------------------------------------------------------------------------
  testWidgets('SIZE appears in the metadata row', (tester) async {
    const tabId = 'tab7';
    final tab = _tabWithBody(tabId, '{"ok":true}');
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);
    final controller = CodeLineEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: BlocProvider.value(
            value: bloc,
            child: ResponseSection(tabId: tabId, responseController: controller),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('SIZE: '), findsOneWidget);
  });
}
