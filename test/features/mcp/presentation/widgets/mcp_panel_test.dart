// Widget tests for McpPanel: disconnected hint, tool list + no overflow,
// and session log expansion.
// Fixtures verified against the real entity/state signatures in mcp_state.dart,
// mcp_tool.dart, and mcp_tool_result.dart.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:getman/features/mcp/presentation/widgets/mcp_panel.dart';
import 'package:mocktail/mocktail.dart';

class _MockMcpBloc extends MockBloc<McpEvent, McpState> implements McpBloc {}

void main() {
  late _MockMcpBloc mcp;

  setUp(() => mcp = _MockMcpBloc());

  Widget harness(McpState state) {
    when(() => mcp.state).thenReturn(state);
    when(() => mcp.stream).thenAnswer((_) => const Stream.empty());
    return MaterialApp(
      // resolveTheme returns AppThemeBuilder = ThemeData Function(Brightness,
      // {bool isCompact, bool reduceEffects}); named args, so no second
      // positional arg.
      theme: resolveTheme('classic')(Brightness.light),
      home: Scaffold(
        body: BlocProvider<McpBloc>.value(
          value: mcp,
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
    expect(find.textContaining('result text'), findsWidgets);
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
