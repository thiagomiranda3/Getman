import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
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
import 'package:getman/features/tabs/presentation/widgets/response/response_body_view.dart';
import 'package:re_editor/re_editor.dart';

// Lightweight fake blocs that only expose `state` — the widget reads state via
// context.read<...>() / BlocBuilder and never dispatches events here.
class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initialState);
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

const _tabId = 'tab-lazy-tree';

HttpRequestTabEntity _tabWith(String body) => HttpRequestTabEntity(
  tabId: _tabId,
  config: const HttpRequestConfigEntity(
    id: 'cfg-lazy',
    url: 'https://api.example.com/data',
  ),
  response: HttpResponseEntity(
    statusCode: 200,
    body: body,
    headers: const {},
    durationMs: 10,
  ),
);

/// Pumps [ResponseBodyView] seeded with a tab whose response body is [body].
/// The [settings] parameter seeds [SettingsBloc] — pass a custom
/// `SettingsEntity` to parameterise (e.g. Task 6 will wire
/// `alwaysPrettifyLargeResponses` here).
///
/// Calls `tester.runAsync` + `pumpAndSettle` to let the initial `_syncBody`
/// async prettify (which uses `compute`) finish before returning.
Future<void> pumpResponseBodyView(
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
        BlocProvider<RulesBloc>(
          create: (_) => _FakeRulesBloc(),
        ),
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
  // setState calls.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'TREE is enabled for a JSON-object body and decodes on tap',
    (tester) async {
      await pumpResponseBodyView(tester, body: '{"a":1,"b":2}');

      // TREE segment is present and enabled (not wrapped in a Tooltip).
      final treeFinder = find.byKey(const ValueKey('body_toggle_TREE'));
      expect(treeFinder, findsOneWidget);
      expect(
        find.ancestor(of: treeFinder, matching: find.byType(Tooltip)),
        findsNothing,
        reason: 'enabled TREE must not be wrapped in a Tooltip',
      );

      await tester.tap(treeFinder);
      await tester.pumpAndSettle();

      // A tree row for key "a" is rendered (decode happened lazily on tap).
      expect(find.text('a'), findsOneWidget);
    },
  );

  testWidgets('non-JSON body leaves TREE disabled', (tester) async {
    await pumpResponseBodyView(tester, body: 'plain text, not json');

    // The TREE segment is wrapped in a Tooltip when disabled.
    final treeFinder = find.byKey(const ValueKey('body_toggle_TREE'));
    expect(treeFinder, findsOneWidget);
    expect(
      find.ancestor(of: treeFinder, matching: find.byType(Tooltip)),
      findsOneWidget,
      reason: 'disabled TREE must be wrapped in a Tooltip',
    );
  });
}
