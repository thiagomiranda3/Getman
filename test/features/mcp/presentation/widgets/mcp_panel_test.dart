// Widget tests for McpPanel: disconnected hint, tool list + no overflow,
// and session log expansion.
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
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:getman/features/mcp/presentation/widgets/mcp_panel.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
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

void main() {
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

  Widget harness(McpState state) {
    when(() => mcp.state).thenReturn(state);
    when(() => mcp.stream).thenAnswer((_) => const Stream.empty());
    return MaterialApp(
      // resolveTheme returns AppThemeBuilder = ThemeData Function(Brightness,
      // {bool isCompact, bool reduceEffects}); named args, so no second
      // positional arg.
      theme: resolveTheme('classic')(Brightness.light),
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
}
