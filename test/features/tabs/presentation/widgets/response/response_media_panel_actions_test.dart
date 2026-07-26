import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/response_media_panel.dart';

class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initialState);

  @override
  bool get canReopenClosedTab => false;
}

class _FakeCollectionsBloc extends Bloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {
  _FakeCollectionsBloc(super.initialState);
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc(super.initialState);
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc(super.initialState);
}

const _tabId = 'tab-media-actions';

HttpRequestTabEntity _tabWith({
  required String contentType,
  required Uint8List? bytes,
}) {
  return HttpRequestTabEntity(
    tabId: _tabId,
    config: const HttpRequestConfigEntity(
      id: 'cfg-media',
      url: 'https://api.example.com/data.bin',
    ),
    response: HttpResponseEntity(
      statusCode: 200,
      body: '$contentType · ${bytes?.length ?? 0} B',
      headers: {'content-type': contentType},
      durationMs: 10,
      bodyBytes: bytes,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required String contentType,
  required Uint8List? bytes,
}) async {
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TabsBloc>(
          create: (_) => _FakeTabsBloc(
            TabsState(
              tabs: [_tabWith(contentType: contentType, bytes: bytes)],
            ),
          ),
        ),
        BlocProvider<CollectionsBloc>(
          create: (_) => _FakeCollectionsBloc(CollectionsState()),
        ),
        BlocProvider<HistoryBloc>(
          create: (_) => _FakeHistoryBloc(const HistoryState()),
        ),
        BlocProvider<SettingsBloc>(
          create: (_) => _FakeSettingsBloc(
            const SettingsState(settings: SettingsEntity()),
          ),
        ),
      ],
      child: MaterialApp(
        theme: resolveTheme(kClassicThemeId)(
          Brightness.light,
          isCompact: false,
        ),
        home: const Scaffold(body: ResponseMediaPanel(tabId: _tabId)),
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

IconButton _buttonByTooltip(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );

void main() {
  group('csv media (text-ish)', () {
    final csvBytes = Uint8List.fromList(utf8.encode('a,b\n1,2'));

    testWidgets('COPY is enabled and copies the decoded text', (tester) async {
      final clips = _mockClipboard(tester);
      await _pump(tester, contentType: 'text/csv', bytes: csvBytes);

      await tester.tap(find.byTooltip('Copy response'));
      await tester.pump();
      expect(clips, ['a,b\n1,2']);
      expect(find.text('Response copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('SAVE TO FILE and COMPARE are surfaced at panel level', (
      tester,
    ) async {
      await _pump(tester, contentType: 'text/csv', bytes: csvBytes);
      expect(
        _buttonByTooltip(tester, 'Save response to file').onPressed,
        isNotNull,
      );
      expect(
        find.byKey(const ValueKey('compare_response_button')),
        findsOneWidget,
      );
      // Unlinked tab → SAVE AS EXAMPLE stays hidden (same rule as body view).
      expect(
        find.byKey(const ValueKey('save_as_example_button')),
        findsNothing,
      );
    });
  });

  group('binary media (not text-ish)', () {
    // GZIP magic bytes: classifyResponseMedia falls through content-type
    // ('application/octet-stream' is deliberately ambiguous) and the
    // unmapped `.bin` URL extension to the magic-byte sniff — a positive
    // signal is required to land on `binary` rather than the conservative
    // `textual` default (see response_media.dart's header).
    final binBytes = Uint8List.fromList([0x1F, 0x8B, 0x08, 0x00]);

    testWidgets('COPY is disabled with the explanatory tooltip', (
      tester,
    ) async {
      await _pump(
        tester,
        contentType: 'application/octet-stream',
        bytes: binBytes,
      );
      final copy = _buttonByTooltip(
        tester,
        'Copy is available for CSV/HTML media only',
      );
      expect(copy.onPressed, isNull);
    });

    testWidgets('SAVE TO FILE disabled when live bytes are gone', (
      tester,
    ) async {
      await _pump(
        tester,
        contentType: 'application/octet-stream',
        bytes: null,
      );
      expect(
        _buttonByTooltip(tester, 'Save response to file').onPressed,
        isNull,
      );
    });
  });
}
