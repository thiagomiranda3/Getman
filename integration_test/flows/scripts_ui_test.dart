// Real app authoring and SEND through the editor input client.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/ui/widgets/branded_tab_bar.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/actions.dart';
import '../support/app_harness.dart';
import '../support/mock_server.dart';
import '../support/script_actions.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerScriptUiContracts();
}

void registerScriptUiContracts() {
  patrolWidgetTest(
    'authored post script shows isolated tests and console in real app',
    ($) async {
      final server = await MockServer.start(
        responder: (request) {
          request.response.headers.set('X-Trace', 'trace-42');
          request.response.write('{"nullable":null}');
        },
      );
      addTearDown(server.close);
      await bootGetman($);
      await enterUrl($, server.baseUrl);
      await openRequestTab($, 'SCRIPTS');
      await $('POST-RESPONSE').tap();
      final source = await loadScriptFixture('response_tests_post.js');
      final editor = find
          .byKey(const ValueKey('script_editor_post'))
          .hitTestable();
      await _insertScriptThroughInputClient($, editor, source);
      await $.tester.pump();
      final bloc = di.sl<TabsBloc>();
      expect(
        bloc.state.tabs[bloc.state.activeIndex].config.scripts.postResponse,
        source,
      );
      await tapSend($);
      for (var i = 0; i < 200; i++) {
        await $.tester.pump(const Duration(milliseconds: 25));
        final tab = bloc.state.tabs[bloc.state.activeIndex];
        if (tab.executionId != null &&
            !tab.isSending &&
            tab.scriptExecutionResult != null) {
          break;
        }
      }
      final tab = bloc.state.tabs[bloc.state.activeIndex];
      expect(tab.executionId, isNotNull);
      expect(tab.scriptExecutionResult?.error, isNull);
      expect(server.received.length, 1);
      await openResponseTab($, 'TESTS');
      expect(
        find.textContaining('Falha intencional').hitTestable(),
        findsOneWidget,
      );
      expect(
        find.textContaining('Continua após falha').hitTestable(),
        findsOneWidget,
      );
      await openResponseTab($, 'CONSOLE');
      expect(
        find.textContaining('Resposta verificada').hitTestable(),
        findsOneWidget,
      );
    },
  );

  patrolWidgetTest('compact pre failure focuses visible console without HTTP', (
    $,
  ) async {
    final server = await MockServer.start();
    addTearDown(server.close);

    await bootGetman($, windowSize: const Size(560, 900));

    final environments = di.sl<EnvironmentsRepository>();
    await environments.putEnvironment(
      EnvironmentEntity(id: 'script-ui-env', name: 'Script profile'),
    );
    await $.tester.pump();
    await $.tester.pump();
    await openEnvironmentSelector($);
    await $('Script profile').tap();
    await enterUrl($, server.baseUrl);
    await $('SCRIPTS').tap();
    final source = await loadScriptFixture('pre_failure.js');

    final editor = find
        .byKey(const ValueKey('script_editor_pre'))
        .hitTestable();
    await _insertScriptThroughInputClient($, editor, source);
    await $.tester.pump();
    final bloc = di.sl<TabsBloc>();
    expect(
      bloc.state.tabs[bloc.state.activeIndex].config.scripts.preRequest,
      source,
    );
    await tapSend($);
    for (var i = 0; i < 200; i++) {
      await $.tester.pump(const Duration(milliseconds: 25));
      final tab = bloc.state.tabs[bloc.state.activeIndex];
      if (tab.executionId != null &&
          !tab.isSending &&
          tab.scriptExecutionResult != null) {
        break;
      }
    }

    expect(server.received, isEmpty);
    expect(bloc.state.tabs[bloc.state.activeIndex].response, isNull);
    expect(
      bloc
          .state
          .tabs[bloc.state.activeIndex]
          .scriptExecutionResult
          ?.error
          ?.kind,
      ScriptErrorKind.runtime,
      reason: bloc
          .state
          .tabs[bloc.state.activeIndex]
          .scriptExecutionResult
          ?.error
          ?.message,
    );
    expect(
      bloc
          .state
          .tabs[bloc.state.activeIndex]
          .scriptExecutionResult
          ?.error
          ?.message,
      contains('Preparação interrompida'),
    );
    // Start the listener's animation tick before advancing its elapsed time.
    await $.tester.pump();
    final strip = $.tester
        .widgetList<BrandedTabBar>(find.byType(BrandedTabBar))
        .firstWhere((bar) => bar.labels.contains('RESPONSE'));
    expect(strip.controller!.index, 5);
    await $.tester.pump(const Duration(milliseconds: 500));
    expect(
      find.textContaining('Preparação interrompida').hitTestable(),
      findsOneWidget,
      reason: find
          .byType(Text)
          .hitTestable()
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .join(' | '),
    );
    expect(find.textContaining('at line 2').hitTestable(), findsOneWidget);
    expect((await environments.getEnvironments()).single.variables, isEmpty);
  });
}

// re_editor uses DeltaTextInputClient; updateEditingState is intentionally a
// no-op there. Send the same insertion delta a native keyboard/paste produces.
Future<void> _insertScriptThroughInputClient(
  PatrolTester $,
  Finder editor,
  String source,
) async {
  final input = $.tester.testTextInput..register();
  addTearDown(input.unregister);
  await $(editor).tap(settlePolicy: SettlePolicy.noSettle);
  for (var frame = 0; frame < 20 && !input.hasAnyClients; frame++) {
    await $.tester.pump(const Duration(milliseconds: 10));
  }
  expect(input.hasAnyClients, isTrue, reason: 'Script editor must own input');
  expect(input.setClientArgs?['enableDeltaModel'], isTrue);
  final client =
      (input.log
                      .lastWhere((call) => call.method == 'TextInput.setClient')
                      .arguments
                  as List<dynamic>)
              .first
          as int;
  final oldText = input.editingState?['text'] as String? ?? '';

  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        SystemChannels.textInput.name,
        SystemChannels.textInput.codec.encodeMethodCall(
          MethodCall('TextInputClient.updateEditingStateWithDeltas', [
            client,
            {
              'deltas': [
                {
                  'oldText': oldText,
                  'deltaText': source,
                  'deltaStart': 0,
                  'deltaEnd': oldText.length,
                  'selectionBase': source.length,
                  'selectionExtent': source.length,
                  'composingBase': -1,
                  'composingExtent': -1,
                },
              ],
            },
          ]),
        ),
        (_) {},
      );
  await $.tester.pump();
  await $.tester.pump();
}
