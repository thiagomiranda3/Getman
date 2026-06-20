// Regression: switching INTO/OUT OF AURIS while a ListTile is mounted (e.g. the
// Settings dialog you switch themes from) crashed. The app uses
// themeAnimationDuration: zero, so the theme swap is instant and ListTile's OWN
// internal AnimatedDefaultTextStyle (leading/title/subtitle/trailing, 200ms)
// lerps the old resolved style to the new one. AURIS's resolved styles were
// inherit:true while every other theme resolves to Material's inherit:false, so
// TextStyle.lerp threw "Failed to interpolate TextStyles with different inherit
// values" — the title/subtitle threw and the leading/trailing became
// RenderErrorBoxes (→ the ListTile "leading consumes entire width" assertion).
//
// Fix: AURIS's textTheme + AppTypography.base are normalized to inherit:false.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:google_fonts/google_fonts.dart';

class _Swapper extends StatefulWidget {
  const _Swapper({required this.from, required this.to});
  final ThemeData from;
  final ThemeData to;
  @override
  State<_Swapper> createState() => _SwapperState();
}

class _SwapperState extends State<_Swapper> {
  late ThemeData _t = widget.from;
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: _t,
    // Matches the app: instant theme data swap, so ListTile's own
    // AnimatedDefaultTextStyle does the (potentially crashing) lerp.
    themeAnimationDuration: Duration.zero,
    home: Scaffold(
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.star),
            title: const Text('THEME SOUNDS'),
            subtitle: const Text('Play themed sound effects'),
            trailing: Switch(value: true, onChanged: (_) {}),
          ),
          ElevatedButton(
            onPressed: () => setState(() => _t = widget.to),
            child: const Text('go'),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Resolve through resolveThemeData — the real app path that normalizes every
  // theme's textTheme (inherit:false + textBaseline). Done inside the test body
  // so the GoogleFonts/asset-bundle access happens after the binding is ready.
  ThemeData t(String id) =>
      resolveThemeData(id, Brightness.dark, isCompact: false);
  final cases = <(String, String, String)>[
    ('AURIS→glass', kAurisThemeId, kGlassThemeId),
    ('AURIS→classic', kAurisThemeId, kClassicThemeId),
    ('glass→AURIS', kGlassThemeId, kAurisThemeId),
    ('classic→AURIS', kClassicThemeId, kAurisThemeId),
  ];

  for (final (name, fromId, toId) in cases) {
    testWidgets('$name with a ListTile mounted does not crash on text lerp', (
      tester,
    ) async {
      await tester.pumpWidget(_Swapper(from: t(fromId), to: t(toId)));
      await tester.pump();
      await tester.tap(find.text('go'));
      await tester.pump(); // instant theme swap frame
      await tester.pump(const Duration(milliseconds: 100)); // mid ListTile lerp
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull, reason: name);
    });
  }
}
