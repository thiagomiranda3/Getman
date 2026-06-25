import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Regression: AURIS light-mode tabs flickered on hover/activation because the
  // inactive tab fill was `Colors.transparent` (premultiplied black) while
  // hover/active fills are opaque LIGHT colors. The `AnimatedContainer` lerps
  // between them, and `Color.lerp(Colors.transparent, lightColor, .5)` lands on
  // a muddy mid-gray (transparent's RGB is 0,0,0), which flashes dark against
  // AURIS's light surfaces. The fix keeps the inactive fill a *same-hue,
  // zero-alpha* color so the fade is alpha-only and stays light throughout.
  testWidgets(
    'AURIS light: inactive tab fades through a light midpoint, not muddy dark',
    (tester) async {
      late BoxDecoration inactive;
      late BoxDecoration hovered;
      late BoxDecoration active;

      await tester.pumpWidget(
        MaterialApp(
          theme: resolveTheme(kAurisThemeId)(
            Brightness.light,
            isCompact: false,
          ),
          home: Builder(
            builder: (context) {
              inactive = context.appDecoration.tabShape(
                context,
                active: false,
                hovered: false,
                isFirst: false,
              );
              hovered = context.appDecoration.tabShape(
                context,
                active: false,
                hovered: true,
                isFirst: false,
              );
              active = context.appDecoration.tabShape(
                context,
                active: true,
                hovered: false,
                isFirst: false,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // At rest the inactive tab is still fully transparent: no visual change.
      expect(inactive.color!.a, 0.0);

      // The hover-in fade must not pass through a dark midpoint.
      final hoverMid = Color.lerp(inactive.color, hovered.color, 0.5)!;
      expect(
        hoverMid.computeLuminance(),
        greaterThan(0.5),
        reason: 'hover fade-in midpoint should stay light, not flash dark',
      );

      // Neither should activation.
      final activeMid = Color.lerp(inactive.color, active.color, 0.5)!;
      expect(
        activeMid.computeLuminance(),
        greaterThan(0.5),
        reason: 'activation fade midpoint should stay light, not flash dark',
      );
    },
  );
}
