// HEADERS tab: lists the current response's headers as key/value rows
// (keys uppercased at render time), with a magnifier-toggled row filter
// (ResponseRowFilterBar) matching name+value case-insensitive contains — C1
// "find everywhere" for the table modes — and a COPY ALL button sharing that
// toolbar row (C3) that copies every header as an unfiltered `Key: value`
// line in original wire casing. Gates its BlocBuilder on response identity,
// not a headers map compare, since the response is replaced wholesale on
// every send; the filter is local widget state and never widens that gate.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_row_filter_bar.dart';

/// HEADERS tab: lists the response headers as key/value rows with a
/// magnifier-toggled name+value row filter and a COPY ALL toolbar button.
class ResponseHeadersView extends StatefulWidget {
  const ResponseHeadersView({required this.tabId, super.key});
  final String tabId;

  @override
  State<ResponseHeadersView> createState() => _ResponseHeadersViewState();
}

class _ResponseHeadersViewState extends State<ResponseHeadersView> {
  String _filter = '';

  /// Copies every header as a `Key: value` line (original wire casing,
  /// `\n`-joined, ALL rows regardless of the active filter) — the C3 COPY
  /// ALL payload contract.
  static Future<void> _copyAll(
    BuildContext context,
    List<MapEntry<String, String>> entries,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = [for (final e in entries) '${e.key}: ${e.value}'].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    showAppSnackBarVia(messenger, 'Headers copied');
  }

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

        final allEntries = headers.entries.toList();
        final q = _filter.trim().toLowerCase();
        final visibleEntries = allEntries
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
            Row(
              children: [
                Expanded(
                  child: ResponseRowFilterBar(
                    onQueryChanged: (query) => setState(() => _filter = query),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(right: layout.pagePadding),
                  child: TextButton.icon(
                    key: const ValueKey('headers_copy_all_button'),
                    onPressed: () => unawaited(_copyAll(context, allEntries)),
                    icon: Icon(
                      Icons.copy_all_outlined,
                      size: layout.smallIconSize,
                    ),
                    label: Text(
                      'COPY ALL',
                      style: TextStyle(
                        fontSize: layout.fontSizeSmall,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: visibleEntries.isEmpty
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
                      itemCount: visibleEntries.length,
                      itemBuilder: (context, index) {
                        final e = visibleEntries[index];
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
