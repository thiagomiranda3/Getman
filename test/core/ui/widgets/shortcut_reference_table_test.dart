// Widget tests for ShortcutReferenceTable: one row per catalog entry for
// both platform conventions, the useMetaShortcuts predicate follows
// defaultTargetPlatform, and the settings SHORTCUTS tab renders through the
// shared widget (single-source mandate for E1/E2).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/navigation/shortcut_catalog.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/core/ui/widgets/shortcut_reference_table.dart';
import 'package:getman/features/settings/presentation/widgets/settings_shortcuts_tab.dart';

Widget _host(Widget child) => MaterialApp(
  theme: brutalistTheme(Brightness.light),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('useMetaShortcuts follows defaultTargetPlatform (single predicate)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(useMetaShortcuts, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(useMetaShortcuts, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(useMetaShortcuts, isFalse);
  });

  testWidgets('renders every catalog entry (macOS convention)', (tester) async {
    await tester.pumpWidget(_host(const ShortcutReferenceTable(useMeta: true)));
    for (final entry in shortcutCatalog(useMeta: true)) {
      expect(
        find.text(entry.description),
        findsWidgets,
        reason: '${entry.action} row missing',
      );
    }
    // macOS convention renders symbol caps, never the spelled-out modifier.
    expect(find.text('⌘'), findsWidgets);
    expect(find.text('Ctrl'), findsNothing);
  });

  testWidgets('renders the Ctrl convention when useMeta is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const ShortcutReferenceTable(useMeta: false)),
    );
    expect(find.text('Ctrl'), findsWidgets);
    expect(find.text('⌘'), findsNothing);
  });

  testWidgets('settings SHORTCUTS tab renders through the shared table', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const SettingsShortcutsTab()));
    expect(find.byType(ShortcutReferenceTable), findsOneWidget);
  });
}
