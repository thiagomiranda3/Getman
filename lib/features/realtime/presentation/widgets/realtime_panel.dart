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
  const RealtimePanel({required this.tabId, super.key});
  final String tabId;

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

  /// Rebuilds only when this tab's connection status flips.
  bool _connectedChanged(RealtimeState p, RealtimeState n) =>
      p.sessionFor(widget.tabId).connected !=
      n.sessionFor(widget.tabId).connected;

  /// Rebuilds only when the frame log grows or its newest entry changes —
  /// frames are append-only + capped, so (length, last timestamp) is a cheap,
  /// sufficient proxy that still catches tail changes once the cap window
  /// slides.
  bool _framesChanged(RealtimeState p, RealtimeState n) {
    final pf = p.sessionFor(widget.tabId).frames;
    final nf = n.sessionFor(widget.tabId).frames;
    if (pf.length != nf.length) return true;
    if (nf.isEmpty) return false;
    return pf.last.timestampMs != nf.last.timestampMs;
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final kind =
        context.read<TabsBloc>().state.tabs.byId(widget.tabId)?.config.kind ??
        RequestKind.http;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlocBuilder<RealtimeBloc, RealtimeState>(
          buildWhen: _connectedChanged,
          builder: (context, state) => _StatusBanner(
            connected: state.sessionFor(widget.tabId).connected,
          ),
        ),
        SizedBox(height: layout.tabSpacing),
        Expanded(
          child: RepaintBoundary(
            child: Container(
              decoration: context.appDecoration.panelBox(context, offset: 0),
              child: BlocBuilder<RealtimeBloc, RealtimeState>(
                buildWhen: _framesChanged,
                builder: (context, state) {
                  final frames = state.sessionFor(widget.tabId).frames;
                  if (frames.isEmpty) {
                    return Center(
                      child: Text(
                        kind == RequestKind.sse
                            ? 'CONNECT TO STREAM EVENTS'
                            : 'CONNECT TO START MESSAGING',
                        style: TextStyle(
                          fontSize: layout.fontSizeNormal,
                          fontWeight: context.appTypography.titleWeight,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: EdgeInsets.all(layout.isCompact ? 8 : 12),
                    itemCount: frames.length,
                    itemBuilder: (context, i) => _FrameRow(frame: frames[i]),
                  );
                },
              ),
            ),
          ),
        ),
        if (kind == RequestKind.webSocket) ...[
          SizedBox(height: layout.tabSpacing),
          BlocBuilder<RealtimeBloc, RealtimeState>(
            buildWhen: _connectedChanged,
            builder: (context, state) {
              final connected = state.sessionFor(widget.tabId).connected;
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      enabled: connected,
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
                      onPressed: connected ? _send : null,
                      child: Text(
                        'SEND',
                        style: TextStyle(
                          fontWeight: context.appTypography.displayWeight,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final palette = context.appPalette;
    final color = connected ? palette.statusSuccess : palette.statusError;
    final on = palette.onColor(color);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: layout.isCompact ? 4 : 8,
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: layout.borderThin,
        ),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connected ? Icons.link : Icons.link_off,
            color: on,
            size: layout.smallIconSize,
          ),
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
  const _FrameRow({required this.frame});
  final RealtimeFrame frame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final (icon, label, color) = switch (frame.direction) {
      RealtimeDirection.incoming => (
        Icons.arrow_downward,
        'IN',
        theme.colorScheme.onSurface,
      ),
      RealtimeDirection.outgoing => (
        Icons.arrow_upward,
        'OUT',
        theme.colorScheme.secondary,
      ),
      RealtimeDirection.open => (
        Icons.link,
        'OPEN',
        context.appPalette.statusSuccess,
      ),
      RealtimeDirection.close => (
        Icons.link_off,
        'CLOSE',
        theme.colorScheme.onSurface,
      ),
      RealtimeDirection.error => (
        Icons.error_outline,
        'ERROR',
        context.appPalette.statusError,
      ),
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
            child: Text(
              label,
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.displayWeight,
                color: color,
              ),
            ),
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
