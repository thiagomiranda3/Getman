import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/features/realtime/presentation/widgets/realtime_panel.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response_section.dart';
import 'package:re_editor/re_editor.dart';

/// Shows the HTTP [ResponseSection] or, for WebSocket/SSE requests, the live
/// [RealtimePanel] — switching on the tab's request kind.
class ResponseArea extends StatelessWidget {
  final String tabId;
  final CodeLineEditingController responseController;
  final bool showMetadata;

  const ResponseArea({
    super.key,
    required this.tabId,
    required this.responseController,
    this.showMetadata = true,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) =>
          prev.tabs.byId(tabId)?.config.kind != next.tabs.byId(tabId)?.config.kind,
      builder: (context, state) {
        final kind = state.tabs.byId(tabId)?.config.kind ?? RequestKind.http;
        if (kind == RequestKind.http) {
          return ResponseSection(
            tabId: tabId,
            responseController: responseController,
            showMetadata: showMetadata,
          );
        }
        return RealtimePanel(tabId: tabId);
      },
    );
  }
}
