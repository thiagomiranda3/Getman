import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/mcp_service.dart';
import 'package:getman/features/mcp/domain/entities/mcp_session.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockService extends Mock implements McpService {}

class _MockConnection extends Mock implements McpConnection {}

void main() {
  late _MockService service;
  late _MockConnection conn;

  const tool = McpTool(name: 'add', description: 'Add', inputSchema: {});
  const session = McpSession(
    sessionId: 's1',
    protocolVersion: '2025-06-18',
    serverName: 'demo',
    serverVersion: '1',
  );

  setUp(() {
    service = _MockService();
    conn = _MockConnection();
    when(() => conn.session).thenReturn(session);
    when(() => conn.listTools()).thenAnswer((_) async => [tool]);
    when(() => conn.close()).thenAnswer((_) async {});
  });

  blocTest<McpBloc, McpState>(
    'connect → connected with tools',
    build: () {
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => conn);
      return McpBloc(service: service);
    },
    act: (b) => b.add(
      const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'),
    ),
    verify: (b) {
      final s = b.state.sessionFor('t1');
      expect(s.status, McpConnectionStatus.connected);
      expect(s.tools.single.name, 'add');
      expect(s.session?.serverName, 'demo');
    },
  );

  blocTest<McpBloc, McpState>(
    'connect failure → error status with message',
    build: () {
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenThrow(McpException('nope', code: -1));
      return McpBloc(service: service);
    },
    act: (b) => b.add(
      const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'),
    ),
    verify: (b) {
      final s = b.state.sessionFor('t1');
      expect(s.status, McpConnectionStatus.error);
      expect(s.errorMessage, contains('nope'));
    },
  );

  blocTest<McpBloc, McpState>(
    'call tool → lastResult populated',
    build: () {
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => conn);
      when(
        () =>
            conn.callTool(any(), any(), cancelToken: any(named: 'cancelToken')),
      ).thenAnswer(
        (_) async => const McpToolResult(
          isError: false,
          textBlocks: ['42'],
          rawBlocks: [],
        ),
      );
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(
        const McpToolCallRequested(
          tabId: 't1',
          toolName: 'add',
          arguments: {'a': 1, 'b': 2},
        ),
      );
    },
    verify: (b) {
      expect(b.state.sessionFor('t1').lastResult?.textBlocks, ['42']);
    },
  );

  blocTest<McpBloc, McpState>(
    'disconnect closes the connection and resets status',
    build: () {
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => conn);
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(const McpDisconnectRequested('t1'));
    },
    verify: (b) {
      expect(b.state.sessionFor('t1').status, McpConnectionStatus.disconnected);
      verify(() => conn.close()).called(1);
    },
  );

  blocTest<McpBloc, McpState>(
    'selecting a tool clears lastResult and sets selectedTool',
    build: () {
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => conn);
      when(
        () =>
            conn.callTool(any(), any(), cancelToken: any(named: 'cancelToken')),
      ).thenAnswer(
        (_) async => const McpToolResult(
          isError: false,
          textBlocks: ['prior'],
          rawBlocks: [],
        ),
      );
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(
        const McpToolCallRequested(
          tabId: 't1',
          toolName: 'add',
          arguments: {'a': 1},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      b.add(const McpToolSelected(tabId: 't1', toolName: 'add'));
    },
    verify: (b) {
      final s = b.state.sessionFor('t1');
      expect(s.lastResult, isNull);
      expect(s.selectedTool, 'add');
    },
  );

  blocTest<McpBloc, McpState>(
    'reconnecting the same tab tears down the previous connection',
    build: () {
      final conn2 = _MockConnection();
      when(() => conn2.session).thenReturn(session);
      when(conn2.listTools).thenAnswer((_) async => [tool]);
      when(conn2.close).thenAnswer((_) async {});
      var calls = 0;
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => calls++ == 0 ? conn : conn2);
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
    },
    verify: (b) {
      // The first connection is closed when the same tab reconnects.
      verify(() => conn.close()).called(1);
      expect(b.state.sessionFor('t1').status, McpConnectionStatus.connected);
    },
  );

  blocTest<McpBloc, McpState>(
    'connections are isolated per tab',
    build: () {
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => conn);
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(const McpToolSelected(tabId: 't1', toolName: 'add'));
    },
    verify: (b) {
      expect(b.state.sessionFor('t1').status, McpConnectionStatus.connected);
      expect(b.state.sessionFor('t1').selectedTool, 'add');
      // A tab that never connected keeps the default disconnected session.
      final other = b.state.sessionFor('t2');
      expect(other.status, McpConnectionStatus.disconnected);
      expect(other.tools, isEmpty);
    },
  );

  blocTest<McpBloc, McpState>(
    'a failed tool call keeps the prior result and records the error',
    build: () {
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => conn);
      var calls = 0;
      when(
        () =>
            conn.callTool(any(), any(), cancelToken: any(named: 'cancelToken')),
      ).thenAnswer((_) async {
        if (calls++ == 0) {
          return const McpToolResult(
            isError: false,
            textBlocks: ['ok'],
            rawBlocks: [],
          );
        }
        throw McpException('tool blew up');
      });
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(
        const McpToolCallRequested(tabId: 't1', toolName: 'add', arguments: {}),
      );
      await Future<void>.delayed(Duration.zero);
      b.add(
        const McpToolCallRequested(tabId: 't1', toolName: 'add', arguments: {}),
      );
    },
    verify: (b) {
      final s = b.state.sessionFor('t1');
      expect(s.calling, isFalse);
      expect(s.errorMessage, contains('tool blew up'));
      // The prior successful result is retained so the pane isn't blanked.
      expect(s.lastResult?.textBlocks, ['ok']);
    },
  );

  blocTest<McpBloc, McpState>(
    'a tool call with no live connection is a no-op',
    build: () => McpBloc(service: service),
    act: (b) => b.add(
      const McpToolCallRequested(
        tabId: 'ghost',
        toolName: 'add',
        arguments: {},
      ),
    ),
    expect: () => const <McpState>[],
    verify: (b) {
      expect(
        b.state.sessionFor('ghost').status,
        McpConnectionStatus.disconnected,
      );
    },
  );
}
