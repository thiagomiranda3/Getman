// Tears down realtime (WebSocket/SSE) and MCP sessions when their request
// tab closes. Without this, closing a connected tab left its socket open —
// and its frames streaming into bloc state — until app exit. Widget-layer
// coordinator (TabsBloc must not depend on RealtimeBloc/McpBloc), same shape
// as BranchSyncListener / ExitFlushGuard.
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// Watches [TabsBloc] for tabs disappearing (close, close-others, panel
/// close, …) and dispatches [RealtimeTabsClosed] / [McpTabsClosed] for any
/// closed tab that holds a realtime or MCP session, so live connections
/// never outlive their tab. Moves between panels keep the id present in the
/// union and are unaffected.
class TabCloseTeardownListener extends StatelessWidget {
  const TabCloseTeardownListener({required this.child, super.key});
  final Widget child;

  static Set<String> _allTabIds(TabsState state) => {
    for (final panel in state.panels)
      for (final tab in panel.tabs) tab.tabId,
  };

  @override
  Widget build(BuildContext context) {
    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) {
        final before = _allTabIds(prev);
        final after = _allTabIds(next);
        return before.any((id) => !after.contains(id));
      },
      listener: (context, state) {
        final alive = _allTabIds(state);
        final realtime = context.read<RealtimeBloc>();
        final mcp = context.read<McpBloc>();
        final closedRealtime = {
          for (final id in realtime.state.sessions.keys)
            if (!alive.contains(id)) id,
        };
        if (closedRealtime.isNotEmpty) {
          realtime.add(RealtimeTabsClosed(closedRealtime));
        }
        final closedMcp = {
          for (final id in mcp.state.sessions.keys)
            if (!alive.contains(id)) id,
        };
        if (closedMcp.isNotEmpty) {
          mcp.add(McpTabsClosed(closedMcp));
        }
      },
      child: child,
    );
  }
}
