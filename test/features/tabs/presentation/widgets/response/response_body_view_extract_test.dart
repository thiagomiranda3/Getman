import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
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
import 'package:getman/features/tabs/presentation/widgets/response/response_body_view.dart';
import 'package:re_editor/re_editor.dart';

// Lightweight fake blocs; the rules bloc records every dispatched event so
// tests can assert on the extraction rule the tree action produced.
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

class _RecordingRulesBloc extends Bloc<RulesEvent, RulesState>
    implements RulesBloc {
  _RecordingRulesBloc() : super(const RulesState()) {
    on<RulesEvent>((event, emit) => events.add(event));
  }

  final List<RulesEvent> events = [];
}

const _tabId = 'tab-extract';
const _configId = 'cfg-extract';

HttpRequestTabEntity _tabWith(String body) => HttpRequestTabEntity(
  tabId: _tabId,
  config: const HttpRequestConfigEntity(
    id: _configId,
    url: 'https://api.example.com/data',
  ),
  response: HttpResponseEntity(
    statusCode: 200,
    body: body,
    headers: const {},
    durationMs: 10,
  ),
);

/// Pumps the body view in TREE mode over [body] and returns the recording
/// rules bloc.
Future<_RecordingRulesBloc> _pumpTree(
  WidgetTester tester, {
  required String body,
}) async {
  final rulesBloc = _RecordingRulesBloc();
  addTearDown(rulesBloc.close);
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
          create: (_) => _FakeSettingsBloc(
            const SettingsState(settings: SettingsEntity()),
          ),
        ),
        BlocProvider<RulesBloc>.value(value: rulesBloc),
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
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('body_toggle_TREE')));
  await tester.pumpAndSettle();
  return rulesBloc;
}

Future<void> _extractVia(WidgetTester tester, String menuKey) async {
  await tester.tap(find.byKey(ValueKey(menuKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Extract to {{var}}'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'extracting a named field adds a JSONPath rule with the key as the '
    'suggested variable',
    (tester) async {
      final rules = await _pumpTree(tester, body: '{"user":{"id":7}}');

      await _extractVia(tester, r'tree_menu_$.user.id');

      final event = rules.events.single as AddExtractionRule;
      expect(event.configId, _configId);
      expect(event.rule.expression, r'$.user.id');
      expect(event.rule.targetVariable, 'id');
      expect(event.rule.kind, ExtractionKind.jsonPath);
      expect(
        find.text('Added extraction → {{id}} (edit in RULES)'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets('an array-index tail falls back to the `value` variable', (
    tester,
  ) async {
    final rules = await _pumpTree(tester, body: '{"items":[5]}');

    await _extractVia(tester, r'tree_menu_$.items[0]');

    final event = rules.events.single as AddExtractionRule;
    expect(event.rule.expression, r'$.items[0]');
    expect(event.rule.targetVariable, 'value');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'a bracket-quoted key is cleaned into an identifier-safe variable',
    (tester) async {
      final rules = await _pumpTree(tester, body: '{"user-name":"x"}');

      await _extractVia(tester, r'tree_menu_$["user-name"]');

      final event = rules.events.single as AddExtractionRule;
      expect(event.rule.expression, r'$["user-name"]');
      expect(event.rule.targetVariable, 'user_name');
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'a key the JSONPath grammar cannot express refuses with a snackbar '
    'and adds no rule',
    (tester) async {
      final rules = await _pumpTree(tester, body: '{"a]b":1}');

      await _extractVia(tester, r'tree_menu_$["a]b"]');

      expect(rules.events, isEmpty);
      expect(find.text('Cannot extract: unsupported path'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
