import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/extraction_result.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/chaining/presentation/widgets/chaining_write_back_listener.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:mocktail/mocktail.dart';

class MockTabsBloc extends Mock implements TabsBloc {}

class MockEnvironmentsBloc extends Mock implements EnvironmentsBloc {}

class MockSettingsBloc extends Mock implements SettingsBloc {}

void main() {
  setUpAll(
    () =>
        registerFallbackValue(UpdateEnvironment(EnvironmentEntity(name: 'x'))),
  );

  late MockTabsBloc tabsBloc;
  late MockEnvironmentsBloc envBloc;
  late MockSettingsBloc settingsBloc;
  late StreamController<TabsState> tabsStream;
  late StreamController<SettingsState> settingsStream;

  const tabId = 't1';
  HttpRequestTabEntity tabWith(List<ExtractionResult> results) =>
      HttpRequestTabEntity(
        tabId: tabId,
        config: const HttpRequestConfigEntity(id: tabId),
        extractionResults: results,
      );

  setUp(() {
    tabsStream = StreamController<TabsState>.broadcast();
    tabsBloc = MockTabsBloc();
    when(() => tabsBloc.stream).thenAnswer((_) => tabsStream.stream);
    when(() => tabsBloc.state).thenReturn(TabsState(tabs: [tabWith(const [])]));

    envBloc = MockEnvironmentsBloc();
    when(() => envBloc.add(any())).thenReturn(null);

    settingsStream = StreamController<SettingsState>.broadcast();
    settingsBloc = MockSettingsBloc();
    when(() => settingsBloc.stream).thenAnswer((_) => settingsStream.stream);
  });

  tearDown(() {
    unawaited(tabsStream.close());
    unawaited(settingsStream.close());
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: RepositoryProvider<EnvironmentsBloc>.value(
            value: envBloc,
            child: RepositoryProvider<SettingsBloc>.value(
              value: settingsBloc,
              child: BlocProvider<TabsBloc>.value(
                value: tabsBloc,
                child: const ChainingWriteBackListener(child: SizedBox()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('writes captured values into the active environment', (
    tester,
  ) async {
    when(() => settingsBloc.state).thenReturn(
      const SettingsState(settings: SettingsEntity(activeEnvironmentId: 'e1')),
    );
    when(() => envBloc.state).thenReturn(
      EnvironmentsState(
        environments: [
          EnvironmentEntity(
            id: 'e1',
            name: 'Prod',
            variables: const {'old': '1'},
          ),
        ],
      ),
    );

    await pump(tester);

    tabsStream.add(
      TabsState(
        tabs: [
          tabWith(const [
            ExtractionResult(variable: 'tok', value: 'abc', matched: true),
          ]),
        ],
      ),
    );
    await tester.pump();

    final event =
        verify(() => envBloc.add(captureAny())).captured.single
            as UpdateEnvironment;
    expect(event.environment.id, 'e1');
    expect(event.environment.variables, {'old': '1', 'tok': 'abc'});
  });

  testWidgets(
    'writes captured values from a NON-active tab '
    '(user switched away mid-flight)',
    (tester) async {
      // Two tabs; tab B (index 1) is the active one. Tab A's request is still
      // in flight when the user switches to B, then A returns with a capture.
      HttpRequestTabEntity tab(String id, List<ExtractionResult> results) =>
          HttpRequestTabEntity(
            tabId: id,
            config: HttpRequestConfigEntity(id: id),
            extractionResults: results,
          );
      when(() => tabsBloc.state).thenReturn(
        TabsState(
          tabs: [tab('A', const []), tab('B', const [])],
          activeIndex: 1,
        ),
      );
      when(() => settingsBloc.state).thenReturn(
        const SettingsState(
          settings: SettingsEntity(activeEnvironmentId: 'e1'),
        ),
      );
      when(() => envBloc.state).thenReturn(
        EnvironmentsState(
          environments: [EnvironmentEntity(id: 'e1', name: 'Prod')],
        ),
      );

      await pump(tester);

      tabsStream.add(
        TabsState(
          tabs: [
            tab('A', const [
              ExtractionResult(variable: 'tok', value: 'fromA', matched: true),
            ]),
            tab('B', const []),
          ],
          activeIndex: 1,
        ),
      );
      await tester.pump();

      final event =
          verify(() => envBloc.add(captureAny())).captured.single
              as UpdateEnvironment;
      expect(event.environment.id, 'e1');
      expect(
        event.environment.variables,
        {'tok': 'fromA'},
        reason:
            'capture on the non-active tab must still reach the active '
            'environment',
      );
    },
  );

  testWidgets('does not re-write an unchanged capture on a later emission', (
    tester,
  ) async {
    when(() => settingsBloc.state).thenReturn(
      const SettingsState(settings: SettingsEntity(activeEnvironmentId: 'e1')),
    );
    when(() => envBloc.state).thenReturn(
      EnvironmentsState(
        environments: [EnvironmentEntity(id: 'e1', name: 'Prod')],
      ),
    );

    await pump(tester);

    const results = [
      ExtractionResult(variable: 'tok', value: 'abc', matched: true),
    ];
    tabsStream.add(TabsState(tabs: [tabWith(results)]));
    await tester.pump();
    // An unrelated emission carrying the SAME capture must not write again.
    tabsStream.add(TabsState(tabs: [tabWith(results)]));
    await tester.pump();

    verify(() => envBloc.add(any())).called(1);
  });

  testWidgets(
    'a capture made with no active environment is written once one is '
    'selected later',
    (tester) async {
      // Start with NO active environment.
      var settings = const SettingsState(settings: SettingsEntity());
      when(() => settingsBloc.state).thenAnswer((_) => settings);
      when(() => envBloc.state).thenReturn(
        EnvironmentsState(
          environments: [EnvironmentEntity(id: 'e1', name: 'Prod')],
        ),
      );

      await pump(tester);

      final captureState = TabsState(
        tabs: [
          tabWith(const [
            ExtractionResult(variable: 'tok', value: 'abc', matched: true),
          ]),
        ],
      );
      when(
        () => tabsBloc.state,
      ).thenReturn(captureState); // _flush reads the live state
      tabsStream.add(captureState);
      await tester.pump();

      // No environment yet → nothing persisted, but the capture must NOT be
      // lost.
      verifyNever(() => envBloc.add(any()));

      // User now selects an environment (emits on SettingsBloc only — no new
      // TabsState).
      settings = const SettingsState(
        settings: SettingsEntity(activeEnvironmentId: 'e1'),
      );
      settingsStream.add(settings);
      await tester.pump();

      final event =
          verify(() => envBloc.add(captureAny())).captured.single
              as UpdateEnvironment;
      expect(event.environment.id, 'e1');
      expect(
        event.environment.variables,
        {'tok': 'abc'},
        reason:
            'the pending capture is flushed when an environment becomes active',
      );
    },
  );

  testWidgets('with no active environment, nothing is written', (tester) async {
    when(
      () => settingsBloc.state,
    ).thenReturn(const SettingsState(settings: SettingsEntity()));
    when(() => envBloc.state).thenReturn(const EnvironmentsState());

    await pump(tester);

    tabsStream.add(
      TabsState(
        tabs: [
          tabWith(const [
            ExtractionResult(variable: 'tok', value: 'abc', matched: true),
          ]),
        ],
      ),
    );
    await tester.pump();

    verifyNever(() => envBloc.add(any()));
  });
}
