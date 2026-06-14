import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';

/// Live view for a WebSocket/SSE session: connection status, the message/event
/// log (direction shown by icon + label, not color alone), and — for
/// WebSocket — a composer to send messages.
class RealtimePanel extends StatefulWidget {
  final String tabId;
  const RealtimePanel({super.key, required this.tabId});

  @override
  State<RealtimePanel> createState() => _RealtimePanelState();
}

class _RealtimePanelState extends State<RealtimePanel> {
  final TextEditingController _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  void _send() {
    final text = _composer.text;
    if (text.isEmpty) return;
    context.read<RealtimeBloc>().add(SendRealtimeMessage(widget.tabId, text));
    _composer.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final kind =
        context.read<TabsBloc>().state.tabs.byId(widget.tabId)?.config.kind ?? RequestKind.http;

    return BlocBuilder<RealtimeBloc, RealtimeState>(
      buildWhen: (p, n) => p.sessionFor(widget.tabId) != n.sessionFor(widget.tabId),
      builder: (context, state) {
        final session = state.sessionFor(widget.tabId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBanner(connected: session.connected),
            SizedBox(height: layout.tabSpacing),
            Expanded(
              child: Container(
                decoration: context.appDecoration.panelBox(context, offset: 0),
                child: session.frames.isEmpty
                    ? Center(
                        child: Text(
                          kind == RequestKind.sse
                              ? 'CONNECT TO STREAM EVENTS'
                              : 'CONNECT TO START MESSAGING',
                          style: TextStyle(
                            fontSize: layout.fontSizeNormal,
                            fontWeight: context.appTypography.titleWeight,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(layout.isCompact ? 8 : 12),
                        itemCount: session.frames.length,
                        itemBuilder: (context, i) => _FrameRow(frame: session.frames[i]),
                      ),
              ),
            ),
            if (kind == RequestKind.webSocket) ...[
              SizedBox(height: layout.tabSpacing),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      enabled: session.connected,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  SizedBox(width: layout.tabSpacing),
                  context.appDecoration.wrapInteractive(
                    child: ElevatedButton(
                      onPressed: session.connected ? _send : null,
                      child: Text('SEND',
                          style: TextStyle(fontWeight: context.appTypography.displayWeight)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool connected;
  const _StatusBanner({required this.connected});

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final palette = context.appPalette;
    final color = connected ? palette.statusSuccess : palette.statusError;
    final on = palette.onColor(color);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: layout.isCompact ? 4 : 8),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Theme.of(context).dividerColor, width: layout.borderThin),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(connected ? Icons.link : Icons.link_off, color: on, size: layout.smallIconSize),
          const SizedBox(width: 6),
          Text(
            connected ? 'CONNECTED' : 'DISCONNECTED',
            style: TextStyle(
              color: on,
              fontWeight: context.appTypography.displayWeight,
              fontSize: layout.fontSizeNormal,
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameRow extends StatelessWidget {
  final RealtimeFrame frame;
  const _FrameRow({required this.frame});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final (icon, label, color) = switch (frame.direction) {
      RealtimeDirection.incoming => (Icons.arrow_downward, 'IN', theme.colorScheme.onSurface),
      RealtimeDirection.outgoing => (Icons.arrow_upward, 'OUT', theme.colorScheme.secondary),
      RealtimeDirection.open => (Icons.link, 'OPEN', context.appPalette.statusSuccess),
      RealtimeDirection.close => (Icons.link_off, 'CLOSE', theme.colorScheme.onSurface),
      RealtimeDirection.error => (Icons.error_outline, 'ERROR', context.appPalette.statusError),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: layout.tabSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: layout.smallIconSize, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(label,
                style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    fontWeight: context.appTypography.displayWeight,
                    color: color)),
          ),
          Expanded(
            child: SelectableText(
              frame.text,
              style: TextStyle(
                fontFamily: context.appTypography.codeFontFamily,
                fontSize: layout.fontSizeCode,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
