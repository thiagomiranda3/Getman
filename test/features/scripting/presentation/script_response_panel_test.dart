// Script stage progress stays inspectable before HTTP has returned.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/scripting/domain/entities/script_error.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/execute_request_result.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';
import 'package:getman/features/tabs/presentation/widgets/response_section.dart';
import 'package:getman/features/tabs/presentation/widgets/unified_request_panel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

class _Tabs extends Mock implements TabsBloc {}

class _Settings extends Mock implements SettingsBloc {}

void main() {
  testWidgets('compact layout opens response diagnostics on pre-HTTP failure', (
    tester,
  ) async {
    final tabs = _Tabs();
    const tab = HttpRequestTabEntity(
      config: HttpRequestConfigEntity(id: 'request'),
      tabId: 'tab',
      isSending: true,
    );
    var state = const TabsState(tabs: [tab]);
    final stream = StreamController<TabsState>.broadcast();
    addTearDown(stream.close);
    when(() => tabs.state).thenAnswer((_) => state);
    when(() => tabs.stream).thenAnswer((_) => stream.stream);
    final section = RequestSectionIndex()..value = 4;
    addTearDown(section.dispose);
    final body = CodeLineEditingController();
    final variables = CodeLineEditingController();
    final response = CodeLineEditingController();
    addTearDown(body.dispose);
    addTearDown(variables.dispose);
    addTearDown(response.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: BlocProvider<TabsBloc>.value(
          value: tabs,
          child: ChangeNotifierProvider<RequestSectionIndex>.value(
            value: section,
            child: Scaffold(
              body: UnifiedRequestPanel(
                tabId: 'tab',
                bodyController: body,
                variablesController: variables,
                responseController: response,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // The real pipeline publishes a failed stage before ending the request.
    const result = ExecuteRequestResult(
      error: ScriptError(
        kind: ScriptErrorKind.syntax,
        phase: ScriptPhase.preRequest,
        message: 'invalid syntax',
        line: 2,
      ),
    );
    state = TabsState(tabs: [tab.copyWith(scriptExecutionResult: result)]);
    stream.add(state);
    await tester.pump();
    state = TabsState(
      tabs: [
        tab.copyWith(
          isSending: false,
          scriptExecutionResult: result,
        ),
      ],
    );
    stream.add(state);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('line 2').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'pre-request failure opens its visible diagnostic on first frame',
    (tester) async {
      final tabs = _Tabs();
      when(() => tabs.state).thenReturn(
        const TabsState(
          tabs: [
            HttpRequestTabEntity(
              config: HttpRequestConfigEntity(id: 'request'),
              tabId: 'tab',
              scriptExecutionResult: ExecuteRequestResult(
                error: ScriptError(
                  kind: ScriptErrorKind.syntax,
                  phase: ScriptPhase.preRequest,
                  message: 'invalid syntax',
                  line: 2,
                ),
              ),
            ),
          ],
        ),
      );
      when(
        () => tabs.stream,
      ).thenAnswer((_) => const Stream<TabsState>.empty());
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: BlocProvider<TabsBloc>.value(
            value: tabs,
            child: Scaffold(
              body: ResponseSection(
                tabId: 'tab',
                responseController: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('line 2').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'in-flight script result keeps console accessible without response',
    (tester) async {
      final tabs = _Tabs();
      final settings = _Settings();
      when(() => tabs.state).thenReturn(
        const TabsState(
          tabs: [
            HttpRequestTabEntity(
              config: HttpRequestConfigEntity(id: 'request'),
              tabId: 'tab',
              isSending: true,
              scriptExecutionPhase: ScriptExecutionPhase.postResponse,
              scriptExecutionResult: ExecuteRequestResult(),
            ),
          ],
        ),
      );
      when(
        () => tabs.stream,
      ).thenAnswer((_) => const Stream<TabsState>.empty());
      when(() => settings.state).thenReturn(SettingsState.initial());
      when(
        () => settings.stream,
      ).thenAnswer((_) => const Stream<SettingsState>.empty());
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<TabsBloc>.value(value: tabs),
              BlocProvider<SettingsBloc>.value(value: settings),
            ],
            child: Scaffold(
              body: ResponseSection(
                tabId: 'tab',
                responseController: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('RUNNING POST-RESPONSE'), findsOneWidget);
      expect(find.text('CONSOLE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
    },
  );
}
