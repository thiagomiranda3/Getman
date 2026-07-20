// CONNECT/DISCONNECT button for WebSocket/SSE tabs; activeVars is a provider
// (not a snapshot) so press-time env resolution reads the live environment
// even though the URL bar's builder doesn't rebuild on environment changes.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/environment_resolver.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';

/// CONNECT / DISCONNECT button for WebSocket & SSE requests, driven by the
/// realtime connection status for this tab.
class RealtimeButton extends StatelessWidget {
  const RealtimeButton({
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
    return BlocBuilder<RealtimeBloc, RealtimeState>(
      buildWhen: (p, n) =>
          p.sessionFor(tabId).connected != n.sessionFor(tabId).connected,
      builder: (context, rt) {
        final connected = rt.sessionFor(tabId).connected;
        return context.appDecoration.wrapInteractive(
          child: ElevatedButton(
            key: const ValueKey('realtime_connect_button'),
            onPressed: () {
              final bloc = context.read<RealtimeBloc>();
              if (connected) {
                bloc.add(Disconnect(tabId));
                return;
              }
              // Read the tab's current config at press time. The URL bar does
              // not rebuild on URL edits (perf), so the constructor-captured
              // [config] can carry a stale URL; fall back to it only if the tab
              // is gone.
              final current =
                  context.read<TabsBloc>().state.tabs.byId(tabId)?.config ??
                  config;
              final vars = activeVars();
              bloc.add(
                Connect(
                  tabId: tabId,
                  kind: current.kind,
                  url: EnvironmentResolver.resolve(current.url, vars),
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
              connected ? (isNarrow ? 'STOP' : 'DISCONNECT') : 'CONNECT',
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
