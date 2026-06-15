import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/cookie_parser.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// COOKIES tab: parses the response's `set-cookie` header into name/value rows.
class ResponseCookiesView extends StatelessWidget {
  final String tabId;
  const ResponseCookiesView({super.key, required this.tabId});

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
        final headers = state.tabs.byId(tabId)?.response?.headers;
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

        return ListView.builder(
          itemCount: cookies.length,
          itemBuilder: (context, index) {
            final c = cookies[index];
            return ListTile(
              dense: true,
              title: Text(
                c.name,
                style: TextStyle(
                  fontWeight: context.appTypography.titleWeight,
                  fontSize: layout.fontSizeNormal,
                  color: theme.primaryColor,
                ),
              ),
              subtitle: Text(
                c.attributes.isEmpty ? c.value : '${c.value}\n${c.attributes}',
                style: TextStyle(fontSize: layout.fontSizeNormal, color: theme.colorScheme.onSurface),
              ),
            );
          },
        );
      },
    );
  }
}
