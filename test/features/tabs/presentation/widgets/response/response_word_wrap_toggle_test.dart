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
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_body_view.dart';
import 'package:re_editor/re_editor.dart';

// Lightweight fake blocs that only expose `state`.
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

const _tabId = 'tab-wrap';

HttpRequestTabEntity _tabWith(String body) => HttpRequestTabEntity(
  tabId: _tabId,
  config: const HttpRequestConfigEntity(
    id: 'cfg-wrap',
    url: 'https://api.example.com/data',
  ),
  response: HttpResponseEntity(
    statusCode: 200,
    body: body,
    headers: const {},
    durationMs: 10,
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required String body,
  SettingsEntity settings = const SettingsEntity(),
}) async {
  final controller = CodeLineEditingController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TabsBloc>(
          create: (_) => _FakeTabsBloc(TabsState(tabs: [_tabWith(body)])),
        ),
        BlocProvider<CollectionsBloc>(
          create: (_) => _FakeCollectionsBloc(CollectionsState()),
        ),
        BlocProvider<HistoryBloc>(
          create: (_) => _FakeHistoryBloc(const HistoryState()),
        ),
        BlocProvider<SettingsBloc>(
          create: (_) => _FakeSettingsBloc(SettingsState(settings: settings)),
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
  // _syncBody uses compute() (via JsonUtils.prettify) which spawns an isolate.
  // runAsync lets real async I/O complete; pumpAndSettle flushes the resulting
  // setState calls (same pattern as response_body_view_lazy_tree_test.dart).
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

bool _editorWrap(WidgetTester tester) =>
    tester.widget<JsonCodeEditor>(find.byType(JsonCodeEditor)).wordWrap;

void main() {
  final toggleFinder = find.byKey(const ValueKey('word_wrap_toggle_button'));

  testWidgets('normal response defaults to wrap ON; toggle flips it', (
    tester,
  ) async {
    await _pump(tester, body: '{"a":1}');
    expect(_editorWrap(tester), isTrue, reason: 'default preserved: wrap on');
    expect(toggleFinder, findsOneWidget);
    expect(
      tester.widget<IconButton>(toggleFinder).tooltip,
      'Word wrap: on',
    );

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();
    expect(_editorWrap(tester), isFalse);
    expect(
      tester.widget<IconButton>(toggleFinder).tooltip,
      'Word wrap: off',
    );

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();
    expect(_editorWrap(tester), isTrue);
  });

  testWidgets('toggle hidden in TREE mode', (tester) async {
    await _pump(tester, body: '{"a":1}');
    await tester.tap(find.byKey(const ValueKey('body_toggle_TREE')));
    await tester.pumpAndSettle();
    expect(toggleFinder, findsNothing);
  });

  testWidgets('toggle hidden in large plain-text mode', (tester) async {
    final big = 'x' * (kLargeResponseViewerChars + 1);
    await _pump(tester, body: big);
    // Large plain-text path: no editor, no wrap toggle.
    expect(find.byType(CodeEditor), findsNothing);
    expect(toggleFinder, findsNothing);
  });

  testWidgets('opted-in large defaults to wrap OFF; toggle flips it', (
    tester,
  ) async {
    // alwaysPrettifyLargeResponses opts into the editor for large bodies;
    // an all-'x' body short-circuits prettify (non-JSON) so no isolate hop.
    final big = 'x' * (kLargeResponseViewerChars + 1);
    await _pump(
      tester,
      body: big,
      settings: const SettingsEntity(alwaysPrettifyLargeResponses: true),
    );
    expect(
      _editorWrap(tester),
      isFalse,
      reason: 'default preserved: opted-in large is wrap off',
    );
    expect(toggleFinder, findsOneWidget);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();
    expect(_editorWrap(tester), isTrue);
  });
}
