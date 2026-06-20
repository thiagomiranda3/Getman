import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';

AppLogLineKind _logKindFor(RealtimeDirection d) => switch (d) {
  RealtimeDirection.incoming => AppLogLineKind.incoming,
  RealtimeDirection.outgoing => AppLogLineKind.outgoing,
  RealtimeDirection.open => AppLogLineKind.open,
  RealtimeDirection.close => AppLogLineKind.close,
  RealtimeDirection.error => AppLogLineKind.error,
};

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
          builder: (context, state) {
            final connected = state.sessionFor(widget.tabId).connected;
            return context.appComponents.statusBanner(
              context,
              state: connected ? AppBannerState.success : AppBannerState.error,
              message: connected ? 'CONNECTED' : 'DISCONNECTED',
            );
          },
        ),
        SizedBox(height: layout.tabSpacing),
        Expanded(
          child: RepaintBoundary(
            child: context.appDecoration.frost(
              context,
              borderRadius: BorderRadius.circular(context.appShape.panelRadius),
              child: context.appComponents.surface(
                context,
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
                    return context.appComponents.logView(
                      context,
                      lines: [
                        for (final f in frames)
                          AppLogLine(
                            text: f.text,
                            kind: _logKindFor(f.direction),
                          ),
                      ],
                    );
                  },
                ),
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
                      key: const ValueKey('realtime_message_input'),
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
                      key: const ValueKey('realtime_send_button'),
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
