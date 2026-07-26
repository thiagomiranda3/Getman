import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
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
import 'package:getman/features/tabs/domain/entities/response_history_entry.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_body_controls.dart';

// Lightweight fake blocs; the collections bloc records dispatched events so
// tests can assert on the SaveExampleToNode the dialog flow produced.
class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initialState);

  @override
  bool get canReopenClosedTab => false;
}

class _RecordingCollectionsBloc extends Bloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {
  _RecordingCollectionsBloc(super.initialState) {
    on<CollectionsEvent>((event, emit) => events.add(event));
  }

  final List<CollectionsEvent> events = [];
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc(super.initialState);
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc(super.initialState);
}

const _tabId = 'tab-controls';

const _currentResponse = HttpResponseEntity(
  statusCode: 200,
  body: '{"a":1}',
  headers: {'content-type': 'application/json'},
  durationMs: 12,
);

HttpRequestTabEntity _tabWith({
  HttpResponseEntity? response,
  String? nodeId,
  List<ResponseHistoryEntry> responseHistory = const [],
}) => HttpRequestTabEntity(
  tabId: _tabId,
  config: const HttpRequestConfigEntity(
    id: 'cfg-controls',
    url: 'https://api.example.com/users',
  ),
  response: response,
  collectionNodeId: nodeId,
  responseHistory: responseHistory,
);

Future<_RecordingCollectionsBloc> _pump(
  WidgetTester tester, {
  required HttpRequestTabEntity tab,
  String copyableText = '{"a":1}',
  HistoryState history = const HistoryState(),
  CollectionsState? collections,
}) async {
  final collectionsBloc = _RecordingCollectionsBloc(
    collections ?? CollectionsState(),
  );
  addTearDown(collectionsBloc.close);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TabsBloc>(
          create: (_) => _FakeTabsBloc(TabsState(tabs: [tab])),
        ),
        BlocProvider<CollectionsBloc>.value(value: collectionsBloc),
        BlocProvider<HistoryBloc>(
          create: (_) => _FakeHistoryBloc(history),
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
        home: Scaffold(
          body: ResponseBodyControls(
            tabId: _tabId,
            getCopyableText: () => copyableText,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return collectionsBloc;
}

/// Mocks the file_picker method channel; returns the recorded `save` calls.
/// The handler answers null (user cancelled) so no real file I/O happens.
List<MethodCall> _mockFilePicker(WidgetTester tester) {
  const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    calls.add(call);
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
  return calls;
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
  group('save as example', () {
    testWidgets('hidden when the tab is not linked to a collection node', (
      tester,
    ) async {
      await _pump(tester, tab: _tabWith(response: _currentResponse));
      expect(
        find.byKey(const ValueKey('save_as_example_button')),
        findsNothing,
      );
    });

    testWidgets(
      'prompts with a "status · time" default and dispatches '
      'SaveExampleToNode on confirm',
      (tester) async {
        final collections = await _pump(
          tester,
          tab: _tabWith(response: _currentResponse, nodeId: 'node-1'),
        );

        await tester.tap(find.byKey(const ValueKey('save_as_example_button')));
        await tester.pumpAndSettle();

        expect(find.text('SAVE AS EXAMPLE'), findsOneWidget);
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('name_prompt_field')),
        );
        expect(
          field.controller!.text,
          matches(RegExp(r'^200 · \d{2}:\d{2}$')),
          reason: 'default name is "<status> · <hh:mm>"',
        );

        await tester.enterText(
          find.byKey(const ValueKey('name_prompt_field')),
          'Golden run',
        );
        await tester.tap(find.text('SAVE'));
        await tester.pumpAndSettle();

        final event = collections.events.single as SaveExampleToNode;
        expect(event.nodeId, 'node-1');
        expect(event.example.name, 'Golden run');
        expect(event.example.config.statusCode, 200);
        expect(event.example.config.responseBody, '{"a":1}');
        expect(
          event.example.config.responseHeaders,
          {'content-type': 'application/json'},
        );
        expect(find.text('Saved example "Golden run"'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
      },
    );
  });

  group('compare', () {
    testWidgets(
      'picking a history target opens the diff view with both labels',
      (tester) async {
        await _pump(
          tester,
          tab: _tabWith(response: _currentResponse),
          history: const HistoryState(
            history: [
              HttpRequestConfigEntity(
                id: 'h1',
                url: 'https://api.example.com/users',
                statusCode: 200,
                responseBody: '{"a":2}',
                responseHeaders: {},
                durationMs: 9,
              ),
            ],
          ),
        );

        await tester.tap(
          find.byKey(const ValueKey('compare_response_button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('COMPARE WITH'), findsOneWidget);

        await tester.tap(
          find.text('GET https://api.example.com/users · 200'),
        );
        // ResponseDiffBuilder prettifies both bodies via compute() — two
        // sequential isolate hops, each needing a real-async window
        // (runAsync) followed by a fake-zone microtask flush (pump).
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(find.text('This response'), findsOneWidget);
        expect(
          find.text('GET https://api.example.com/users · 200'),
          findsOneWidget,
          reason: 'the picked target labels the right side of the diff',
        );
      },
    );

    testWidgets(
      'lists saved examples and earlier timeline responses, excluding the '
      'currently-shown one and placeholder bodies; CANCEL closes cleanly',
      (tester) async {
        const exampleConfig = HttpRequestConfigEntity(
          id: 'cfg-ex',
          url: 'https://api.example.com/users',
          statusCode: 200,
          responseBody: '{"e":1}',
          responseHeaders: {},
          durationMs: 3,
        );
        final tab = _tabWith(
          response: _currentResponse,
          nodeId: 'node-1',
          responseHistory: const [
            // Head mirrors the current response — must be excluded.
            ResponseHistoryEntry(
              id: 'rh-0',
              response: _currentResponse,
              capturedAt: 1700000300000,
            ),
            ResponseHistoryEntry(
              id: 'rh-1',
              response: HttpResponseEntity(
                statusCode: 201,
                body: '{"old":1}',
                headers: {},
                durationMs: 7,
              ),
              capturedAt: 1700000200000,
            ),
            // Metadata-only placeholder — must be excluded too.
            ResponseHistoryEntry(
              id: 'rh-2',
              response: HttpResponseEntity(
                statusCode: 202,
                body: kResponseBodyTooLargePlaceholder,
                headers: {},
                durationMs: 8,
              ),
              capturedAt: 1700000100000,
            ),
          ],
        );
        await _pump(
          tester,
          tab: tab,
          collections: CollectionsState(
            collections: [
              CollectionNodeEntity(
                id: 'node-1',
                name: 'Users',
                isFolder: false,
                config: const HttpRequestConfigEntity(id: 'node-1'),
                examples: [
                  SavedExampleEntity(
                    id: 'ex-1',
                    name: 'Golden',
                    capturedAt: DateTime(2026, 7, 26, 10, 30),
                    config: exampleConfig,
                  ),
                ],
              ),
            ],
          ),
        );

        await tester.tap(
          find.byKey(const ValueKey('compare_response_button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('SAVED EXAMPLES'), findsOneWidget);
        expect(find.text('Golden'), findsOneWidget);
        expect(find.text('PREVIOUS RESPONSES (this tab)'), findsOneWidget);
        expect(find.text('Response 201'), findsOneWidget);
        expect(
          find.text('Response 200'),
          findsNothing,
          reason: 'the currently-displayed response is not a target',
        );
        expect(
          find.text('Response 202'),
          findsNothing,
          reason: 'placeholder bodies are not comparable',
        );

        await tester.tap(find.text('CANCEL'));
        await tester.pumpAndSettle();
        expect(find.text('COMPARE WITH'), findsNothing);
        expect(find.text('This response'), findsNothing);
      },
    );
  });

  group('save to file', () {
    testWidgets(
      'passes the copyable text as response.json with json/txt extensions',
      (tester) async {
        final calls = _mockFilePicker(tester);
        await _pump(
          tester,
          tab: _tabWith(response: _currentResponse),
          copyableText: '{"pretty": true}',
        );

        await tester.tap(find.byTooltip('Save response to file'));
        await tester.pumpAndSettle();

        final call = calls.single;
        expect(call.method, 'save');
        final args = call.arguments as Map;
        expect(args['fileName'], 'response.json');
        expect(args['allowedExtensions'], ['json', 'txt']);
        expect(args['bytes'], utf8.encode('{"pretty": true}'));
        // Cancelled picker → silent no-op, no feedback snackbar.
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('empty body: save and copy are silent no-ops', (tester) async {
      final calls = _mockFilePicker(tester);
      final clips = _mockClipboard(tester);
      await _pump(
        tester,
        tab: _tabWith(response: _currentResponse),
        copyableText: '',
      );

      await tester.tap(find.byTooltip('Save response to file'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.tap(find.byTooltip('Copy response'));
      await tester.pumpAndSettle();
      expect(clips, isEmpty);
      expect(find.text('Response copied'), findsNothing);
    });
  });
}
