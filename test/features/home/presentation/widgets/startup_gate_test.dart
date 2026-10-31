import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/home/presentation/widgets/startup_gate.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('first frame uses saved appearance before services start', (
    tester,
  ) async {
    final ready = Completer<Widget>();
    var starts = 0;
    await tester.pumpWidget(
      StartupGate(
        settings: const SettingsEntity(themeId: 'dracula', isDarkMode: true),
        initialize: () {
          starts++;
          return ready.future;
        },
      ),
    );
    final spinner = find.byType(CircularProgressIndicator).hitTestable();
    expect(spinner, findsOneWidget);
    expect(Theme.of(tester.element(spinner)).brightness, Brightness.dark);
    expect(
      Theme.of(tester.element(spinner)).colorScheme,
      resolveThemeData(
        'dracula',
        Brightness.dark,
        isCompact: false,
      ).colorScheme,
    );
    expect(starts, 0, reason: 'first frame precedes service initialization');
    await tester.pump(const Duration(milliseconds: 1));
    expect(starts, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(starts, 1, reason: 'rebuilds must not initialize DI twice');
    ready.complete(const MaterialApp(home: Text('Ready')));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Ready'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed initialization leaves a visible error', (tester) async {
    final ready = Completer<Widget>();
    await tester.pumpWidget(
      StartupGate(
        settings: const SettingsEntity(),
        initialize: () => ready.future,
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    ready.completeError(StateError('storage unavailable'));
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.takeException(), isA<StateError>());
    expect(
      find.text('Unable to start Getman. Please restart the app.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('dispose while loading ignores late completion', (tester) async {
    final ready = Completer<Widget>();
    await tester.pumpWidget(
      StartupGate(
        settings: const SettingsEntity(),
        initialize: () => ready.future,
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    ready.complete(const Text('Late'));
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('Late'), findsNothing);
  });
}
