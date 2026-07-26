import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/settings/presentation/widgets/settings_shortcuts_tab.dart';

Widget _host(ThemeData theme) => MaterialApp(
  theme: theme,
  home: const Scaffold(body: SettingsShortcutsTab()),
);

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('renders every catalog entry, new shortcuts included', (
    tester,
  ) async {
    await tester.pumpWidget(_host(brutalistTheme(Brightness.light)));

    // Pre-existing rows survive the refactor (spot-check each section).
    expect(find.text('Send request'), findsOneWidget);
    expect(find.text('Switch environment'), findsOneWidget);
    expect(find.text('Close tab'), findsOneWidget);
    expect(find.text('Jump to tab 1–9'), findsOneWidget);
    expect(find.text('New panel'), findsOneWidget);
    expect(find.text('Jump to panel 1–9'), findsOneWidget);

    // New catalog entries appear.
    expect(find.text('Reopen closed tab'), findsOneWidget);
    expect(find.text('Save all'), findsOneWidget);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);

    // Section headers, HELP included.
    expect(find.text('REQUEST'), findsOneWidget);
    expect(find.text('TABS'), findsOneWidget);
    expect(find.text('PANELS'), findsOneWidget);
    expect(find.text('HELP'), findsOneWidget);
  });

  testWidgets('spells out modifiers on non-mac platforms', (tester) async {
    // Widget-test default platform is android → useMeta false.
    await tester.pumpWidget(_host(brutalistTheme(Brightness.light)));
    expect(find.text('Ctrl'), findsWidgets);
    expect(find.text('Shift'), findsWidgets);
    expect(find.text('Alt'), findsWidgets);
    expect(find.text('⌘'), findsNothing);
  });

  testWidgets('uses mac glyph key caps when platform is macOS', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(_host(brutalistTheme(Brightness.light)));
    // Reset within the body: the testWidgets invariant check runs before
    // tearDown, and it forbids a leaked foundation debug override.
    debugDefaultTargetPlatformOverride = null;

    expect(find.text('⌘'), findsWidgets);
    expect(find.text('⌥'), findsWidgets);
    // Next/Previous tab render the Control glyph, never spelled Ctrl.
    expect(find.text('⌃'), findsWidgets);
    expect(find.text('Ctrl'), findsNothing);
  });
}
