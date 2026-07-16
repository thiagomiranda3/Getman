import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/environment_resolver.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';

/// CONNECT / DISCONNECT button for MCP requests, driven by the MCP connection
/// status for this tab. Resolves `{{var}}` in the endpoint URL + headers at
/// press time (the URL bar does not rebuild on URL edits, so read the live
/// config from TabsBloc).
class McpConnectButton extends StatelessWidget {
  const McpConnectButton({
    required this.tabId,
    required this.config,
    required this.isNarrow,
    required this.activeVars,
    super.key,
  });
  final String tabId;
  final HttpRequestConfigEntity config;
  final bool isNarrow;
  // A provider, not a snapshot: the URL bar's buildWhen never fires on
  // environment changes, so a captured Map would resolve against whatever
  // environment was active at the last rebuild, not the one active at press
  // time. Call this inside onPressed only.
  final Map<String, String> Function() activeVars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return BlocBuilder<McpBloc, McpState>(
      buildWhen: (p, n) =>
          p.sessionFor(tabId).status != n.sessionFor(tabId).status,
      builder: (context, mcp) {
        final status = mcp.sessionFor(tabId).status;
        final connected = status == McpConnectionStatus.connected;
        final connecting = status == McpConnectionStatus.connecting;
        return context.appDecoration.wrapInteractive(
          child: ElevatedButton(
            key: const ValueKey('mcp_connect_button'),
            onPressed: connecting
                ? null
                : () {
                    final bloc = context.read<McpBloc>();
                    if (connected) {
                      bloc.add(McpDisconnectRequested(tabId));
                      return;
                    }
                    final current =
                        context
                            .read<TabsBloc>()
                            .state
                            .tabs
                            .byId(tabId)
                            ?.config ??
                        config;
                    final vars = activeVars();
                    bloc.add(
                      McpConnectRequested(
                        tabId: tabId,
                        // Trim: a stray trailing space/newline in the URL would
                        // be percent-encoded into the path and 404 the server.
                        url: EnvironmentResolver.resolve(
                          current.url,
                          vars,
                        ).trim(),
                        headers: EnvironmentResolver.resolveMap(
                          current.headers,
                          vars,
                        ),
                      ),
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: connected ? theme.colorScheme.error : null,
              foregroundColor: connected ? theme.colorScheme.onError : null,
              padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 12 : layout.buttonPaddingHorizontal,
                vertical: isNarrow ? 10 : layout.buttonPaddingVertical,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              connected
                  ? (isNarrow ? 'STOP' : 'DISCONNECT')
                  : (connecting ? '...' : 'CONNECT'),
              style: TextStyle(
                fontSize: layout.fontSizeTitle,
                fontWeight: context.appTypography.displayWeight,
              ),
            ),
          ),
        );
      },
    );
  }
}
