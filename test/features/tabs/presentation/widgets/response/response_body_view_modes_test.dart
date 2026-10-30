import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
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
import 'package:getman/features/tabs/presentation/widgets/code_find_panel.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/response/large_response_text_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_body_view.dart';
import 'package:re_editor/re_editor.dart';

// Lightweight fake blocs that only expose `state`. The pushable ones let a
// test simulate a re-send / setting flip after the initial pump.
class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initialState);

  void push(TabsState next) => emit(next);

  @override
  bool get canReopenClosedTab => false;

  @override
  Future<void> flushPendingSaves() async {}
}

class _FakeCollectionsBloc extends Bloc<CollectionsEvent, CollectionsState>
    implements CollectionsBloc {
  _FakeCollectionsBloc(super.initialState);

  @override
  Future<void> flushPendingSaves() async {}
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc(super.initialState);
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc(super.initialState);

  void push(SettingsState next) => emit(next);
}

const _tabId = 'tab-modes';

HttpRequestTabEntity _tabWith(
  String body, {
  Map<String, String> headers = const {},
}) => HttpRequestTabEntity(
  tabId: _tabId,
  config: const HttpRequestConfigEntity(
    id: 'cfg-modes',
    url: 'https://api.example.com/data',
  ),
  response: HttpResponseEntity(
    statusCode: 200,
    body: body,
    headers: headers,
    durationMs: 10,
  ),
);

/// Pumps [ResponseBodyView] over pushable tabs/settings fakes and returns
/// them (plus the editor controller) so tests can drive follow-up states.
Future<({_FakeTabsBloc tabs, _FakeSettingsBloc settings})> _pump(
  WidgetTester tester, {
  required String body,
  required CodeLineEditingController controller,
  SettingsEntity settings = const SettingsEntity(),
  bool settle = true,
}) async {
  final tabsBloc = _FakeTabsBloc(TabsState(tabs: [_tabWith(body)]));
  final settingsBloc = _FakeSettingsBloc(SettingsState(settings: settings));
  addTearDown(tabsBloc.close);
  addTearDown(settingsBloc.close);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TabsBloc>.value(value: tabsBloc),
        BlocProvider<CollectionsBloc>(
          create: (_) => _FakeCollectionsBloc(CollectionsState()),
        ),
        BlocProvider<HistoryBloc>(
          create: (_) => _FakeHistoryBloc(const HistoryState()),
        ),
        BlocProvider<SettingsBloc>.value(value: settingsBloc),
      ],
      child: MaterialApp(
        theme: resolveTheme(kClassicThemeId)(
          Brightness.light,
          isCompact: false,
        ),
        home: Scaffold(
          body: ResponseBodyView(
            tabId: _tabId,
            responseController: controller,
          ),
        ),
      ),
    ),
  );
  if (settle) await _settle(tester);
  return (tabs: tabsBloc, settings: settingsBloc);
}

/// Lets `compute`-based prettify/decode isolates finish (real async), then
/// flushes the resulting setStates — same pattern as the lazy-tree test.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await _settleResponseWork(tester);
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

// Isolate messages need real event-loop turns; fake-time pumpAndSettle alone
// cannot complete formatting followed by the viewer's background chunk index.
Future<void> _settleResponseWork(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.text('FORMATTING…').evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  group('Copy during JSON formatting', () {
    testWidgets(
      'copies current raw response before initial formatting finishes',
      (
        tester,
      ) async {
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);
        final clips = _mockClipboard(tester);
        await _pump(
          tester,
          body: '{"current":1}',
          controller: controller,
          settle: false,
        );
        expect(controller.text, isEmpty, reason: 'Formatting is still pending');
        await tester.tap(find.byTooltip('Copy response'));
        await tester.pump();
        expect(clips, ['{"current":1}']);
        // Assert clipboard contents before settling the snackbar entrance.
        await tester.pumpAndSettle();
        expect(find.text('Response copied').hitTestable(), findsOneWidget);

        await _settle(tester);
        await tester.tap(find.byTooltip('Copy response'));
        await tester.pump();
        expect(clips.last, '{\n    "current": 1\n}');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('copies new raw response instead of stale formatted response', (
      tester,
    ) async {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      final clips = _mockClipboard(tester);
      final harness = await _pump(
        tester,
        body: '{"old":1}',
        controller: controller,
      );
      harness.tabs.push(TabsState(tabs: [_tabWith('{"new":2}')]));
      await tester.pump();
      expect(
        controller.text,
        '{\n    "old": 1\n}',
        reason: 'The new response is still formatting in its isolate',
      );
      await tester.tap(find.byTooltip('Copy response'));
      await tester.pump();
      expect(clips, ['{"new":2}']);

      await _settle(tester);
      await tester.tap(find.byTooltip('Copy response'));
      await tester.pump();
      expect(clips.last, '{\n    "new": 2\n}');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('PRETTY / RAW toggle', () {
    testWidgets('RAW shows the verbatim body; PRETTY re-prettifies', (
      tester,
    ) async {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      await _pump(tester, body: '{"a":1}', controller: controller);

      expect(
        controller.text,
        contains('\n'),
        reason: 'PRETTY (default) renders prettified multi-line JSON',
      );

      await tester.tap(find.byKey(const ValueKey('body_toggle_RAW')));
      await _settle(tester);
      expect(controller.text, '{"a":1}');

      await tester.tap(find.byKey(const ValueKey('body_toggle_PRETTY')));
      await _settle(tester);
      expect(controller.text, contains('\n'));
      expect(controller.text, contains('"a"'));
    });

    testWidgets(
      'the over-1-MB placeholder stays verbatim and TREE is disabled',
      (tester) async {
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);
        await _pump(
          tester,
          body: kResponseBodyTooLargePlaceholder,
          controller: controller,
        );

        expect(controller.text, kResponseBodyTooLargePlaceholder);
        // Disabled TREE is wrapped in an explanatory Tooltip.
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey('body_toggle_TREE')),
            matching: find.byType(Tooltip),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('TREE decode fallbacks', () {
    testWidgets(
      'malformed JSON-looking body falls back to PRETTY with a snackbar',
      (tester) async {
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);
        await _pump(tester, body: '{oops!', controller: controller);

        // The cheap shape probe enables TREE optimistically…
        final treeFinder = find.byKey(const ValueKey('body_toggle_TREE'));
        expect(
          find.ancestor(of: treeFinder, matching: find.byType(Tooltip)),
          findsNothing,
        );

        // …but the real decode fails on tap and PRETTY takes back over.
        await tester.tap(treeFinder);
        await tester.pump();

        expect(find.text('Not a JSON object/array'), findsOneWidget);
        expect(find.byType(JsonCodeEditor), findsOneWidget);
        expect(
          find.ancestor(of: treeFinder, matching: find.byType(Tooltip)),
          findsOneWidget,
          reason: 'TREE must be disabled after the failed decode',
        );
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets('a JSON body over 64 KiB decodes off the UI isolate', (
      tester,
    ) async {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      // > kTreeInlineDecodeLimit but < kLargeResponseViewerChars.
      final body = '[${List.filled(5000, '"aaaaaaaaaaaaaa"').join(',')}]';
      assert(body.length > kTreeInlineDecodeLimit, 'must take compute path');
      assert(body.length < kLargeResponseViewerChars, 'must stay sub-large');
      await _pump(tester, body: body, controller: controller);

      await tester.tap(find.byKey(const ValueKey('body_toggle_TREE')));
      await tester.pump();
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: 'background decode shows a spinner first',
      );

      await _settle(tester);
      expect(find.text('[0]'), findsOneWidget);
    });
  });

  group('response / settings changes re-sync the body', () {
    testWidgets('a re-sent response with a new body updates the editor', (
      tester,
    ) async {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      final blocs = await _pump(
        tester,
        body: '{"a":1}',
        controller: controller,
      );

      blocs.tabs.push(TabsState(tabs: [_tabWith('{"b":2}')]));
      await _settle(tester);

      expect(controller.text, contains('"b"'));
      expect(controller.text, isNot(contains('"a"')));
    });

    testWidgets('a body change while viewing TREE re-decodes the tree', (
      tester,
    ) async {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      final blocs = await _pump(
        tester,
        body: '{"first":1}',
        controller: controller,
      );

      await tester.tap(find.byKey(const ValueKey('body_toggle_TREE')));
      await _settleResponseWork(tester);
      expect(find.text('first'), findsOneWidget);

      blocs.tabs.push(TabsState(tabs: [_tabWith('{"second":2}')]));
      await _settle(tester);

      expect(find.text('second'), findsOneWidget);
      expect(find.text('first'), findsNothing);
    });

    testWidgets(
      'a content-type flip to image reroutes to the media panel '
      'even when body text and bytes identity are unchanged',
      (tester) async {
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);
        final blocs = await _pump(
          tester,
          body: 'hello',
          controller: controller,
        );
        expect(find.byType(JsonCodeEditor), findsOneWidget);

        // Same body string, same (null) bodyBytes identity — only the
        // content-type header changes. The buildWhen gate must still fire.
        blocs.tabs.push(
          TabsState(
            tabs: [
              _tabWith('hello', headers: const {'content-type': 'image/png'}),
            ],
          ),
        );
        await _settleResponseWork(tester);

        expect(
          find.byKey(const ValueKey('media_preview_placeholder')),
          findsOneWidget,
          reason: 'image content-type without live bytes → media placeholder',
        );
        expect(find.byType(JsonCodeEditor), findsNothing);
      },
    );

    testWidgets(
      'flipping alwaysPrettifyLargeResponses re-renders the current body '
      'without a re-send',
      (tester) async {
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);
        final big = 'x' * (kLargeResponseViewerChars + 10);
        final blocs = await _pump(tester, body: big, controller: controller);

        expect(find.byType(LargeResponseTextView), findsOneWidget);
        expect(find.byType(JsonCodeEditor), findsNothing);

        blocs.settings.push(
          const SettingsState(
            settings: SettingsEntity(alwaysPrettifyLargeResponses: true),
          ),
        );
        await _settleResponseWork(tester);
        expect(find.byType(JsonCodeEditor), findsOneWidget);
        expect(find.byType(LargeResponseTextView), findsNothing);

        blocs.settings.push(
          const SettingsState(settings: SettingsEntity()),
        );
        await _settleResponseWork(tester);
        expect(find.byType(LargeResponseTextView), findsOneWidget);
        expect(find.byType(JsonCodeEditor), findsNothing);
      },
    );
  });

  group('11.3 MB response regression', () {
    testWidgets('prettify formats the full JSON without loading the editor', (
      tester,
    ) async {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      final clips = _mockClipboard(tester);
      final body = '{"description":"${'x' * 11300000}","total":42}';
      await _pump(tester, body: body, controller: controller);
      await tester.tap(find.text('PRETTIFY ANYWAY'));
      await tester.pump();
      // Real isolate completion, bounded wait; no frame-time assertion in CI.
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (find.text('PRETTIFY ANYWAY').evaluate().isEmpty &&
            find.text('FORMATTING…').evaluate().isEmpty) {
          break;
        }
      }
      await tester.tap(find.byTooltip('Copy response'));
      await tester.pump();
      expect(
        clips.single.substring(0, 24),
        startsWith('{\n    "description":'),
      );
      expect(
        clips.single.substring(clips.single.length - 20),
        endsWith('"total": 42\n}'),
      );
      expect(controller.text, isEmpty);
      expect(find.byType(JsonCodeEditor), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
      'plain preview never lays out the entire preview as one paragraph',
      (
        tester,
      ) async {
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);
        await _pump(
          tester,
          body: '{"description":"${'x' * 11300000}"}',
          controller: controller,
        );
        final chunks = find.descendant(
          of: find.byType(LargeResponseTextView),
          matching: find.byType(Text),
        );
        final paragraphs = tester.widgetList<Text>(chunks).toList();
        expect(paragraphs, isNotEmpty);
        expect(
          paragraphs.every((text) => text.data!.length <= 4096),
          isTrue,
          reason: 'A single 256 KiB paragraph blocks layout and search opening',
        );
        expect(
          paragraphs.fold<int>(0, (sum, text) => sum + text.data!.length),
          lessThan(20000),
        );
      },
    );
  });

  group('large plain-text mode', () {
    testWidgets('Copy copies the full verbatim body, not the preview', (
      tester,
    ) async {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      final clips = _mockClipboard(tester);
      final big = 'x' * (kLargeResponseViewerChars + 123);
      await _pump(tester, body: big, controller: controller);

      await tester.tap(find.byTooltip('Copy response'));
      await tester.pump();

      expect(clips, hasLength(1));
      expect(clips.single.length, big.length);
      expect(find.text('Response copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('SHOW FULL reveals the whole body', (tester) async {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      final big = 'x' * (kLargeResponseViewerChars + 5);
      await _pump(tester, body: big, controller: controller);

      String shownText() => tester
          .widget<LargeResponseTextView>(find.byType(LargeResponseTextView))
          .text;
      expect(shownText().length, kLargeResponsePreviewChars);

      await tester.tap(find.text('SHOW FULL'));
      await _settleResponseWork(tester);

      expect(shownText().length, big.length);
      expect(find.text('SHOW FULL'), findsNothing);
    });

    testWidgets('alwaysPrettify formats JSON above the highlighting cap', (
      tester,
    ) async {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      final huge = '{"value":"${'x' * (kMaxHighlightChars + 10)}"}';
      await _pump(
        tester,
        body: huge,
        controller: controller,
        settings: const SettingsEntity(alwaysPrettifyLargeResponses: true),
      );
      for (
        var i = 0;
        i < 200 && find.text('FORMATTING…').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      final view = tester.widget<LargeResponseTextView>(
        find.byType(LargeResponseTextView),
      );
      expect(view.text.substring(0, 20), startsWith('{\n    "value":'));
      expect(controller.text, isEmpty);
      expect(find.byType(JsonCodeEditor), findsNothing);
      expect(find.text('PRETTIFY ANYWAY'), findsNothing);
    });

    testWidgets('formatted output above the cap never enters the editor', (
      tester,
    ) async {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      // Input <3 MiB, formatted output >3 MiB: the guard must use output size.
      final body = '[${List.filled(500000, '0').join(',')}]';
      await _pump(tester, body: body, controller: controller);
      await tester.tap(find.text('PRETTIFY ANYWAY'));
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (find.text('FORMATTING…').evaluate().isEmpty) break;
      }
      expect(find.byType(JsonCodeEditor), findsNothing);
      expect(controller.text, isEmpty);
      expect(
        tester
            .widget<LargeResponseTextView>(find.byType(LargeResponseTextView))
            .text
            .length,
        greaterThan(kMaxHighlightChars),
      );
    });

    testWidgets(
      'no prettify-cap note when the setting is off',
      (tester) async {
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);
        final huge = 'x' * (kMaxHighlightChars + 10);
        await _pump(tester, body: huge, controller: controller);

        expect(
          find.byKey(const ValueKey('prettify_cap_note')),
          findsNothing,
        );
      },
    );

    testWidgets('PRETTIFY ANYWAY under the cap opts into the editor', (
      tester,
    ) async {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      final big = 'x' * (kLargeResponseViewerChars + 10);
      await _pump(tester, body: big, controller: controller);

      await tester.tap(find.text('PRETTIFY ANYWAY'));
      await _settle(tester);

      expect(find.byType(JsonCodeEditor), findsOneWidget);
      expect(find.textContaining('HIGHLIGHTING ENABLED'), findsOneWidget);
      expect(find.text('PRETTIFY ANYWAY'), findsNothing);
    });
  });

  group('editor controller replacement', () {
    testWidgets('a swapped-in controller keeps find working', (tester) async {
      final controllerA = CodeLineEditingController();
      addTearDown(controllerA.dispose);
      await _pump(tester, body: '{"a":1}', controller: controllerA);

      // Re-pump the same tree with a fresh controller — the state must
      // rebuild its CodeFindController over the new editor controller.
      final controllerB = CodeLineEditingController();
      addTearDown(controllerB.dispose);
      await _pump(tester, body: '{"a":1}', controller: controllerB);

      await tester.tap(find.byKey(const ValueKey('response_find_button')));
      await _settleResponseWork(tester);

      expect(
        find.descendant(
          of: find.byType(CodeFindPanel),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );
    });
  });
}
