import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/http_methods.dart';
import 'package:getman/core/network/request_kind.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

/// The leading kind (HTTP / WS / SSE) + HTTP-method selector cluster of the URL
/// bar. The method dropdown only shows for HTTP requests. Dispatches UpdateTab
/// directly so the URL bar stays a thin composition.
class RequestKindMethodSelector extends StatelessWidget {
  final HttpRequestTabEntity tab;
  final bool isNarrow;

  const RequestKindMethodSelector({
    super.key,
    required this.tab,
    required this.isNarrow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final smallGap = isNarrow ? 2.0 : (layout.isCompact ? 4.0 : 8.0);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 6 : (layout.isCompact ? 8 : 12)),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: theme.dividerColor, width: layout.borderThick)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<RequestKind>(
              dropdownColor: theme.colorScheme.surface,
              value: tab.config.kind,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: context.appTypography.displayWeight,
                fontSize: layout.fontSizeSmall,
              ),
              items: const [
                DropdownMenuItem(value: RequestKind.http, child: Text('HTTP')),
                DropdownMenuItem(value: RequestKind.webSocket, child: Text('WS')),
                DropdownMenuItem(value: RequestKind.sse, child: Text('SSE')),
              ],
              onChanged: (k) {
                if (k != null && tab.config.kind != k) {
                  context.read<TabsBloc>().add(UpdateTab(
                    tab.copyWith(config: tab.config.copyWith(kind: k)),
                  ));
                }
              },
            ),
          ),
          if (tab.config.kind == RequestKind.http) ...[
            SizedBox(width: smallGap),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                dropdownColor: theme.colorScheme.surface,
                value: tab.config.method,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: context.appTypography.displayWeight,
                  fontSize: layout.fontSizeNormal,
                ),
                selectedItemBuilder: (context) {
                  return HttpMethods.all.map((m) => Center(child: MethodBadge(method: m))).toList();
                },
                items: HttpMethods.all
                    .map((m) => DropdownMenuItem(
                      value: m,
                      child: SizedBox(
                        width: isNarrow ? 64 : (layout.isCompact ? 80 : 100),
                        child: Center(child: MethodBadge(method: m)),
                      ),
                    ))
                    .toList(),
                onChanged: (val) {
                  if (val != null && tab.config.method != val) {
                    context.read<TabsBloc>().add(UpdateTab(
                      tab.copyWith(config: tab.config.copyWith(method: val)),
                    ));
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
