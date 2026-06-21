import 'package:auris/auris.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_copy.dart';
import 'package:getman/core/theme/extensions/app_decoration.dart';
import 'package:getman/core/theme/extensions/app_layout.dart';
import 'package:getman/core/theme/extensions/app_motion.dart';
import 'package:getman/core/theme/extensions/app_shape.dart';
import 'package:getman/core/theme/extensions/app_typography.dart';
import 'package:getman/core/theme/themes/auris/auris_ambient.dart';
import 'package:getman/core/theme/themes/auris/auris_components.dart';
import 'package:getman/core/theme/themes/auris/auris_decorations.dart';
import 'package:getman/core/theme/themes/auris/auris_motion.dart';
import 'package:getman/core/theme/themes/auris/auris_palette.dart';

/// Builds [ThemeData] for the AURIS theme.
///
/// Uses `AurisTheme.dark` / `AurisTheme.light` as the base so Material
/// component themes already match the auris palette. The five Getman extensions
/// (plus `AppMotion` / [AppCopy] / `AppComponents`) are merged in via
/// `copyWith`, crucially **spreading `base.extensions.values`** first so
/// `AurisScheme` — which every auris widget force-unwraps — is always present.
///
/// Phase D1 wires the AURIS component slots via [aurisComponents].
/// Phase E1 replaces the identity [AppMotion] with `aurisMotion(...)`.
/// Task 12 wires the real animated ambient (the C1/C2 base, plumbing
/// AmbientSignals) via `auris_ambient.dart`.
ThemeData aurisTheme(
  Brightness brightness, {
  bool isCompact = false,
  bool reduceEffects = false,
}) {
  final base = _normalizeTextLerp(
    brightness == Brightness.dark
        ? AurisTheme.dark(glowScale: reduceEffects ? 0.0 : 1.0)
        : AurisTheme.light(glowScale: reduceEffects ? 0.0 : 1.0),
  );

  // AurisTheme attaches AurisScheme automatically — confirmed in C1.
  // _normalizeTextLerp uses copyWith, which preserves base.extensions.
  final scheme = base.extension<AurisScheme>()!;

  final layout = isCompact ? AppLayout.compact : AppLayout.normal;

  const shape = AppShape(
    panelRadius: 3,
    buttonRadius: 3,
    inputRadius: 3,
    dialogRadius: 4,
    sheetRadius: 6,
  );

  final palette = aurisPalette(scheme);

  final typography = AppTypography(
    base: base.textTheme, // Rajdhani/ExoTwo already applied by AurisTheme
    codeFontFamily: AurisTokens.fontMono, // 'packages/auris/ShareTechMono'
    displayWeight: FontWeight.w700,
    titleWeight: FontWeight.w600,
    bodyWeight: FontWeight.w400,
  );

  final decoration = AppDecoration(
    panelBox: aurisPanelBox,
    tabShape: aurisTabShape,
    // Light-filled selected tab so the (dark) onPrimary label reads — AURIS's
    // primaryColor defaults dark, which the shared default indicator can't fix.
    brandedTabIndicator: aurisBrandedTabIndicator,
    // Auris press: scale-down on tap-down; identity under reduceEffects.
    wrapInteractive: ({required child, onTap, scaleDown}) => AurisPress(
      onTap: onTap,
      scaleDown: scaleDown,
      animate: !reduceEffects,
      child: child,
    ),
    // Animated scanning HUD grid + radar sweep + telemetry ticks; static grid
    // frame under reduceEffects. Plumbs AmbientSignals (C1/C2 base, Task 12).
    scaffoldBackground: reduceEffects
        ? aurisStaticScaffoldBackground
        : aurisScaffoldBackgroundAnimated,
  );

  return base.copyWith(
    // CRITICAL: spread base extensions FIRST so AurisScheme is preserved.
    // Every auris widget calls Theme.of(context).extension<AurisScheme>()!
    // and will throw if this extension is missing.
    // Cast needed: base.extensions.values is Iterable<ThemeExtension<dynamic>>
    // but the list literal infers ThemeExtension<Object?>, which is compatible
    // after the explicit cast below.
    extensions: [
      ...base.extensions.values,
      layout,
      palette,
      shape,
      typography,
      decoration,
      // AURIS HUD motion (Phase E1).
      aurisMotion(reduceEffects: reduceEffects),
      const AppCopy(emptyResponse: '// NO SIGNAL'),
      // AURIS component slots: each surface maps to its Auris* widget.
      aurisComponents(),
    ],
  );
}

/// Aligns AURIS's `listTileTheme.leadingAndTrailingTextStyle` with the
/// convention every other theme follows, so theme switches don't crash.
///
/// The app runs with `themeAnimationDuration: Duration.zero`, but a mounted
/// [ListTile] still wraps each of its leading/title/subtitle/trailing slots in
/// its OWN internal `AnimatedDefaultTextStyle` (hardcoded ~200ms, independent
/// of the app's theme animation duration). On a theme switch each slot lerps
/// the old resolved style to the new one — and `TextStyle.lerp` throws "Failed
/// to interpolate TextStyles with different inherit values" if the two sides
/// disagree on `inherit`. (`ThemeData.lerp` inside `AnimatedTheme` lerps the
/// `listTileTheme` styles directly too, with the same constraint.)
///
/// The established convention (see every `<name>_theme.dart` listTileTheme,
/// and the comment in `classic_theme`): **`titleTextStyle` and
/// `subtitleTextStyle` are pinned `inherit: true`;
/// `leadingAndTrailingTextStyle` is left unset**, so ListTile falls back to
/// Material's localized `labelSmall`
/// for that slot, which is `inherit: false`. AURIS inherits these from the
/// external `auris` kit and already matches on title/subtitle (both
/// `inherit: true`) — but the kit ALSO sets `leadingAndTrailingTextStyle`
/// (ShareTechMono, `inherit: true`), the lone slot that diverges. Lerping
/// AURIS's `inherit: true` leading/trailing style against another theme's
/// `inherit: false` localized fallback is the crash that flooded the console
/// and red-screened the Settings rows.
///
/// Fix: force ONLY that one slot to `inherit: false` (+ a baseline) so it lerps
/// cleanly against the localized fallback in both directions, while keeping its
/// ShareTechMono family/size/color. Title/subtitle are left exactly as the kit
/// produces them (`inherit: true`) — flipping them would instead mismatch the
/// other themes' pinned `inherit: true` title/subtitle. `textTheme` is likewise
/// untouched: it feeds [AppTypography.base], lerped via a *separate* path
/// (`AppTypography.lerp` → `TextTheme.lerp`) where every theme's base is
/// `inherit: true`; normalizing it to `inherit: false` is exactly the
/// regression a previous app-wide normalization introduced. See
/// `auris_text_lerp_test`.
ThemeData _normalizeTextLerp(ThemeData theme) {
  final tile = theme.listTileTheme;
  final lead = tile.leadingAndTrailingTextStyle;
  if (lead == null) return theme;
  return theme.copyWith(
    listTileTheme: tile.copyWith(
      leadingAndTrailingTextStyle: lead.copyWith(
        inherit: false,
        textBaseline: lead.textBaseline ?? TextBaseline.alphabetic,
      ),
    ),
  );
}
