import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// HEADERS tab: lists the response headers as key/value rows.
class ResponseHeadersView extends StatelessWidget {
  const ResponseHeadersView({required this.tabId, super.key});
  final String tabId;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        // response is replaced wholesale on each send, so a reference check is
        // an O(1) gate — no MapEquality over headers on every state emission.
        return !identical(
          prev.tabs.byId(tabId)?.response,
          next.tabs.byId(tabId)?.response,
        );
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        final headers = tab?.response?.headers;
        if (headers == null || headers.isEmpty) {
          return Center(
            child: Text(
              'NO RESPONSE HEADERS',
              style: TextStyle(
                fontSize: layout.fontSizeNormal,
                fontWeight: context.appTypography.displayWeight,
                color: theme.dividerColor.withValues(alpha: 0.6),
              ),
            ),
          );
        }

        final entries = headers.entries.toList();

        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final e = entries[index];
            return ListTile(
              dense: true,
              title: Text(
                e.key.toUpperCase(),
                style: TextStyle(
                  fontWeight: context.appTypography.titleWeight,
                  fontSize: layout.fontSizeNormal,
                  color: theme.primaryColor,
                ),
              ),
              subtitle: Text(
                e.value,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
