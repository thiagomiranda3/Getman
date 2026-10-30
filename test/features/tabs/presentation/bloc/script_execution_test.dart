import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';
import 'package:getman/features/tabs/domain/entities/execute_request_result.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/script_execution_harness.dart';

class _Repository extends Mock implements TabsRepository {}

class _Bloc extends TabsBloc {
  _Bloc({
    required super.repository,
    required super.sendRequestUseCase,
    required super.executeRequestUseCase,
  });
  final completions = <Completer<void>>[];
  final canceled = Completer<void>();
  @override
  void onDone(TabsEvent event, [Object? error, StackTrace? stackTrace]) {
    super.onDone(event, error, stackTrace);
    if (event is SendRequest && completions.isNotEmpty) {
      completions.removeAt(0).complete();
    }
    if (event is CancelRequest && !canceled.isCompleted) canceled.complete();
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const HttpRequestTabEntity(
        config: HttpRequestConfigEntity(id: 'fallback'),
        tabId: 'fallback',
      ),
    );
    registerFallbackValue(
      const PanelEntity(
        id: 'fallback',
        name: 'Panel',
        tabs: [],
        activeTabId: '',
      ),
    );
  });
  late ScriptExecutionHarness h;
  late _Repository repository;
  late _Bloc bloc;
  Future<void> load({String pre = 'before', String post = ''}) async {
    h = ScriptExecutionHarness();
    repository = _Repository();
    when(() => repository.putTab(any())).thenAnswer((_) async {});
    when(() => repository.putPanel(any())).thenAnswer((_) async {});
    when(() => repository.savePanelMeta(any(), any())).thenAnswer((_) async {});
    when(() => repository.deleteTabs(any())).thenAnswer((_) async {});
    when(() => repository.getPanels()).thenAnswer(
      (_) async => [
        PanelEntity(
          id: 'panel',
          name: 'Panel',
          tabs: [
            HttpRequestTabEntity(
              tabId: 'tab',
              config: HttpRequestConfigEntity(
                id: 'request',
                scripts: RequestScripts(preRequest: pre, postResponse: post),
              ),
            ),
          ],
          activeTabId: 'tab',
        ),
      ],
    );
    when(() => repository.getActivePanelId()).thenAnswer((_) async => 'panel');
    bloc = _Bloc(
      repository: repository,
      sendRequestUseCase: h.network,
      executeRequestUseCase: h.execute,
    )..add(const LoadTabs());
    await bloc.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
  }

  for (final close in [false, true]) {
    test(
      '${close ? 'closing' : 'canceling'} during pre prevents HTTP and results',
      () async {
        await load();
        final started = Completer<void>();
        final output = Completer<ScriptOutput>();
        h.runtime.run = (_) {
          started.complete();
          return output.future;
        };
        final done = Completer<void>();
        bloc.completions.add(done);
        bloc.add(const SendRequest(tabId: 'tab'));
        await started.future;
        if (close) {
          bloc.add(const RemoveTab('tab'));
          await bloc.stream.firstWhere(
            (s) => s.tabs.every((t) => t.tabId != 'tab'),
          );
        } else {
          bloc.add(const CancelRequest('tab'));
          await bloc.canceled.future;
          expect(bloc.state.tabs.single.isSending, isFalse);
        }
        output.complete(
          ScriptOutput(environmentPatch: ScriptPatch(sets: const {'x': '1'})),
        );
        await done.future;
        expect(h.networkCalls, 0);
        expect(h.environment.values, isEmpty);
        if (!close) {
          expect(
            bloc.state.tabs.single.scriptExecutionResult?.cancelled,
            isTrue,
          );
        }
        await bloc.close();
      },
    );
  }
  test(
    'pre results publish while HTTP is pending and phase remains sending',
    () async {
      await load();
      final network = Completer<HttpResponseEntity>();
      final observed = Completer<void>();
      h.network.network = () {
        observed.complete();
        return network.future;
      };
      h.runtime.run = (_) async => ScriptOutput();
      final done = Completer<void>();
      bloc.completions.add(done);
      bloc.add(const SendRequest(tabId: 'tab'));
      await observed.future;
      expect(bloc.state.tabs.single.isSending, isTrue);
      expect(
        bloc.state.tabs.single.scriptExecutionPhase,
        ScriptExecutionPhase.network,
      );
      expect(
        bloc.state.tabs.single.scriptExecutionResult?.preRequest,
        isNotNull,
      );
      bloc.add(const CancelRequest('tab'));
      await bloc.canceled.future;
      // A late network completion cannot publish into the canceled tab.
      network.completeError(StateError('late'));
      await done.future;
      expect(bloc.state.tabs.single.isSending, isFalse);
      expect(bloc.state.tabs.single.response, isNull);
      await bloc.close();
    },
  );
  test(
    'resend after cancel retains new result when old worker completes',
    () async {
      await load();
      final started = Completer<void>();
      final oldOutput = Completer<ScriptOutput>();
      h.runtime.run = (input) {
        if (input.source == 'before') {
          started.complete();
          return oldOutput.future;
        }
        return Future.value(ScriptOutput());
      };
      final firstDone = Completer<void>();
      final secondDone = Completer<void>();
      bloc.completions.addAll([firstDone, secondDone]);
      bloc.add(const SendRequest(tabId: 'tab'));
      await started.future;
      final oldId = bloc.state.tabs.single.executionId;
      bloc.add(const CancelRequest('tab'));
      await bloc.canceled.future;
      bloc.add(
        UpdateTab(
          bloc.state.tabs.single.copyWith(
            config: bloc.state.tabs.single.config.copyWith(
              scripts: const RequestScripts(preRequest: 'after'),
            ),
          ),
        ),
      );
      await bloc.stream.firstWhere(
        (state) => state.tabs.single.config.scripts.preRequest == 'after',
      );
      bloc.add(const SendRequest(tabId: 'tab'));
      await firstDone.future;
      final currentId = bloc.state.tabs.single.executionId;
      expect(currentId, isNot(oldId));
      expect(bloc.state.tabs.single.response?.body, 'ok');
      oldOutput.complete(
        ScriptOutput(
          environmentPatch: ScriptPatch(sets: const {'stale': 'bad'}),
        ),
      );
      await secondDone.future;
      expect(bloc.state.tabs.single.executionId, currentId);
      expect(h.environment.values, isEmpty);
      expect(h.networkCalls, 1);
      await bloc.close();
    },
  );
}
