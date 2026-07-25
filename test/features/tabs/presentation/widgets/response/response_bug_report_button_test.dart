import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
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
import 'package:getman/features/tabs/presentation/widgets/response/response_body_controls.dart';

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

class _FakeEnvironmentsBloc extends Bloc<EnvironmentsEvent, EnvironmentsState>
    implements EnvironmentsBloc {
  _FakeEnvironmentsBloc(super.initialState);
}

const _tabId = 'tab-bug-report';

HttpRequestTabEntity _tabWith({HttpResponseEntity? response}) {
  return HttpRequestTabEntity(
    tabId: _tabId,
    config: const HttpRequestConfigEntity(
      id: 'cfg-bug',
      url: 'https://{{host}}/login',
      headers: {'X-Token': 'Bearer {{token}}'},
    ),
    response: response,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required HttpRequestTabEntity tab,
}) async {
  final env = EnvironmentEntity(
    id: 'env-1',
    name: 'Prod',
    variables: const {
      'host': 'api.example.com',
      'token': 'super-secret-token',
    },
    secretKeys: const {'token'},
  );
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
          create: (_) => _FakeSettingsBloc(
            const SettingsState(
              settings: SettingsEntity(activeEnvironmentId: 'env-1'),
            ),
          ),
        ),
        BlocProvider<EnvironmentsBloc>(
          create: (_) =>
              _FakeEnvironmentsBloc(EnvironmentsState(environments: [env])),
        ),
      ],
      child: MaterialApp(
        theme: resolveTheme(kClassicThemeId)(
          Brightness.light,
          isCompact: false,
        ),
        home: Scaffold(
          body: ResponseBodyControls(
            tabId: _tabId,
            getCopyableText: () => tab.response?.body ?? '',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _mockClipboard(WidgetTester tester) {
  final clips = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clips.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return clips;
}

void main() {
  final buttonFinder = find.byKey(const ValueKey('copy_bug_report_button'));

  testWidgets('hidden while the tab has no response', (tester) async {
    await _pump(tester, tab: _tabWith());
    expect(buttonFinder, findsNothing);
  });

  testWidgets('composes the bundle with secrets masked and confirms', (
    tester,
  ) async {
    final clips = _mockClipboard(tester);
    await _pump(
      tester,
      tab: _tabWith(
        response: const HttpResponseEntity(
          statusCode: 200,
          body: '{"ok":true}',
          headers: {'content-type': 'application/json'},
          durationMs: 34,
        ),
      ),
    );

    expect(buttonFinder, findsOneWidget);
    expect(
      tester.widget<IconButton>(buttonFinder).tooltip,
      'Copy as bug report',
    );

    await tester.tap(buttonFinder);
    await tester.pump();

    expect(clips, hasLength(1));
    final report = clips.single;
    expect(report, contains('### GET https://api.example.com/login'));
    expect(report, contains('X-Token: Bearer •••'));
    expect(report, isNot(contains('super-secret-token')));
    expect(report, contains('**Response:** 200 · 34 ms · 11 B'));
    expect(report, contains('content-type: application/json'));
    expect(report, contains('{"ok":true}'));

    expect(find.text('Bug report copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
