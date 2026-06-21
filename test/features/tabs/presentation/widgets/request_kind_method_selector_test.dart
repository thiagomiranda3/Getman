// Widget tests for RequestKindMethodSelector: kind/method dropdowns, dispatch
// on change. Uses a real TabsBloc with mocked repository + use case.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/request_kind_method_selector.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

class _FakePanel extends Fake implements PanelEntity {}

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

Future<void> _pump(
  WidgetTester tester,
  TabsBloc bloc,
  String tabId, {
  bool isNarrow = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            // Give the selector a wide, unconstrained space so MethodBadge
            // rows in the dropdown overlay always fit without overflow.
            width: 400,
            child: BlocProvider.value(
              value: bloc,
              child: BlocBuilder<TabsBloc, TabsState>(
                builder: (context, state) {
                  final tab = state.tabs.byId(tabId);
                  if (tab == null) return const SizedBox.shrink();
                  return RequestKindMethodSelector(
                    tab: tab,
                    isNarrow: isNarrow,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

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
  });

  testWidgets('shows HTTP kind selector and GET method badge by default', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 't1',
      config: HttpRequestConfigEntity(id: 't1'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 't1');

    expect(find.byKey(const ValueKey('request_kind_selector')), findsOneWidget);
    expect(find.byKey(const ValueKey('method_selector')), findsOneWidget);
  });

  testWidgets('switching kind to WS hides the method selector', (tester) async {
    const tab = HttpRequestTabEntity(
      tabId: 't2',
      config: HttpRequestConfigEntity(id: 't2'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 't2');

    // Open the kind dropdown.
    await tester.tap(find.byKey(const ValueKey('request_kind_selector')));
    await tester.pumpAndSettle();

    // Select WS.
    await tester.tap(find.text('WS').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('method_selector')), findsNothing);
    expect(
      bloc.state.tabs.byId('t2')!.config.kind,
      RequestKind.webSocket,
    );

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('switching HTTP method dispatches UpdateTab with new method', (
    tester,
  ) async {
    const tab = HttpRequestTabEntity(
      tabId: 't3',
      config: HttpRequestConfigEntity(id: 't3'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 't3');

    // Open the method dropdown.
    await tester.tap(find.byKey(const ValueKey('method_selector')));
    await tester.pumpAndSettle();

    // Select POST.
    await tester.tap(find.text('POST').last);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    expect(bloc.state.tabs.byId('t3')!.config.method, 'POST');

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('no overflow', (tester) async {
    const tab = HttpRequestTabEntity(
      tabId: 't4',
      config: HttpRequestConfigEntity(id: 't4'),
    );
    final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
    addTearDown(bloc.close);

    await _pump(tester, bloc, 't4');

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'no overflow when isNarrow=true and selected method is DELETE (wide badge)',
    (tester) async {
      // DELETE is the widest badge and was the overflow vector in the
      // selected-face before FittedBox was added to selectedItemBuilder.
      // isNarrow=true uses a 64 px SizedBox — the narrowest constrained width.
      const tab = HttpRequestTabEntity(
        tabId: 't5',
        config: HttpRequestConfigEntity(id: 't5', method: 'DELETE'),
      );
      final bloc = await _loadedBloc(repository, sendRequestUseCase, tab);
      addTearDown(bloc.close);

      await _pump(tester, bloc, 't5', isNarrow: true);

      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 11));
    },
  );
}
