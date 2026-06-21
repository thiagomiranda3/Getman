// Regression: switching INTO/OUT OF AURIS while a [ListTile] is mounted (e.g.
// the Settings dialog you switch themes from) flooded the console with
// exceptions and red-screened the rows.
//
// Why: the app uses `themeAnimationDuration: Duration.zero`, so MaterialApp's
// own theme swap is instant — but [ListTile] wraps each of its
// leading/title/subtitle/trailing slots in its OWN internal
// `AnimatedDefaultTextStyle` (hardcoded ~200ms, independent of the app's theme
// animation duration), and `AnimatedTheme` also lerps the whole ThemeData. On
// a swap those lerp the OLD text style to the NEW one, and `TextStyle.lerp`
// throws "Failed to interpolate TextStyles with different inherit values" on an
// `inherit` mismatch — so the slots became RenderErrorBoxes (=> the ListTile
// "leading consumes entire width" assertion).
//
// The other six themes all follow one convention (see classic_theme): pin
// listTile `titleTextStyle`/`subtitleTextStyle` `inherit: true`, and leave
// `leadingAndTrailingTextStyle` unset so ListTile falls back to Material's
// localized `labelSmall` (`inherit: false`). AURIS inherits these from the
// external `auris` kit and matches on title/subtitle — but the kit ALSO sets
// `leadingAndTrailingTextStyle` (ShareTechMono, `inherit: true`), the lone slot
// that diverges and crashes against the others' `inherit: false` fallback.
//
// Fix (aurisTheme._normalizeTextLerp): flip ONLY that one slot to
// `inherit: false`. Title/subtitle and `textTheme` are left exactly as the kit
// produces them (`inherit: true`) — flipping them instead mismatched the other
// themes (the regression the previous app-wide normalization caused).

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
    // Matches the app: instant theme-data swap, so ListTile's own
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

  ThemeData t(String id) =>
      resolveThemeData(id, Brightness.dark, isCompact: false);

  // The user can switch INTO AURIS from any theme (and back out). Exercise
  // every other theme against AURIS in both directions. Each _Swapper swap is a
  // full MaterialApp theme change, so it drives BOTH lerp surfaces at once:
  // ListTile's own per-slot AnimatedDefaultTextStyle, and AnimatedTheme's
  // ThemeData.lerp (textTheme / primaryTextTheme / listTileTheme + every
  // ThemeExtension, including AppTypography.lerp -> TextTheme.lerp on `base`).
  final others = <String>[
    kClassicThemeId,
    kBrutalistThemeId,
    kEditorialThemeId,
    kRpgThemeId,
    kDraculaThemeId,
    kGlassThemeId,
  ];
  final cases = <(String, String, String)>[
    for (final id in others) ...[
      ('AURIS->$id', kAurisThemeId, id),
      ('$id->AURIS', id, kAurisThemeId),
    ],
  ];

  for (final (name, fromId, toId) in cases) {
    testWidgets('$name with a ListTile mounted does not crash on text lerp', (
      tester,
    ) async {
      await tester.pumpWidget(_Swapper(from: t(fromId), to: t(toId)));
      await tester.pump();
      await tester.tap(find.text('go'));
      await tester.pump(); // instant theme swap frame
      await tester.pump(const Duration(milliseconds: 100)); // mid-lerp
      await tester.pump(const Duration(milliseconds: 150)); // lerp end
      expect(tester.takeException(), isNull, reason: name);
    });
  }

  // Direct guard on the framework lerp path that AnimatedTheme drives: lerping
  // two themes' ThemeData must not throw, regardless of direction or midpoint.
  // This covers textTheme / primaryTextTheme / listTileTheme and every
  // ThemeExtension lerp (incl. AppTypography) without needing a mounted widget.
  testWidgets('ThemeData.lerp AURIS <-> every theme never throws', (
    tester,
  ) async {
    for (final id in others) {
      final auris = t(kAurisThemeId);
      final other = t(id);
      for (final pair in [(auris, other), (other, auris)]) {
        for (final f in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          expect(
            () => ThemeData.lerp(pair.$1, pair.$2, f),
            returnsNormally,
            reason: 'lerp $id @ $f',
          );
        }
      }
    }
  });

  test('AURIS listTileTheme follows the cross-theme inherit convention', () {
    final auris = t(kAurisThemeId).listTileTheme;

    // title/subtitle: inherit:true, matching every other theme's pinned styles
    // (see classic_theme). Flipping these would mismatch the others on lerp.
    expect(auris.titleTextStyle, isNotNull);
    expect(
      auris.titleTextStyle!.inherit,
      isTrue,
      reason: 'title stays inherit',
    );
    expect(auris.subtitleTextStyle, isNotNull);
    expect(auris.subtitleTextStyle!.inherit, isTrue, reason: 'subtitle stays');

    // leadingAndTrailing: the lone slot AURIS's kit sets that other themes
    // leave unset — pinned inherit:false to match Material's localized
    // labelSmall fallback the other themes resolve to. Color must survive the
    // copyWith (the regression guard — forcing inherit must not blank it).
    final lead = auris.leadingAndTrailingTextStyle;
    expect(lead, isNotNull);
    expect(lead!.inherit, isFalse, reason: 'leading/trailing -> inherit:false');
    expect(lead.textBaseline, isNotNull, reason: 'baseline must be set');
    expect(lead.color, isNotNull, reason: 'color must survive');
  });
}
