import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_event.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_state.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/code_find_panel.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_body_view.dart';
import 'package:re_editor/re_editor.dart';

// Lightweight fake blocs that only expose `state` (same pattern as
// response_body_view_lazy_tree_test.dart).
class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initialState);

  @override
  bool get canReopenClosedTab => false;
}

class _FakeCollectionsBloc extends Bloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {
  _FakeCollectionsBloc(super.initialState);
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc(super.initialState);
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc(super.initialState);
}

class _FakeRulesBloc extends Bloc<RulesEvent, RulesState> implements RulesBloc {
  _FakeRulesBloc() : super(const RulesState());
}

const _tabId = 'tab-find-button';

Future<void> _pump(WidgetTester tester, {required String body}) async {
  final tab = HttpRequestTabEntity(
    tabId: _tabId,
    config: const HttpRequestConfigEntity(
      id: 'cfg-find',
      url: 'https://api.example.com/data',
    ),
    response: HttpResponseEntity(
      statusCode: 200,
      body: body,
      headers: const {},
      durationMs: 10,
    ),
  );
  final controller = CodeLineEditingController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TabsBloc>(
          create: (_) => _FakeTabsBloc(TabsState(tabs: [tab])),
        ),
        BlocProvider<CollectionsBloc>(
          create: (_) => _FakeCollectionsBloc(CollectionsState()),
        ),
        BlocProvider<HistoryBloc>(
          create: (_) => _FakeHistoryBloc(const HistoryState()),
        ),
        BlocProvider<SettingsBloc>(
          create: (_) => _FakeSettingsBloc(SettingsState.initial()),
        ),
        BlocProvider<RulesBloc>(create: (_) => _FakeRulesBloc()),
      ],
      child: MaterialApp(
        theme: resolveTheme(kClassicThemeId)(
          Brightness.light,
          isCompact: false,
        ),
        home: Scaffold(
          body: ResponseBodyView(
            tabId: _tabId,
            responseController: controller,
          ),
        ),
      ),
    ),
  );
  // Let the initial _syncBody (compute-based prettify) finish.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('PRETTY mode: find button opens the CodeFindPanel', (
    tester,
  ) async {
    await _pump(tester, body: '{"a":1,"b":2}');

    // Panel exists but is closed (renders nothing) before the tap.
    expect(
      find.descendant(
        of: find.byType(CodeFindPanel),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('response_find_button')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(CodeFindPanel),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TREE mode: find button focuses the tree filter field', (
    tester,
  ) async {
    await _pump(tester, body: '{"a":1,"b":2}');
    await tester.tap(find.byKey(const ValueKey('body_toggle_TREE')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('response_find_button')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('tree_filter_field')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets(
    'large plain-text mode: find button opens the windowed find; close '
    'restores the normal view',
    (tester) async {
      final big = 'x' * (kLargeResponseViewerChars + 100);
      await _pump(tester, body: big);

      // Large plain-text path: SelectableText, no find bar yet.
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byKey(const ValueKey('large_find_field')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('response_find_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('large_find_field')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('large_find_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('large_find_field')), findsNothing);
      expect(find.byType(SelectableText), findsOneWidget);
    },
  );
}
