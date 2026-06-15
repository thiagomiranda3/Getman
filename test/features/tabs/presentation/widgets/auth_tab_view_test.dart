// Widget tests for AuthTabView: scheme selection reveals the right fields and
// edits round-trip into the tab's config.auth map. Uses a real TabsBloc fed by
// a mocked repository + use case (same pattern as response_section_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/auth_tab_view.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsRepository extends Mock implements TabsRepository {}

class MockSendRequestUseCase extends Mock implements SendRequestUseCase {}

class _FakeConfig extends Fake implements HttpRequestConfigEntity {}

Future<TabsBloc> _loadedBloc(
  MockTabsRepository repository,
  MockSendRequestUseCase useCase,
  HttpRequestTabEntity tab,
) async {
  when(() => repository.getTabs()).thenAnswer((_) async => [tab]);
  final bloc = TabsBloc(repository: repository, sendRequestUseCase: useCase)
    ..add(const LoadTabs());
  await bloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
  return bloc;
}

Future<void> _pump(WidgetTester tester, TabsBloc bloc, String tabId) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: Scaffold(
        body: BlocProvider.value(
          value: bloc,
          child: AuthTabView(tabId: tabId),
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
  });

  HttpRequestTabEntity tabWithAuth(String tabId, Map<String, String> auth) =>
      HttpRequestTabEntity(
        tabId: tabId,
        config: HttpRequestConfigEntity(id: tabId, auth: auth),
      );

  testWidgets('defaults to NO AUTH with no credential fields', (tester) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tabWithAuth('t', const {}),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc, 't');

    expect(find.text('NO AUTH'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('selecting Bearer reveals the token field and edits round-trip', (
    tester,
  ) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tabWithAuth('t', const {}),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc, 't');

    // Open the type dropdown and pick Bearer.
    await tester.tap(find.text('NO AUTH'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BEARER TOKEN').last);
    await tester.pumpAndSettle();

    // Token field is now present.
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'sk-123');
    await tester.pump();

    expect(
      bloc.state.tabs.byId('t')!.config.auth,
      {'type': 'bearer', 'token': 'sk-123'},
    );

    // Let the bloc's 10s debounced-save timer fire so no timer is pending
    // when the widget tree is torn down.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('renders an existing bearer token prefilled', (tester) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tabWithAuth('t', const {'type': 'bearer', 'token': 'preset'}),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc, 't');

    expect(find.text('BEARER TOKEN'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'preset'), findsOneWidget);
  });

  testWidgets('api key in query mode round-trips addTo=query', (tester) async {
    final bloc = await _loadedBloc(
      repository,
      sendRequestUseCase,
      tabWithAuth('t', const {}),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc, 't');

    await tester.tap(find.text('NO AUTH'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('API KEY').last);
    await tester.pumpAndSettle();

    // KEY + VALUE fields present.
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).at(0), 'api_key');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'v');
    await tester.pump();

    // Switch ADD TO -> QUERY PARAM.
    await tester.tap(find.text('HEADER'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QUERY PARAM').last);
    await tester.pumpAndSettle();

    expect(
      bloc.state.tabs.byId('t')!.config.auth,
      {'type': 'apikey', 'key': 'api_key', 'value': 'v', 'addTo': 'query'},
    );

    await tester.pump(const Duration(seconds: 11));
  });
}
