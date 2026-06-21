// Widget tests for EmptyTabsPlaceholder: renders the exact copy and
// "NEW REQUEST" button dispatches AddTab.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/home/presentation/widgets/empty_tabs_placeholder.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

Widget _host(TabsBloc bloc) {
  return MaterialApp(
    theme: brutalistTheme(Brightness.light),
    home: Scaffold(
      body: BlocProvider<TabsBloc>.value(
        value: bloc,
        child: const EmptyTabsPlaceholder(),
      ),
    ),
  );
}

void main() {
  setUpAll(() => registerFallbackValue(_FakeTabsEvent()));

  late MockTabsBloc bloc;

  setUp(() {
    bloc = MockTabsBloc();
    when(() => bloc.state).thenReturn(const TabsState());
  });

  testWidgets('renders NO OPEN TABS headline', (tester) async {
    await tester.pumpWidget(_host(bloc));
    expect(find.text('NO OPEN TABS'), findsOneWidget);
  });

  testWidgets('renders the keyboard hint', (tester) async {
    await tester.pumpWidget(_host(bloc));
    expect(find.text('PRESS CTRL+N TO CREATE A NEW REQUEST'), findsOneWidget);
  });

  testWidgets('NEW REQUEST button dispatches AddTab', (tester) async {
    await tester.pumpWidget(_host(bloc));

    await tester.tap(find.text('NEW REQUEST'));
    await tester.pump(const Duration(milliseconds: 50));

    verify(() => bloc.add(any(that: isA<AddTab>()))).called(1);
  });
}
