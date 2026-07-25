// HEADERS tab: lists the current response's headers as key/value rows
// (keys uppercased at render time), with a magnifier-toggled row filter
// (ResponseRowFilterBar) matching name+value case-insensitive contains — C1
// "find everywhere" for the table modes. Gates its BlocBuilder on response
// identity, not a headers map compare, since the response is replaced
// wholesale on every send; the filter is local widget state and never
// widens that gate.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_row_filter_bar.dart';

/// HEADERS tab: lists the response headers as key/value rows with a
/// magnifier-toggled name+value row filter.
class ResponseHeadersView extends StatefulWidget {
  const ResponseHeadersView({required this.tabId, super.key});
  final String tabId;

  @override
  State<ResponseHeadersView> createState() => _ResponseHeadersViewState();
}

class _ResponseHeadersViewState extends State<ResponseHeadersView> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        // response is replaced wholesale on each send, so a reference check is
        // an O(1) gate — no MapEquality over headers on every state emission.
        return !identical(
          prev.tabs.byId(widget.tabId)?.response,
          next.tabs.byId(widget.tabId)?.response,
        );
      },
      builder: (context, state) {
        final tab = state.tabs.byId(widget.tabId);
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

        final q = _filter.trim().toLowerCase();
        final entries = headers.entries
            .where(
              (e) =>
                  q.isEmpty ||
                  e.key.toLowerCase().contains(q) ||
                  e.value.toLowerCase().contains(q),
            )
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ResponseRowFilterBar(
              onQueryChanged: (query) => setState(() => _filter = query),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        'NO MATCHES',
                        key: const ValueKey('row_filter_no_matches'),
                        style: TextStyle(
                          fontSize: layout.fontSizeNormal,
                          fontWeight: context.appTypography.displayWeight,
                          color: theme.dividerColor.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final e = entries[index];
                        // Uppercase at the call site — preserves the existing
                        // rendering (integration tests assert
                        // find.textContaining('CONTENT-TYPE')).
                        return context.appComponents.dataRow(
                          context,
                          label: e.key.toUpperCase(),
                          value: e.value,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
