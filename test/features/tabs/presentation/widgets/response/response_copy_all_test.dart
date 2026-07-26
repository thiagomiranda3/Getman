import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initialState);

  @override
  bool get canReopenClosedTab => false;
}

const _kTabId = 'tab-copy-all';

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, String> headers,
  required Widget view,
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
        home: Scaffold(body: view),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _mockClipboard(WidgetTester tester) {
  final clips = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clips.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return clips;
}

void main() {
  group('HEADERS copy all', () {
    testWidgets(r'copies Key: value lines in wire casing, \n-joined', (
      tester,
    ) async {
      final clips = _mockClipboard(tester);
      await _pump(
        tester,
        headers: {
          'content-type': 'application/json',
          'x-request-id': 'abc-123',
        },
        view: const ResponseHeadersView(tabId: _kTabId),
      );

      final button = find.byKey(const ValueKey('headers_copy_all_button'));
      expect(button, findsOneWidget);
      expect(find.text('COPY ALL'), findsOneWidget);

      await tester.tap(button);
      await tester.pump();
      expect(clips, [
        'content-type: application/json\nx-request-id: abc-123',
      ]);
      expect(find.text('Headers copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('no toolbar on the empty state', (tester) async {
      await _pump(
        tester,
        headers: const {},
        view: const ResponseHeadersView(tabId: _kTabId),
      );
      expect(
        find.byKey(const ValueKey('headers_copy_all_button')),
        findsNothing,
      );
      expect(find.text('NO RESPONSE HEADERS'), findsOneWidget);
    });
  });

  group('COOKIES copy all', () {
    testWidgets('copies name: value; attributes lines', (tester) async {
      final clips = _mockClipboard(tester);
      await _pump(
        tester,
        headers: const {
          'set-cookie': 'sessionId=abc123; Path=/; HttpOnly, plain=1',
        },
        view: const ResponseCookiesView(tabId: _kTabId),
      );

      final button = find.byKey(const ValueKey('cookies_copy_all_button'));
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();
      expect(clips, [
        'sessionId: abc123; Path=/; HttpOnly\nplain: 1',
      ]);
      expect(find.text('Cookies copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('no toolbar when there are no cookies', (tester) async {
      await _pump(
        tester,
        headers: const {},
        view: const ResponseCookiesView(tabId: _kTabId),
      );
      expect(
        find.byKey(const ValueKey('cookies_copy_all_button')),
        findsNothing,
      );
    });
  });
}
