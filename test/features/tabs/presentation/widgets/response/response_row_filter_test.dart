import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_cookies_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_headers_view.dart';

// Lightweight fake — only exposes `state`.
class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initialState);

  @override
  bool get canReopenClosedTab => false;
}

const _kTabId = 'tab-row-filter';

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, String> headers,
  required Widget child,
}) async {
  final tab = HttpRequestTabEntity(
    tabId: _kTabId,
    config: const HttpRequestConfigEntity(id: 'cfg', url: 'https://x.test'),
    response: HttpResponseEntity(
      statusCode: 200,
      body: '',
      headers: headers,
      durationMs: 10,
    ),
  );
  await tester.pumpWidget(
    BlocProvider<TabsBloc>(
      create: (_) => _FakeTabsBloc(TabsState(tabs: [tab])),
      child: MaterialApp(
        theme: resolveTheme(kClassicThemeId)(
          Brightness.light,
          isCompact: false,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openFilterAndType(WidgetTester tester, String query) async {
  await tester.tap(find.byKey(const ValueKey('row_filter_toggle')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('row_filter_field')),
    query,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ResponseHeadersView row filter', () {
    const headers = {
      'content-type': 'application/json',
      'x-request-id': 'abc-123',
      'cache-control': 'no-store',
    };

    testWidgets('filter by name narrows the rows (case-insensitive)', (
      tester,
    ) async {
      await _pump(
        tester,
        headers: headers,
        child: const ResponseHeadersView(tabId: _kTabId),
      );
      expect(find.textContaining('CACHE-CONTROL'), findsOneWidget);

      await _openFilterAndType(tester, 'CONTENT');
      expect(find.textContaining('CONTENT-TYPE'), findsOneWidget);
      expect(find.textContaining('X-REQUEST-ID'), findsNothing);
      expect(find.textContaining('CACHE-CONTROL'), findsNothing);
    });

    testWidgets('filter matches values too', (tester) async {
      await _pump(
        tester,
        headers: headers,
        child: const ResponseHeadersView(tabId: _kTabId),
      );
      await _openFilterAndType(tester, 'abc-123');
      expect(find.textContaining('X-REQUEST-ID'), findsOneWidget);
      expect(find.textContaining('CONTENT-TYPE'), findsNothing);
    });

    testWidgets('no hit shows NO MATCHES; closing the bar restores rows', (
      tester,
    ) async {
      await _pump(
        tester,
        headers: headers,
        child: const ResponseHeadersView(tabId: _kTabId),
      );
      await _openFilterAndType(tester, 'zzz-nothing');
      expect(
        find.byKey(const ValueKey('row_filter_no_matches')),
        findsOneWidget,
      );

      // Toggle closed → query cleared → all rows back.
      await tester.tap(find.byKey(const ValueKey('row_filter_toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row_filter_field')), findsNothing);
      expect(find.textContaining('CONTENT-TYPE'), findsOneWidget);
      expect(find.textContaining('X-REQUEST-ID'), findsOneWidget);
    });
  });

  group('ResponseCookiesView row filter', () {
    testWidgets('filters cookies by name and value', (tester) async {
      await _pump(
        tester,
        headers: const {'set-cookie': 'sessionId=abc123; Path=/'},
        child: const ResponseCookiesView(tabId: _kTabId),
      );
      expect(find.textContaining('sessionId'), findsOneWidget);

      await _openFilterAndType(tester, 'session');
      expect(find.textContaining('sessionId'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('row_filter_field')),
        'nope',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('row_filter_no_matches')),
        findsOneWidget,
      );
    });
  });
}
