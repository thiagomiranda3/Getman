import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_event.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_state.dart';
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
import 'package:getman/features/tabs/presentation/widgets/response/response_body_view.dart';
import 'package:re_editor/re_editor.dart';

// Lightweight fake blocs that only expose `state`. The pushable ones let a
// test simulate a re-send / setting flip after the initial pump.
class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initialState);

  void push(TabsState next) => emit(next);

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

  void push(SettingsState next) => emit(next);
}

class _FakeRulesBloc extends Bloc<RulesEvent, RulesState> implements RulesBloc {
  _FakeRulesBloc() : super(const RulesState());
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
        BlocProvider<RulesBloc>(create: (_) => _FakeRulesBloc()),
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
  await _settle(tester);
  return (tabs: tabsBloc, settings: settingsBloc);
}

/// Lets `compute`-based prettify/decode isolates finish (real async), then
/// flushes the resulting setStates — same pattern as the lazy-tree test.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
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
      await tester.pumpAndSettle();
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
        await tester.pumpAndSettle();

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

        expect(find.byType(SelectableText), findsOneWidget);
        expect(find.byType(JsonCodeEditor), findsNothing);

        blocs.settings.push(
          const SettingsState(
            settings: SettingsEntity(alwaysPrettifyLargeResponses: true),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(JsonCodeEditor), findsOneWidget);
        expect(find.byType(SelectableText), findsNothing);

        blocs.settings.push(
          const SettingsState(settings: SettingsEntity()),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsOneWidget);
        expect(find.byType(JsonCodeEditor), findsNothing);
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

      String shownText() =>
          tester.widget<SelectableText>(find.byType(SelectableText)).data!;
      expect(shownText().length, kLargeResponsePreviewChars);

      await tester.tap(find.text('SHOW FULL'));
      await tester.pumpAndSettle();

      expect(shownText().length, big.length);
      expect(find.text('SHOW FULL'), findsNothing);
    });

    testWidgets(
      'PRETTIFY ANYWAY on an over-3-MB body refuses with a snackbar',
      (tester) async {
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);
        final huge = 'x' * (kMaxHighlightChars + 10);
        await _pump(tester, body: huge, controller: controller);

        await tester.tap(find.text('PRETTIFY ANYWAY'));
        await tester.pump();

        expect(
          find.text(
            'Body too large to highlight (over 3 MB) — showing plain text',
          ),
          findsOneWidget,
        );
        expect(find.byType(SelectableText), findsOneWidget);
        expect(find.byType(JsonCodeEditor), findsNothing);
        await tester.pump(const Duration(seconds: 3));
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
      await tester.pumpAndSettle();

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
