// Widget tests for QuickEnvSwitcher: lists No Environment + every env, marks +
// pre-highlights the active row, navigates with arrows, selects with Enter/tap,
// and dispatches UpdateActiveEnvironmentId on the held SettingsBloc.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/widgets/quick_env_switcher.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:mocktail/mocktail.dart';

class MockSettingsBloc extends Mock implements SettingsBloc {}

void main() {
  late MockSettingsBloc settings;

  final envs = [
    EnvironmentEntity(id: 'e1', name: 'Production'),
    EnvironmentEntity(id: 'e2', name: 'Staging'),
  ];

  setUpAll(() {
    registerFallbackValue(const UpdateActiveEnvironmentId(null));
  });

  setUp(() {
    settings = MockSettingsBloc();
    when(() => settings.add(any())).thenReturn(null);
  });

  Future<void> pump(
    WidgetTester tester, {
    required List<EnvironmentEntity> environments,
    required String? activeId,
  }) async {
    // Mount the switcher as a pushed route (mirroring showResponsiveDialog) so
    // its Navigator.maybePop() on select actually unmounts the widget — a
    // direct Scaffold-body pump leaves nothing to pop and the dismissal
    // assertions can't be observed.
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: QuickEnvSwitcher(
                        environments: environments,
                        activeId: activeId,
                        settingsBloc: settings,
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists No Environment plus every environment', (tester) async {
    await pump(tester, environments: envs, activeId: 'e1');
    expect(find.text('No Environment'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Staging'), findsOneWidget);
    expect(find.text('SWITCH ENVIRONMENT'), findsOneWidget);
  });

  testWidgets('active row shows the check marker', (tester) async {
    await pump(tester, environments: envs, activeId: 'e2');
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('Enter on open selects the pre-highlighted active row', (
    tester,
  ) async {
    // Active is e2 (Staging) → it opens pre-highlighted, so a bare Enter
    // re-selects e2 and pops.
    await pump(tester, environments: envs, activeId: 'e2');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    verify(
      () => settings.add(
        any(
          that: isA<UpdateActiveEnvironmentId>().having(
            (e) => e.id,
            'id',
            'e2',
          ),
        ),
      ),
    ).called(1);
    expect(find.byType(QuickEnvSwitcher), findsNothing);
  });

  testWidgets('ArrowUp from the active row reaches No Environment (null)', (
    tester,
  ) async {
    // Rows: [No Environment, Production(e1), Staging(e2)]. Active e1 opens at
    // index 1; one ArrowUp moves to No Environment; Enter dispatches null.
    await pump(tester, environments: envs, activeId: 'e1');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    verify(
      () => settings.add(
        any(
          that: isA<UpdateActiveEnvironmentId>().having(
            (e) => e.id,
            'id',
            null,
          ),
        ),
      ),
    ).called(1);
    expect(find.byType(QuickEnvSwitcher), findsNothing);
  });

  testWidgets('ArrowDown then Enter selects the next environment', (
    tester,
  ) async {
    // Active e1 opens at index 1 (Production); ArrowDown → index 2 (Staging,
    // e2); Enter dispatches e2.
    await pump(tester, environments: envs, activeId: 'e1');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    verify(
      () => settings.add(
        any(
          that: isA<UpdateActiveEnvironmentId>().having(
            (e) => e.id,
            'id',
            'e2',
          ),
        ),
      ),
    ).called(1);
  });

  testWidgets('tapping a row dispatches the same event as Enter on it', (
    tester,
  ) async {
    await pump(tester, environments: envs, activeId: null);
    await tester.tap(find.text('Staging'));
    await tester.pumpAndSettle();
    verify(
      () => settings.add(
        any(
          that: isA<UpdateActiveEnvironmentId>().having(
            (e) => e.id,
            'id',
            'e2',
          ),
        ),
      ),
    ).called(1);
    expect(find.byType(QuickEnvSwitcher), findsNothing);
  });

  testWidgets('no saved environments still renders just No Environment', (
    tester,
  ) async {
    await pump(tester, environments: const [], activeId: null);
    expect(find.text('No Environment'), findsOneWidget);
    expect(find.text('Production'), findsNothing);
    await tester.tap(find.text('No Environment'));
    await tester.pumpAndSettle();
    verify(
      () => settings.add(
        any(
          that: isA<UpdateActiveEnvironmentId>().having(
            (e) => e.id,
            'id',
            null,
          ),
        ),
      ),
    ).called(1);
  });

  testWidgets('stale active id falls back to No Environment highlight', (
    tester,
  ) async {
    // activeId points at a deleted env → no row matches → highlight falls back
    // to index 0 (No Environment). Enter dispatches null.
    await pump(tester, environments: envs, activeId: 'gone');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    verify(
      () => settings.add(
        any(
          that: isA<UpdateActiveEnvironmentId>().having(
            (e) => e.id,
            'id',
            null,
          ),
        ),
      ),
    ).called(1);
  });
}
