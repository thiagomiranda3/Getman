import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/environment_resolver.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_event.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_state.dart';

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
  final Map<String, String> activeVars;

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
            onPressed: () {
              final bloc = context.read<RealtimeBloc>();
              if (connected) {
                bloc.add(Disconnect(tabId));
              } else {
                bloc.add(
                  Connect(
                    tabId: tabId,
                    kind: config.kind,
                    url: EnvironmentResolver.resolve(config.url, activeVars),
                    headers: EnvironmentResolver.resolveMap(
                      config.headers,
                      activeVars,
                    ),
                  ),
                );
              }
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
