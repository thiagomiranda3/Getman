import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
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

void main() {
  const tabId = 'tab-1';

  HttpRequestTabEntity tabWith({HttpResponseEntity? response, String? nodeId}) {
    return HttpRequestTabEntity(
      tabId: tabId,
      config: const HttpRequestConfigEntity(
        id: 'cfg',
        url: 'https://api.example.com/users',
      ),
      response: response,
      collectionNodeId: nodeId,
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required HttpRequestTabEntity tab,
    required SettingsState settings,
    HistoryState history = const HistoryState(),
    CollectionsState? collections,
  }) async {
    final controller = CodeLineEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>(
            create: (_) => _FakeTabsBloc(TabsState(tabs: [tab])),
          ),
          BlocProvider<CollectionsBloc>(
            create: (_) =>
                _FakeCollectionsBloc(collections ?? CollectionsState()),
          ),
          BlocProvider<HistoryBloc>(
            create: (_) => _FakeHistoryBloc(history),
          ),
          BlocProvider<SettingsBloc>(
            create: (_) => _FakeSettingsBloc(settings),
          ),
        ],
        child: MaterialApp(
          theme: resolveTheme(kBrutalistThemeId)(
            Brightness.light,
            isCompact: false,
          ),
          home: Scaffold(
            body: ResponseBodyView(
              tabId: tabId,
              responseController: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const defaultSettings = SettingsState(settings: SettingsEntity());

  testWidgets('compare button hidden when no response', (tester) async {
    await pump(tester, tab: tabWith(), settings: defaultSettings);
    expect(find.byKey(const ValueKey('compare_response_button')), findsNothing);
  });

  testWidgets('compare button disabled when a response but no targets', (
    tester,
  ) async {
    await pump(
      tester,
      tab: tabWith(
        response: const HttpResponseEntity(
          statusCode: 200,
          body: '{"a":1}',
          headers: {},
          durationMs: 5,
        ),
      ),
      settings: defaultSettings,
    );
    final btn = tester.widget<IconButton>(
      find.byKey(const ValueKey('compare_response_button')),
    );
    expect(btn.onPressed, isNull, reason: 'no targets -> disabled');
  });

  testWidgets('compare button enabled + opens picker with a history match', (
    tester,
  ) async {
    await pump(
      tester,
      tab: tabWith(
        response: const HttpResponseEntity(
          statusCode: 200,
          body: '{"a":1}',
          headers: {},
          durationMs: 5,
        ),
      ),
      history: const HistoryState(
        history: [
          HttpRequestConfigEntity(
            id: 'h1',
            url: 'https://api.example.com/users',
            statusCode: 200,
            responseBody: '{"a":2}',
            responseHeaders: {},
            durationMs: 9,
          ),
        ],
      ),
      settings: defaultSettings,
    );
    await tester.tap(find.byKey(const ValueKey('compare_response_button')));
    await tester.pumpAndSettle();
    expect(find.text('COMPARE WITH'), findsOneWidget);
  });

  testWidgets('existing Copy/Save buttons still present', (tester) async {
    await pump(
      tester,
      tab: tabWith(
        response: const HttpResponseEntity(
          statusCode: 200,
          body: '{"a":1}',
          headers: {},
          durationMs: 5,
        ),
      ),
      settings: defaultSettings,
    );
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.byTooltip('Save response to file'), findsOneWidget);
  });
}
