// COOKIES tab: parses the current response's `set-cookie` header (via
// CookieParser) into name/value rows, with a magnifier-toggled row filter
// (ResponseRowFilterBar) matching name+value case-insensitive contains — C1
// "find everywhere" for the table modes — and a COPY ALL button sharing that
// toolbar row (C3) that copies every cookie as an unfiltered
// `name: value[; attributes]` line. Gates its BlocBuilder on response
// identity, not a headers map compare, since the response is replaced
// wholesale on every send; the filter is local widget state and never
// widens that gate.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/utils/cookie_parser.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_row_filter_bar.dart';

/// COOKIES tab: parses the response's `set-cookie` header into name/value
/// rows with a magnifier-toggled name+value row filter and a COPY ALL
/// toolbar button.
class ResponseCookiesView extends StatefulWidget {
  const ResponseCookiesView({required this.tabId, super.key});
  final String tabId;

  @override
  State<ResponseCookiesView> createState() => _ResponseCookiesViewState();
}

class _ResponseCookiesViewState extends State<ResponseCookiesView> {
  String _filter = '';

  /// One `name: value` line per cookie, `; attributes` appended when present
  /// — the C3 COPY ALL payload contract (attributes stay on the same line so
  /// the payload is one row per line).
  static String _cookieLine(ParsedCookie c) => c.attributes.isEmpty
      ? '${c.name}: ${c.value}'
      : '${c.name}: ${c.value}; ${c.attributes}';

  /// Copies every cookie regardless of the active filter — the C3 COPY ALL
  /// payload contract.
  static Future<void> _copyAll(
    BuildContext context,
    List<ParsedCookie> cookies,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = [for (final c in cookies) _cookieLine(c)].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    showAppSnackBarVia(messenger, 'Cookies copied');
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
        final headers = state.tabs.byId(widget.tabId)?.response?.headers;
        if (headers == null) return const SizedBox();

        String? setCookie;
        for (final e in headers.entries) {
          if (e.key.toLowerCase() == 'set-cookie') {
            setCookie = e.value;
            break;
          }
        }
        final cookies = CookieParser.parse(setCookie);

        if (cookies.isEmpty) {
          return Center(
            child: Text(
              'NO COOKIES',
              style: TextStyle(
                fontSize: layout.fontSizeTitle,
                fontWeight: context.appTypography.displayWeight,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          );
        }

        final q = _filter.trim().toLowerCase();
        final visible = cookies
            .where(
              (c) =>
                  q.isEmpty ||
                  c.name.toLowerCase().contains(q) ||
                  c.value.toLowerCase().contains(q),
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
                    key: const ValueKey('cookies_copy_all_button'),
                    onPressed: () => unawaited(_copyAll(context, cookies)),
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
              child: visible.isEmpty
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
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final c = visible[index];
                        // Cookie name is NOT uppercased — preserved as-is from
                        // the header.
                        return context.appComponents.dataRow(
                          context,
                          label: c.name,
                          value: c.attributes.isEmpty
                              ? c.value
                              : '${c.value}\n${c.attributes}',
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
