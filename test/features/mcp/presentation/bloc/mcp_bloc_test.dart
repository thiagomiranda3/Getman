import 'dart:async';

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
    're-tapping the already-selected tool keeps the displayed result',
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
      expect(
        s.lastResult?.textBlocks,
        ['prior'],
        reason:
            'the old always-replace copyWith silently wiped the result pane '
            'on every McpToolSelected — a same-tool re-tap must keep it',
      );
      expect(s.selectedTool, 'add');
    },
  );

  blocTest<McpBloc, McpState>(
    'selecting a DIFFERENT tool clears the previous tool result and error',
    // Deliberate design decision (not a limitation): lastResult/errorMessage
    // describe the previously selected tool's call, and keeping them under a
    // different tool's argument form would misattribute the output — see
    // _onToolSelected's comment in mcp_bloc.dart.
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
      b.add(const McpToolSelected(tabId: 't1', toolName: 'sub'));
    },
    verify: (b) {
      final s = b.state.sessionFor('t1');
      expect(s.lastResult, isNull);
      expect(s.errorMessage, isNull);
      expect(s.selectedTool, 'sub');
    },
  );

  blocTest<McpBloc, McpState>(
    'McpTabsClosed closes the connection and drops the session entry',
    build: () {
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => conn);
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(const McpTabsClosed({'t1'}));
    },
    verify: (b) {
      verify(() => conn.close()).called(1);
      expect(
        b.state.sessions.containsKey('t1'),
        isFalse,
        reason:
            'a closed tab has nothing left to show a session for — the '
            'entry is dropped entirely, not reset to disconnected',
      );
    },
  );

  blocTest<McpBloc, McpState>(
    'McpTabsClosed for an id with no session emits nothing',
    build: () {
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => conn);
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(const McpTabsClosed({'ghost'}));
    },
    skip: 2, // the connect's connecting + connected emissions
    expect: () => const <McpState>[],
    verify: (b) {
      // t1's live connection is untouched by the ghost close (bloc.close()
      // tears it down later, so conn.close() can't be verifyNever'd here).
      expect(b.state.sessions.keys.toList(), ['t1']);
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

  late Completer<McpToolResult> callCompleter;
  late Completer<void> closeCompleter;

  blocTest<McpBloc, McpState>(
    'McpTabsClosed does not clobber a tool result landing during teardown',
    build: () {
      callCompleter = Completer<McpToolResult>();
      closeCompleter = Completer<void>();
      final conn2 = _MockConnection();
      when(() => conn2.session).thenReturn(session);
      when(conn2.listTools).thenAnswer((_) async => [tool]);
      when(conn2.close).thenAnswer((_) => closeCompleter.future);
      var calls = 0;
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => calls++ == 0 ? conn : conn2);
      when(
        () =>
            conn.callTool(any(), any(), cancelToken: any(named: 'cancelToken')),
      ).thenAnswer((_) => callCompleter.future);
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(const McpConnectRequested(tabId: 't2', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(
        const McpToolCallRequested(tabId: 't1', toolName: 'add', arguments: {}),
      );
      await Future<void>.delayed(Duration.zero);
      // t2's teardown suspends inside conn2.close() …
      b.add(const McpTabsClosed({'t2'}));
      await Future<void>.delayed(Duration.zero);
      // … while t1's in-flight call completes and emits its result …
      callCompleter.complete(
        const McpToolResult(isError: false, textBlocks: ['42'], rawBlocks: []),
      );
      await Future<void>.delayed(Duration.zero);
      // … then the teardown resumes and folds the closed tab out.
      closeCompleter.complete();
      await Future<void>.delayed(Duration.zero);
    },
    verify: (b) {
      final s = b.state.sessionFor('t1');
      expect(
        s.calling,
        isFalse,
        reason:
            'the TabsClosed fold must derive from live state — a pre-teardown '
            'snapshot resurrects the in-flight call state it clobbers',
      );
      expect(s.lastResult?.textBlocks, ['42']);
      expect(b.state.sessions.containsKey('t2'), isFalse);
    },
  );

  blocTest<McpBloc, McpState>(
    'a tool call resolving after its tab closed does not resurrect the '
    'session',
    build: () {
      callCompleter = Completer<McpToolResult>();
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => conn);
      when(
        () =>
            conn.callTool(any(), any(), cancelToken: any(named: 'cancelToken')),
      ).thenAnswer((_) => callCompleter.future);
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(
        const McpToolCallRequested(tabId: 't1', toolName: 'add', arguments: {}),
      );
      await Future<void>.delayed(Duration.zero);
      b.add(const McpTabsClosed({'t1'}));
      await Future<void>.delayed(Duration.zero);
      callCompleter.complete(
        const McpToolResult(isError: false, textBlocks: ['42'], rawBlocks: []),
      );
      await Future<void>.delayed(Duration.zero);
    },
    verify: (b) {
      expect(
        b.state.sessions.containsKey('t1'),
        isFalse,
        reason:
            'a call completing after McpTabsClosed tore the connection down '
            'must not write a phantom session for the dead tab',
      );
    },
  );

  blocTest<McpBloc, McpState>(
    'a tool call failing after a disconnect does not overwrite the reset',
    build: () {
      callCompleter = Completer<McpToolResult>();
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => conn);
      when(
        () =>
            conn.callTool(any(), any(), cancelToken: any(named: 'cancelToken')),
      ).thenAnswer((_) => callCompleter.future);
      return McpBloc(service: service);
    },
    act: (b) async {
      b.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero);
      b.add(
        const McpToolCallRequested(tabId: 't1', toolName: 'add', arguments: {}),
      );
      await Future<void>.delayed(Duration.zero);
      b.add(const McpDisconnectRequested('t1'));
      await Future<void>.delayed(Duration.zero);
      callCompleter.completeError(McpException('late boom'));
      await Future<void>.delayed(Duration.zero);
    },
    verify: (b) {
      final s = b.state.sessionFor('t1');
      expect(s.status, McpConnectionStatus.disconnected);
      expect(
        s.errorMessage,
        isNull,
        reason:
            'the deliberate disconnect reset must not be overwritten by a '
            'stale in-flight call failing afterwards',
      );
      expect(s.log, isEmpty);
      expect(s.calling, isFalse);
    },
  );

  test(
    'close() survives a connect resuming mid-teardown '
    '(no concurrent map mutation)',
    () async {
      final closeGate = Completer<void>();
      final connectGate = Completer<McpConnection>();
      final conn2 = _MockConnection();
      when(() => conn2.session).thenReturn(session);
      when(conn2.listTools).thenAnswer((_) async => [tool]);
      when(conn2.close).thenAnswer((_) async {});
      when(() => conn.close()).thenAnswer((_) => closeGate.future);
      var calls = 0;
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) => calls++ == 0 ? Future.value(conn) : connectGate.future,
      );

      final bloc = McpBloc(service: service)
        ..add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero); // t1 holds a live connection
      bloc.add(const McpConnectRequested(tabId: 't2', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero); // t2 suspended in connect()

      final closing = bloc.close(); // suspends awaiting conn.close()
      await Future<void>.delayed(Duration.zero);
      connectGate.complete(conn2); // _onConnect resumes and touches the map
      await Future<void>.delayed(Duration.zero);
      closeGate.complete();

      await closing; // without the snapshot: ConcurrentModificationError
      expect(bloc.isClosed, isTrue);
    },
  );

  test(
    'a connect resolving after close() closes the connection instead of '
    'leaking it',
    () async {
      final connectGate = Completer<McpConnection>();
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) => connectGate.future);

      final bloc = McpBloc(service: service)
        ..add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero); // suspended in connect()

      final closing = bloc.close();
      connectGate.complete(conn);
      await closing;

      verify(() => conn.close()).called(1);
    },
  );

  test(
    'a connect resolving after McpTabsClosed closed the TAB neither emits a '
    'ghost session nor leaks the connection',
    () async {
      // The old guard was isClosed-only: it covered bloc close but not the
      // tab closing while the handshake was in flight — the handler then
      // stored the connection and emitted a session for a dead tab.
      final connectGate = Completer<McpConnection>();
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) => connectGate.future);

      final bloc = McpBloc(service: service)
        ..add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero); // suspended in connect()
      bloc.add(const McpTabsClosed({'t1'}));
      await Future<void>.delayed(Duration.zero); // tab torn down + folded out
      connectGate.complete(conn);
      await Future<void>.delayed(Duration.zero); // stale connect resumes

      expect(
        bloc.state.sessions.containsKey('t1'),
        isFalse,
        reason:
            'the in-flight connect resuming after its tab closed must bail, '
            'not resurrect a session for the dead tab',
      );
      verify(() => conn.close()).called(1);
      await bloc.close();
    },
  );

  test(
    'a second connect during the first handshake wins — the slower first '
    'connect closes its connection instead of overwriting',
    () async {
      final gate1 = Completer<McpConnection>();
      final conn2 = _MockConnection();
      when(() => conn2.session).thenReturn(session);
      when(conn2.listTools).thenAnswer((_) async => [tool]);
      when(conn2.close).thenAnswer((_) async {});
      when(
        () => conn2.callTool(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => const McpToolResult(
          isError: false,
          textBlocks: ['42'],
          rawBlocks: [],
        ),
      );
      var calls = 0;
      when(
        () => service.connect(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) => calls++ == 0 ? gate1.future : Future.value(conn2),
      );

      final bloc = McpBloc(service: service)
        ..add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero); // #1 suspended in connect()
      bloc.add(const McpConnectRequested(tabId: 't1', url: 'https://mcp.dev/'));
      await Future<void>.delayed(Duration.zero); // #2 connected via conn2
      gate1.complete(conn);
      await Future<void>.delayed(Duration.zero); // #1 resumes, must bail

      expect(bloc.state.sessionFor('t1').status, McpConnectionStatus.connected);
      verify(
        () => conn.close(),
        // #1's connection was never stored, so bailing must close it.
      ).called(1);
      verifyNever(conn2.close);
      // conn2 is the live connection: tool calls route to it.
      bloc.add(
        const McpToolCallRequested(tabId: 't1', toolName: 'add', arguments: {}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.sessionFor('t1').lastResult?.textBlocks, ['42']);
      await bloc.close();
    },
  );
}
