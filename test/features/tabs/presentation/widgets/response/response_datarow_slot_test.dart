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
}

const _kTabId = 'tab-test';

HttpRequestTabEntity _tabWith({required HttpResponseEntity response}) {
  return HttpRequestTabEntity(
    tabId: _kTabId,
    config: const HttpRequestConfigEntity(id: 'cfg', url: 'https://x.test'),
    response: response,
  );
}

Future<void> _pumpHeaders(
  WidgetTester tester, {
  required Map<String, String> headers,
}) async {
  final tab = _tabWith(
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
        theme: resolveTheme(kBrutalistThemeId)(
          Brightness.light,
          isCompact: false,
        ),
        home: const Scaffold(
          body: ResponseHeadersView(tabId: _kTabId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpCookies(
  WidgetTester tester, {
  required String setCookieHeader,
}) async {
  final tab = _tabWith(
    response: HttpResponseEntity(
      statusCode: 200,
      body: '',
      headers: {'set-cookie': setCookieHeader},
      durationMs: 10,
    ),
  );
  await tester.pumpWidget(
    BlocProvider<TabsBloc>(
      create: (_) => _FakeTabsBloc(TabsState(tabs: [tab])),
      child: MaterialApp(
        theme: resolveTheme(kBrutalistThemeId)(
          Brightness.light,
          isCompact: false,
        ),
        home: const Scaffold(
          body: ResponseCookiesView(tabId: _kTabId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ResponseHeadersView dataRow routing', () {
    testWidgets('renders header key UPPERCASED and value, no exception', (
      tester,
    ) async {
      await _pumpHeaders(
        tester,
        headers: {'content-type': 'application/json'},
      );
      expect(tester.takeException(), isNull);
      // The view uppercases the key at the call site.
      expect(find.textContaining('CONTENT-TYPE'), findsOneWidget);
      expect(find.textContaining('application/json'), findsOneWidget);
    });

    testWidgets('renders multiple headers without exception', (tester) async {
      await _pumpHeaders(
        tester,
        headers: {
          'content-type': 'application/json',
          'x-request-id': 'abc-123',
        },
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('CONTENT-TYPE'), findsOneWidget);
      expect(find.textContaining('X-REQUEST-ID'), findsOneWidget);
    });
  });

  group('ResponseCookiesView dataRow routing', () {
    testWidgets('renders cookie name in original casing and value', (
      tester,
    ) async {
      // The cookie name is NOT uppercased.
      await _pumpCookies(tester, setCookieHeader: 'sessionId=abc123; Path=/');
      expect(tester.takeException(), isNull);
      expect(find.textContaining('sessionId'), findsOneWidget);
      expect(find.textContaining('abc123'), findsOneWidget);
    });

    testWidgets('renders cookie with attributes in multiline subtitle', (
      tester,
    ) async {
      await _pumpCookies(
        tester,
        setCookieHeader: 'token=xyz; HttpOnly; Secure',
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('token'), findsOneWidget);
    });
  });
}
