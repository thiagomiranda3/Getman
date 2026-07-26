import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/domain/entities/request_rules_entity.dart';
import 'package:getman/features/chaining/domain/usecases/request_rules_usecases.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/chaining/presentation/widgets/rules_tab_view.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsBloc extends Mock implements TabsBloc {}

class MockGet extends Mock implements GetRequestRulesUseCase {}

class MockSave extends Mock implements SaveRequestRulesUseCase {}

void main() {
  late MockTabsBloc tabsBloc;
  late MockGet get;
  late MockSave save;
  late RulesBloc rulesBloc;

  setUpAll(() => registerFallbackValue(const RequestRulesEntity(configId: '')));

  setUp(() {
    tabsBloc = MockTabsBloc();
    when(() => tabsBloc.state).thenReturn(
      const TabsState(
        tabs: [
          HttpRequestTabEntity(
            tabId: 't1',
            config: HttpRequestConfigEntity(id: 't1'),
          ),
        ],
      ),
    );
    get = MockGet();
    save = MockSave();
    when(
      () => get.call('t1'),
    ).thenAnswer((_) async => const RequestRulesEntity(configId: 't1'));
    when(() => save.call(any())).thenAnswer((_) async {});
  });

  tearDown(() => rulesBloc.close());

  Future<void> pump(WidgetTester tester) async {
    // The bloc must be created INSIDE the testWidgets body (not setUp): its
    // stream subscriptions must live in the test's FakeAsync zone or LoadRules
    // emissions are never delivered while the test pumps.
    rulesBloc = RulesBloc(
      getRequestRulesUseCase: get,
      saveRequestRulesUseCase: save,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: RepositoryProvider<TabsBloc>.value(
            value: tabsBloc,
            child: BlocProvider<RulesBloc>.value(
              value: rulesBloc,
              child: const RulesTabView(tabId: 't1'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the two sections and add buttons', (tester) async {
    await pump(tester);
    expect(find.text('EXTRACT VARIABLES'), findsOneWidget);
    expect(find.text('ASSERTIONS'), findsOneWidget);
    expect(find.text('ADD ASSERTION'), findsOneWidget);
  });

  testWidgets('adding an assertion shows a row and saves', (tester) async {
    await pump(tester);

    await tester.tap(find.text('ADD ASSERTION'));
    await tester.pumpAndSettle();

    // The new assertion row renders its STATUS target dropdown + a delete icon.
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    verify(() => save.call(any())).called(1);
  });

  testWidgets('adding an extraction rule shows the kind dropdown', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('ADD EXTRACTION'));
    await tester.pumpAndSettle();

    expect(find.text('JSON PATH'), findsOneWidget);
    verify(() => save.call(any())).called(1);
  });

  // Rules already persisted for this config — exercises the BlocListener
  // load path (draft replaced by the loaded entity, rows rendered).
  const preloaded = RequestRulesEntity(
    configId: 't1',
    extractionRules: [
      ExtractionRule(id: 'x1', expression: r'$.id', targetVariable: 'uid'),
    ],
    assertions: [Assertion(id: 'a1')],
  );

  testWidgets('renders rows for rules loaded from the bloc', (tester) async {
    when(() => get.call('t1')).thenAnswer((_) async => preloaded);

    await pump(tester);

    expect(find.text(r'$.id'), findsOneWidget);
    expect(find.text('uid'), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget); // the assertion row
  });

  testWidgets('editing the extraction expression saves the updated rule', (
    tester,
  ) async {
    when(() => get.call('t1')).thenAnswer((_) async => preloaded);
    await pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('extraction_expr_0')),
      r'$.token',
    );
    await tester.pump();

    final saved =
        verify(() => save.call(captureAny())).captured.last
            as RequestRulesEntity;
    expect(saved.extractionRules.single.id, 'x1');
    expect(saved.extractionRules.single.expression, r'$.token');
    expect(saved.extractionRules.single.targetVariable, 'uid');
  });

  testWidgets('editing the assertion expected value saves it', (tester) async {
    when(() => get.call('t1')).thenAnswer((_) async => preloaded);
    await pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('assertion_expected_0')),
      '201',
    );
    await tester.pump();

    final saved =
        verify(() => save.call(captureAny())).captured.last
            as RequestRulesEntity;
    expect(saved.assertions.single.id, 'a1');
    expect(saved.assertions.single.expected, '201');
  });

  testWidgets('deleting the extraction rule removes its row and saves', (
    tester,
  ) async {
    when(() => get.call('t1')).thenAnswer((_) async => preloaded);
    await pump(tester);

    // Rows render in section order: the extraction row's delete comes first.
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('extraction_expr_0')), findsNothing);
    final saved =
        verify(() => save.call(captureAny())).captured.last
            as RequestRulesEntity;
    expect(saved.extractionRules, isEmpty);
    expect(saved.assertions, hasLength(1)); // the assertion is untouched
  });

  testWidgets('deleting the assertion removes its row and saves', (
    tester,
  ) async {
    when(() => get.call('t1')).thenAnswer((_) async => preloaded);
    await pump(tester);

    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();

    expect(find.text('STATUS'), findsNothing);
    final saved =
        verify(() => save.call(captureAny())).captured.last
            as RequestRulesEntity;
    expect(saved.assertions, isEmpty);
    expect(saved.extractionRules, hasLength(1)); // the extraction is untouched
  });
}
