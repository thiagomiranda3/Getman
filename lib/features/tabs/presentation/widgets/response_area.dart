// Switches the response pane by request kind: HTTP -> ResponseSection, MCP ->
// McpPanel, WebSocket/SSE -> RealtimePanel.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/features/mcp/presentation/widgets/mcp_panel.dart';
import 'package:getman/features/realtime/presentation/widgets/realtime_panel.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response_section.dart';
import 'package:re_editor/re_editor.dart';

/// Shows the HTTP [ResponseSection], [McpPanel] for MCP requests, or the live
/// [RealtimePanel] for WebSocket/SSE — switching on the tab's request kind.
class ResponseArea extends StatelessWidget {
  const ResponseArea({
    required this.tabId,
    required this.responseController,
    super.key,
    this.showMetadata = true,
  });
  final String tabId;
  final CodeLineEditingController responseController;
  final bool showMetadata;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) =>
          prev.tabs.byId(tabId)?.config.kind !=
          next.tabs.byId(tabId)?.config.kind,
      builder: (context, state) {
        final kind = state.tabs.byId(tabId)?.config.kind ?? RequestKind.http;
        if (kind == RequestKind.http) {
          return ResponseSection(
            tabId: tabId,
            responseController: responseController,
            showMetadata: showMetadata,
          );
        }
        if (kind == RequestKind.mcp) {
          return McpPanel(tabId: tabId);
        }
        return RealtimePanel(tabId: tabId);
      },
    );
  }
}
