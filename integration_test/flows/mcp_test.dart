import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_mcp_server.dart';

/// MCP end-to-end: switch the request kind to MCP, connect to a hermetic MCP
/// server, list its tools, select one, CALL it, see the result, then
/// disconnect. Exercises the real `McpService` dio path + `McpBloc` + the
/// `McpPanel` UI together.
///
/// The arguments editor is a `re_editor` instance (patrol_finders can't type
/// into it), so the call uses the panel's default `{}` arguments; the mock tool
/// echoes them back — enough to prove the round-trip renders a result.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolWidgetTest('connect, list tools, call a tool, then disconnect', (
    $,
  ) async {
    final server = await MockMcpServer.start();
    addTearDown(server.close);

    await bootGetman($);

    // Switch the request kind to MCP and point it at the mock server. The
    // CONNECT button reads the live config URL from TabsBloc at press time.
    await setRequestKind($, 'MCP');
    await enterUrl($, server.url);

    // CONNECT runs the initialize handshake + tools/list over real HTTP.
    await $(
      const ValueKey('mcp_connect_button'),
    ).tap(settlePolicy: SettlePolicy.noSettle);

    // Once connected, the panel lists the advertised tools.
    await $('Tools (1)').waitUntilVisible();
    expect(server.receivedMethods, contains('initialize'));
    expect(server.receivedMethods, contains('tools/list'));

    // Select the echo tool (a ChoiceChip labelled with the tool name) and let
    // the off-build schema/args sync settle.
    await $('echo').tap(settlePolicy: SettlePolicy.noSettle);
    await pumpFrames($);

    // CALL with the default `{}` arguments → the mock echoes them back.
    await $(
      const ValueKey('mcp_call_button'),
    ).tap(settlePolicy: SettlePolicy.noSettle);

    // The result header + view render once the call returns.
    await $('Result').waitUntilVisible();
    await $(const ValueKey('mcp_result_view')).waitUntilVisible();
    expect(server.receivedMethods, contains('tools/call'));

    // DISCONNECT returns the panel to the not-connected prompt.
    await $(
      const ValueKey('mcp_connect_button'),
    ).tap(settlePolicy: SettlePolicy.noSettle);
    await pumpFrames($);
    await $(find.textContaining('Not connected')).waitUntilVisible();
  });
}
