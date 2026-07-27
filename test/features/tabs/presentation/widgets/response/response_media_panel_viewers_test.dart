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
import 'package:getman/features/tabs/presentation/widgets/response/viewers/binary_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/csv_response_view.dart';
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

const _tabId = 'tab-media-viewers';

HttpRequestTabEntity _tabWith({
  required String contentType,
  required Uint8List? bytes,
}) {
  return HttpRequestTabEntity(
    tabId: _tabId,
    config: const HttpRequestConfigEntity(
      id: 'cfg-media-viewers',
      url: 'https://api.example.com/resource',
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

/// Pumps the panel WITHOUT pumpAndSettle — the pdf/video/audio preview
/// viewers show a looping spinner while their (test-VM-doomed) native load
/// is in flight, which would hang pumpAndSettle. Bounded pumps instead.
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('PREVIEW routing by kind', () {
    testWidgets('application/pdf routes to the PDF viewer', (tester) async {
      await _pump(
        tester,
        contentType: 'application/pdf',
        bytes: Uint8List.fromList('%PDF-1.4\n%%EOF'.codeUnits),
      );
      expect(find.byKey(const ValueKey('media_preview_pdf')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('video/mp4 routes to the video viewer', (tester) async {
      await _pump(
        tester,
        contentType: 'video/mp4',
        bytes: Uint8List.fromList(const [0, 1, 2, 3]),
      );
      expect(
        find.byKey(const ValueKey('media_preview_video')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('audio/mpeg routes to the audio viewer', (tester) async {
      await _pump(
        tester,
        contentType: 'audio/mpeg',
        bytes: Uint8List.fromList(const [0, 1, 2, 3]),
      );
      expect(
        find.byKey(const ValueKey('media_preview_audio')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PREVIEW / RAW toggle', () {
    testWidgets('RAW always shows the binary card; PREVIEW switches back', (
      tester,
    ) async {
      final csvBytes = Uint8List.fromList(utf8.encode('a,b\n1,2'));
      await _pump(tester, contentType: 'text/csv', bytes: csvBytes);
      expect(find.byType(CsvResponseView), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('media_toggle_RAW')));
      await tester.pumpAndSettle();
      expect(find.byType(BinaryResponseView), findsOneWidget);
      expect(find.byType(CsvResponseView), findsNothing);

      await tester.tap(find.byKey(const ValueKey('media_toggle_PREVIEW')));
      await tester.pumpAndSettle();
      expect(find.byType(CsvResponseView), findsOneWidget);
      expect(find.byType(BinaryResponseView), findsNothing);
    });
  });

  group('panel-level SAVE TO FILE', () {
    testWidgets('saves the raw bytes under the media extension', (
      tester,
    ) async {
      const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null; // user cancelled — no real file I/O
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final csvBytes = Uint8List.fromList(utf8.encode('a,b\n1,2'));
      await _pump(tester, contentType: 'text/csv', bytes: csvBytes);

      await tester.tap(find.byTooltip('Save response to file'));
      await tester.pumpAndSettle();

      final call = calls.single;
      expect(call.method, 'save');
      final args = call.arguments as Map;
      expect(args['fileName'], 'response.csv');
      expect(args['allowedExtensions'], ['csv']);
      expect(args['bytes'], csvBytes);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
