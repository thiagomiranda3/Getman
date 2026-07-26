// Widget tests for McpPanel: disconnected/connecting/error hints, tool list +
// no overflow, tool selection, CALL dispatch (incl. {{var}} resolution and the
// invalid-arguments inline error), result rendering, and session log expansion.
// Fixtures verified against the real entity/state signatures in mcp_state.dart,
// mcp_tool.dart, and mcp_tool_result.dart.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:getman/features/mcp/presentation/widgets/mcp_panel.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:mocktail/mocktail.dart';

class _MockMcpBloc extends MockBloc<McpEvent, McpState> implements McpBloc {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockEnvironmentsBloc
    extends MockBloc<EnvironmentsEvent, EnvironmentsState>
    implements EnvironmentsBloc {}

class _MockCollectionsBloc extends MockBloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {}

class _MockTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {}

class _FakeMcpEvent extends Fake implements McpEvent {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeMcpEvent()));
  late _MockMcpBloc mcp;
  late _MockSettingsBloc settings;
  late _MockEnvironmentsBloc environments;
  late _MockCollectionsBloc collections;
  late _MockTabsBloc tabs;

  setUp(() {
    mcp = _MockMcpBloc();
    // The args editor's TabVariableContextBuilder reads these blocs at build.
    settings = _MockSettingsBloc();
    environments = _MockEnvironmentsBloc();
    collections = _MockCollectionsBloc();
    tabs = _MockTabsBloc();
    when(() => settings.state).thenReturn(SettingsState.initial());
    when(() => environments.state).thenReturn(const EnvironmentsState());
    when(() => collections.state).thenReturn(CollectionsState());
    when(() => tabs.state).thenReturn(const TabsState());
  });

  Widget harness(
    McpState state, {
    Brightness brightness = Brightness.light,
  }) {
    when(() => mcp.state).thenReturn(state);
    when(() => mcp.stream).thenAnswer((_) => const Stream.empty());
    return MaterialApp(
      // resolveTheme returns AppThemeBuilder = ThemeData Function(Brightness,
      // {bool isCompact, bool reduceEffects}); named args, so no second
      // positional arg.
      theme: resolveTheme('classic')(brightness),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<McpBloc>.value(value: mcp),
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<EnvironmentsBloc>.value(value: environments),
            BlocProvider<CollectionsBloc>.value(value: collections),
            BlocProvider<TabsBloc>.value(value: tabs),
          ],
          child: const SizedBox(
            width: 800,
            height: 600,
            child: McpPanel(tabId: 't1'),
          ),
        ),
      ),
    );
  }

  testWidgets('disconnected shows a hint containing CONNECT', (tester) async {
    await tester.pumpWidget(harness(const McpState()));
    expect(find.textContaining('CONNECT'), findsWidgets);
  });

  testWidgets('connected lists tools and renders without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const McpState(
          sessions: {
            't1': McpTabSession(
              status: McpConnectionStatus.connected,
              tools: [
                McpTool(name: 'add', description: 'Add', inputSchema: {}),
                McpTool(name: 'echo', description: 'Echo', inputSchema: {}),
              ],
              selectedTool: 'add',
              lastResult: McpToolResult(
                isError: false,
                textBlocks: ['result text'],
                rawBlocks: [],
              ),
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('add'), findsWidgets);
    expect(find.text('echo'), findsWidgets);
    // The result renders in a read-only JSON code editor (not plain text), so
    // assert the Result section + its editor are present.
    expect(find.text('Result'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcp_result_view')), findsOneWidget);
    expect(tester.takeException(), isNull); // no RenderFlex overflow
  });

  testWidgets(
    'connected with session log shows log entries after expansion',
    (tester) async {
      await tester.pumpWidget(
        harness(
          const McpState(
            sessions: {
              't1': McpTabSession(
                status: McpConnectionStatus.connected,
                tools: [
                  McpTool(name: 'add', description: 'Add', inputSchema: {}),
                ],
                selectedTool: 'add',
                log: ['→ initialize', '← tools/list'],
              ),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The log tile may be below the viewport — scroll it into view first.
      await tester.ensureVisible(find.text('Session log'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Session log'));
      await tester.pumpAndSettle();
      expect(find.text('→ initialize'), findsOneWidget);
      expect(tester.takeException(), isNull); // no RenderFlex overflow
    },
  );

  // A connected session with one selected tool — the base fixture for the
  // detail-pane tests below.
  const connectedWithAdd = McpState(
    sessions: {
      't1': McpTabSession(
        status: McpConnectionStatus.connected,
        tools: [
          McpTool(
            name: 'add',
            description: 'Add',
            inputSchema: {'type': 'object'},
          ),
          McpTool(name: 'echo', description: 'Echo', inputSchema: {}),
        ],
        selectedTool: 'add',
      ),
    },
  );

  /// The one editable JSON editor in the panel is the arguments editor
  /// (schema + result are read-only).
  JsonCodeEditor argsEditor(WidgetTester tester) => tester
      .widgetList<JsonCodeEditor>(find.byType(JsonCodeEditor))
      .firstWhere((e) => !e.readOnly);

  testWidgets('connecting status shows the Connecting hint', (tester) async {
    await tester.pumpWidget(
      harness(
        const McpState(
          sessions: {
            't1': McpTabSession(status: McpConnectionStatus.connecting),
          },
        ),
      ),
    );
    expect(find.text('Connecting…'), findsOneWidget);
  });

  testWidgets('error status shows the session error message', (tester) async {
    await tester.pumpWidget(
      harness(
        const McpState(
          sessions: {
            't1': McpTabSession(
              status: McpConnectionStatus.error,
              errorMessage: 'server exploded',
            ),
          },
        ),
      ),
    );
    expect(find.text('server exploded'), findsOneWidget);
  });

  testWidgets('error status without a message falls back to Connection error', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const McpState(
          sessions: {'t1': McpTabSession(status: McpConnectionStatus.error)},
        ),
      ),
    );
    expect(find.text('Connection error'), findsOneWidget);
  });

  testWidgets('connected with no selected tool prompts to select one', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const McpState(
          sessions: {
            't1': McpTabSession(
              status: McpConnectionStatus.connected,
              tools: [McpTool(name: 'add', description: '', inputSchema: {})],
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Select a tool above'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcp_call_button')), findsNothing);
  });

  testWidgets('tapping a tool chip dispatches McpToolSelected', (tester) async {
    await tester.pumpWidget(harness(connectedWithAdd));
    await tester.pumpAndSettle();

    await tester.tap(find.text('echo'));
    await tester.pump();

    verify(
      () => mcp.add(const McpToolSelected(tabId: 't1', toolName: 'echo')),
    ).called(1);
  });

  testWidgets('CALL dispatches McpToolCallRequested with resolved {{vars}}', (
    tester,
  ) async {
    // An active environment feeds the args editor's variable context, so the
    // `{{host}}` token must be substituted at CALL time.
    when(() => settings.state).thenReturn(
      const SettingsState(
        settings: SettingsEntity(activeEnvironmentId: 'e1'),
      ),
    );
    when(() => environments.state).thenReturn(
      EnvironmentsState(
        environments: [
          EnvironmentEntity(
            id: 'e1',
            name: 'Dev',
            variables: const {'host': 'example.com'},
          ),
        ],
      ),
    );

    await tester.pumpWidget(harness(connectedWithAdd));
    await tester.pumpAndSettle();

    argsEditor(tester).controller.text = '{"target": "{{host}}"}';
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('mcp_call_button')));
    await tester.tap(find.byKey(const ValueKey('mcp_call_button')));
    await tester.pump();

    verify(
      () => mcp.add(
        const McpToolCallRequested(
          tabId: 't1',
          toolName: 'add',
          arguments: {'target': 'example.com'},
        ),
      ),
    ).called(1);
    expect(find.text('Arguments must be a JSON object'), findsNothing);
  });

  testWidgets('CALL with default empty args dispatches an empty object', (
    tester,
  ) async {
    await tester.pumpWidget(harness(connectedWithAdd));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('mcp_call_button')));
    await tester.tap(find.byKey(const ValueKey('mcp_call_button')));
    await tester.pump();

    verify(
      () => mcp.add(
        const McpToolCallRequested(
          tabId: 't1',
          toolName: 'add',
          arguments: {},
        ),
      ),
    ).called(1);
  });

  testWidgets('CALL with a non-object JSON shows the inline error', (
    tester,
  ) async {
    await tester.pumpWidget(harness(connectedWithAdd));
    await tester.pumpAndSettle();

    argsEditor(tester).controller.text = '[1, 2]';
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('mcp_call_button')));
    await tester.tap(find.byKey(const ValueKey('mcp_call_button')));
    await tester.pumpAndSettle();

    expect(find.text('Arguments must be a JSON object'), findsOneWidget);
    verifyNever(() => mcp.add(any()));
  });

  testWidgets('CALL with malformed JSON shows the inline error', (
    tester,
  ) async {
    await tester.pumpWidget(harness(connectedWithAdd));
    await tester.pumpAndSettle();

    argsEditor(tester).controller.text = '{nope';
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('mcp_call_button')));
    await tester.tap(find.byKey(const ValueKey('mcp_call_button')));
    await tester.pumpAndSettle();

    expect(find.text('Arguments must be a JSON object'), findsOneWidget);
    verifyNever(() => mcp.add(any()));
  });

  testWidgets('in-flight call disables the button and shows CALLING…', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const McpState(
          sessions: {
            't1': McpTabSession(
              status: McpConnectionStatus.connected,
              tools: [McpTool(name: 'add', description: '', inputSchema: {})],
              selectedTool: 'add',
              calling: true,
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('mcp_call_button')));
    final button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('mcp_call_button')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('CALLING…'), findsOneWidget);
  });

  testWidgets('raw-block result renders the Result section', (tester) async {
    await tester.pumpWidget(
      harness(
        const McpState(
          sessions: {
            't1': McpTabSession(
              status: McpConnectionStatus.connected,
              tools: [McpTool(name: 'add', description: '', inputSchema: {})],
              selectedTool: 'add',
              lastResult: McpToolResult(
                isError: false,
                textBlocks: [],
                rawBlocks: [
                  {'answer': 42},
                ],
              ),
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcp_result_view')), findsOneWidget);
  });

  testWidgets('error result with no content shows Result (error)', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const McpState(
          sessions: {
            't1': McpTabSession(
              status: McpConnectionStatus.connected,
              tools: [McpTool(name: 'add', description: '', inputSchema: {})],
              selectedTool: 'add',
              lastResult: McpToolResult(
                isError: true,
                textBlocks: [],
                rawBlocks: [],
              ),
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Result (error)'), findsOneWidget);
  });

  testWidgets('theme brightness switch repaints without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(harness(connectedWithAdd));
    await tester.pumpAndSettle();

    // Same widget tree, new theme: didChangeDependencies must pick up the new
    // variable palette and force a token repaint without throwing.
    await tester.pumpWidget(
      harness(connectedWithAdd, brightness: Brightness.dark),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Tools (2)'), findsOneWidget);
  });
}
