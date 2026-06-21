// test/core/theme/themes/auris/auris_press_test.dart
//
// AurisPress (tap-down scale feedback) coverage. These tests used to live in
// auris_ambient_test.dart; they were re-homed when Task 12 introduced the new
// dedicated auris_ambient.dart (HUD ambient) and that test file was rewritten
// to the new ambient contract. AurisPress itself stays in
// auris_decorations.dart (press feedback wired into wrapInteractive).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/auris/auris_decorations.dart';

void main() {
  testWidgets('AurisPress animate:true fires onTap + no exception', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AurisPress(
            animate: true,
            onTap: () => tapped = true,
            child: const SizedBox(
              width: 40,
              height: 40,
              key: ValueKey<String>('btn'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('btn')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AurisPress animate:false fires onTap + no exception', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AurisPress(
            animate: false,
            onTap: () => tapped = true,
            child: const SizedBox(
              width: 40,
              height: 40,
              key: ValueKey<String>('btn'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('btn')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AurisPress survives animate:true->false->true (no multiple-tickers crash)',
    (tester) async {
      Widget host({required bool animate}) => MaterialApp(
        home: Scaffold(
          body: AurisPress(
            animate: animate,
            onTap: () {},
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );

      await tester.pumpWidget(host(animate: true));
      await tester.pumpWidget(host(animate: false));
      await tester.pumpWidget(host(animate: true));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(AurisPress), findsOneWidget);
    },
  );

  testWidgets('AurisPress reduced mode: mount + dispose without crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AurisPress(
            animate: false,
            onTap: () {},
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );
    // Replace to trigger dispose.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
