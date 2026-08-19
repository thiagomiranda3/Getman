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
/// close, …) and dispatches [RealtimeTabsClosed] / [McpTabsClosed] with
/// EVERY closed id — not just ids that already hold a session entry: a
/// realtime connect emits no session until its first frame batch, so a
/// session-keyed filter skipped exactly the tab closed while its connect was
/// still pending, and the socket then streamed into a ghost session forever.
/// The blocs no-op cheaply on unknown ids, and the dispatch bumps their
/// per-tab epochs so in-flight connects are cancelled too. Moves between
/// panels keep the id present in the union and are unaffected.
///
/// Stateful: the closed set is derived against the ids seen at the previous
/// emission (a BlocListener's callback only receives the NEW state).
class TabCloseTeardownListener extends StatefulWidget {
  const TabCloseTeardownListener({required this.child, super.key});
  final Widget child;

  @override
  State<TabCloseTeardownListener> createState() =>
      _TabCloseTeardownListenerState();
}

class _TabCloseTeardownListenerState extends State<TabCloseTeardownListener> {
  Set<String> _lastAlive = const {};
  var _seeded = false;

  static Set<String> _allTabIds(TabsState state) => {
    for (final panel in state.panels)
      for (final tab in panel.tabs) tab.tabId,
  };

  @override
  Widget build(BuildContext context) {
    if (!_seeded) {
      // Seed from the CURRENT state so a listener firing before any build-
      // time emission still diffs against reality, not an empty set.
      _lastAlive = _allTabIds(context.read<TabsBloc>().state);
      _seeded = true;
    }
    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) {
        final before = _allTabIds(prev);
        final after = _allTabIds(next);
        return before.any((id) => !after.contains(id));
      },
      listener: (context, state) {
        final alive = _allTabIds(state);
        final closed = {
          for (final id in _lastAlive)
            if (!alive.contains(id)) id,
        };
        _lastAlive = alive;
        if (closed.isEmpty) return;
        context.read<RealtimeBloc>().add(RealtimeTabsClosed(closed));
        context.read<McpBloc>().add(McpTabsClosed(closed));
      },
      child: widget.child,
    );
  }
}
