# CLASSIC Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a calm, native-style "CLASSIC" theme (muted-indigo accent, neutral gray surfaces, hairline borders, tighter padding, soft small radii) and make it the app's default for fresh installs.

**Architecture:** Themes are self-contained — a folder under `lib/core/theme/themes/classic/` whose builder returns a `ThemeData` carrying six `ThemeExtension`s (`AppLayout`, `AppPalette`, `AppShape`, `AppTypography`, `AppDecoration`, `AppCopy`). The picker and command palette already iterate `appThemes`, so **no widget edits** are needed. "Default" is set in three places: the registry `defaultThemeId` (unknown-id fallback) and the `SettingsEntity`/`SettingsModel` `themeId` defaults (the real first-run value). Existing users are unaffected — their `themeId` is persisted in the `settings` Hive box.

**Tech Stack:** Flutter, `flutter_bloc`, `hive_ce` (typeId 0 `SettingsModel`, field 7 `themeId`), `google_fonts` (Inter + JetBrains Mono).

## Global Constraints

- Always invoke Flutter as `fvm flutter ...` / `fvm dart ...` — never plain `flutter`/`dart`. (build_runner is `dart run build_runner ...` per CLAUDE.md §5.)
- All imports are `package:getman/...` — no relative imports.
- `Colors.black`/`Colors.white`/`Colors.red` literals are allowed **only** inside `lib/core/theme/` (the `avoid_hardcoded_brand_colors` custom_lint rule). All new theme files live under `lib/core/theme/themes/classic/`, so literal black/white for shadows and on-accent contrast is permitted there.
- Theme display names are uppercase (e.g. `BRUTALIST`, `DRACULA`). New name: `CLASSIC`.
- Never renumber a Hive `typeId`. This work changes only the **default value** of the existing `themeId` field (HiveField 7) — no new field, but `build_runner` must be rerun so the generated adapter's default string becomes `'classic'`.
- Done-bar (CLAUDE.md §5): `fvm flutter analyze` (0 issues), `fvm dart run custom_lint` (0), `fvm dart run bloc_tools:bloc lint lib` (0), `fvm dart format` clean, `fvm flutter test` 100% green. These are independent passes.
- Spec: `docs/superpowers/specs/2026-06-19-classic-theme-design.md`.

---

### Task 1: Create the CLASSIC theme and register it

**Files:**
- Create: `lib/core/theme/themes/classic/classic_palette.dart`
- Create: `lib/core/theme/themes/classic/classic_press.dart`
- Create: `lib/core/theme/themes/classic/classic_decorations.dart`
- Create: `lib/core/theme/themes/classic/classic_theme.dart`
- Modify: `lib/core/theme/theme_ids.dart`
- Modify: `lib/core/theme/theme_registry.dart`
- Test: `test/core/theme/themes/classic_theme_test.dart` (create)
- Modify (test): `test/core/theme/themes/glass_theme_test.dart` (add `'classic'` to two hardcoded theme-id lists)

**Interfaces:**
- Produces: `ThemeData classicTheme(Brightness brightness, {bool isCompact = false, bool reduceEffects = false})` (matches the `AppThemeBuilder` typedef in `theme_registry.dart`).
- Produces: `const String kClassicThemeId = 'classic';`
- Produces: registry entry `appThemes[kClassicThemeId]` with `displayName: 'CLASSIC'`.
- Produces: `class ClassicPress extends StatefulWidget` with named params `{required Widget child, Key? key, VoidCallback? onTap, double? scaleDown, bool animate = true}`.
- Produces decoration builders: `classicPanelBox`, `classicTabShape`, `classicScaffoldBackground` (signatures match the typedefs in `lib/core/theme/extensions/app_decoration.dart`).
- Consumes: `accentSwitchTheme({required Color thumbWhenOn, required Color trackWhenOn})` from `lib/core/theme/app_switch_theme.dart`; the six extension classes + `BuildContext` accessors (`context.appLayout`, `context.appShape`, `context.appDecoration`) from `lib/core/theme/app_theme.dart`.

- [ ] **Step 1: Write the failing smoke test**

Create `test/core/theme/themes/classic_theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/theme/themes/classic/classic_theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('classicTheme', () {
    for (final b in [Brightness.light, Brightness.dark]) {
      for (final c in [false, true]) {
        for (final r in [false, true]) {
          testWidgets(
            'attaches all six extensions (brightness=$b compact=$c reduce=$r)',
            (tester) async {
              final theme = classicTheme(b, isCompact: c, reduceEffects: r);
              expect(theme.extension<AppLayout>(), isNotNull);
              expect(theme.extension<AppPalette>(), isNotNull);
              expect(theme.extension<AppShape>(), isNotNull);
              expect(theme.extension<AppTypography>(), isNotNull);
              expect(theme.extension<AppDecoration>(), isNotNull);
              expect(theme.extension<AppCopy>(), isNotNull);
              expect(theme.extension<AppLayout>()!.isCompact, c);
              expect(theme.brightness, b);
            },
          );
        }
      }
    }

    test('is registered with the CLASSIC display name', () {
      expect(appThemes[kClassicThemeId], isNotNull);
      expect(appThemes[kClassicThemeId]!.displayName, 'CLASSIC');
      expect(appThemes[kClassicThemeId]!.id, kClassicThemeId);
    });

    testWidgets('panels are soft cards: rounded, soft shadow, no hard offset', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: classicTheme(Brightness.light),
          home: Builder(
            builder: (ctx) {
              final deco = ctx.appDecoration;
              final box = deco.panelBox(ctx);
              expect(box.borderRadius, isNotNull);
              expect(box.boxShadow, isNotEmpty);
              // No branded-tab indicator override → keeps the default filled look.
              expect(deco.brandedTabIndicator, isNull);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('active tab shows an accent bottom indicator', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: classicTheme(Brightness.light),
          home: Builder(
            builder: (ctx) {
              final deco = ctx.appDecoration;
              final active = deco.tabShape(
                ctx,
                active: true,
                hovered: false,
                isFirst: true,
              );
              expect(active.border?.bottom.color,
                  Theme.of(ctx).colorScheme.primary);
              final inactive = deco.tabShape(
                ctx,
                active: false,
                hovered: false,
                isFirst: false,
              );
              expect(inactive.color, Colors.transparent);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/core/theme/themes/classic_theme_test.dart`
Expected: FAIL — compile error, `classic_theme.dart` / `kClassicThemeId` don't exist.

- [ ] **Step 3: Create the palette**

Create `lib/core/theme/themes/classic/classic_palette.dart`:

```dart
import 'package:flutter/material.dart';

/// Calm, conventional palette for the CLASSIC theme — neutral grays with a
/// single muted-indigo accent. One method-color map serves both brightnesses;
/// `AppPalette.onColor` picks legible text so the contrast suite passes.
class ClassicPalette {
  ClassicPalette._();

  static const Color scaffoldLight = Color(0xFFF6F7F9);
  static const Color scaffoldDark = Color(0xFF1B1C1F);

  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF232428);

  static const Color inkLight = Color(0xFF1F2328);
  static const Color inkDark = Color(0xFFE6E7EA);

  static const Color inkSoftLight = Color(0xFF656D76);
  static const Color inkSoftDark = Color(0xFF9AA0A6);

  static const Color borderLight = Color(0xFFD6DAE0);
  static const Color borderDark = Color(0xFF34353A);

  static const Color accentLight = Color(0xFF6366F1);
  static const Color accentDark = Color(0xFF818CF8);

  static const Color codeBackgroundLight = Color(0xFFF6F8FA);
  static const Color codeBackgroundDark = Color(0xFF1A1B1E);

  static const Map<String, Color> methodColors = {
    'GET': Color(0xFF2EA043),
    'POST': Color(0xFFD97706),
    'PUT': Color(0xFF2563EB),
    'PATCH': Color(0xFF0891B2),
    'DELETE': Color(0xFFDC2626),
  };

  static const Color statusSuccess = Color(0xFF2EA043);
  static const Color statusWarning = Color(0xFFD97706);
  static const Color statusError = Color(0xFFDC2626);

  static const Color statusAccentSuccess = Color(0xFF1A7F37);
  static const Color statusAccentWarning = Color(0xFFB45309);
  static const Color statusAccentError = Color(0xFFB91C1C);
}
```

- [ ] **Step 4: Create the press wrapper**

Create `lib/core/theme/themes/classic/classic_press.dart`:

```dart
import 'package:flutter/material.dart';

/// Subtle press feedback for CLASSIC: a quick opacity dim plus an optional tiny
/// scale on tap — no bounce. When [animate] is false (reduceEffects) it is a
/// plain tap target with no animation.
class ClassicPress extends StatefulWidget {
  const ClassicPress({
    required this.child,
    super.key,
    this.onTap,
    this.scaleDown,
    this.animate = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double? scaleDown;
  final bool animate;

  @override
  State<ClassicPress> createState() => _ClassicPressState();
}

class _ClassicPressState extends State<ClassicPress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.child,
      );
    }
    final scale = _pressed ? (widget.scaleDown ?? 0.99) : 1.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          opacity: _pressed ? 0.85 : 1.0,
          child: widget.child,
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Create the decorations**

Create `lib/core/theme/themes/classic/classic_decorations.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Flat native-style card: surface fill + 1px hairline border + a very subtle
/// soft shadow (no hard brutalist offset). Radius defaults to the theme's
/// panel radius.
BoxDecoration classicPanelBox(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final shape = context.appShape;
  final isDark = theme.brightness == Brightness.dark;
  return BoxDecoration(
    color: color ?? theme.cardColor,
    borderRadius: borderRadius ?? BorderRadius.circular(shape.panelRadius),
    border: Border.all(
      color: theme.dividerColor,
      width: borderWidth ?? layout.borderThin,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
        blurRadius: 6,
        offset: const Offset(0, 1),
      ),
    ],
  );
}

/// Browser/editor-style tab: active = surface fill + accent bottom indicator;
/// hovered = subtle bg tint; inactive = transparent. No per-column rules.
BoxDecoration classicTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final accent = theme.colorScheme.primary;
  final Color bg;
  if (active) {
    bg = theme.cardColor;
  } else if (hovered) {
    bg = theme.hoverColor;
  } else {
    bg = Colors.transparent;
  }
  return BoxDecoration(
    color: bg,
    border: Border(
      bottom: BorderSide(
        color: active ? accent : Colors.transparent,
        width: layout.borderThick,
      ),
    ),
  );
}

/// Plain scaffold — no dot grid, no sparkles. Identity wrapper.
Widget classicScaffoldBackground(
  BuildContext context, {
  required Widget child,
}) =>
    child;
```

- [ ] **Step 6: Create the theme builder**

Create `lib/core/theme/themes/classic/classic_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_switch_theme.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/classic/classic_decorations.dart';
import 'package:getman/core/theme/themes/classic/classic_palette.dart';
import 'package:getman/core/theme/themes/classic/classic_press.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData classicTheme(
  Brightness brightness, {
  bool isCompact = false,
  bool reduceEffects = false,
}) {
  final isDark = brightness == Brightness.dark;
  final scaffold =
      isDark ? ClassicPalette.scaffoldDark : ClassicPalette.scaffoldLight;
  final surface =
      isDark ? ClassicPalette.surfaceDark : ClassicPalette.surfaceLight;
  final ink = isDark ? ClassicPalette.inkDark : ClassicPalette.inkLight;
  final inkSoft =
      isDark ? ClassicPalette.inkSoftDark : ClassicPalette.inkSoftLight;
  final border = isDark ? ClassicPalette.borderDark : ClassicPalette.borderLight;
  final accent = isDark ? ClassicPalette.accentDark : ClassicPalette.accentLight;
  final code = isDark
      ? ClassicPalette.codeBackgroundDark
      : ClassicPalette.codeBackgroundLight;

  // Density: start from the shared layout and dial padding/borders down so the
  // theme reads calm and tight (no "huge paddings", no thick borders).
  final layoutBase = isCompact ? AppLayout.compact : AppLayout.normal;
  final layout = layoutBase.copyWith(
    pagePadding: isCompact ? 10 : 16,
    sectionSpacing: isCompact ? 10 : 16,
    buttonPaddingHorizontal: isCompact ? 14 : 16,
    buttonPaddingVertical: isCompact ? 8 : 10,
    inputPadding: isCompact ? 10 : 12,
    headerPaddingVertical: isCompact ? 10 : 12,
    headerFontSize: isCompact ? 17 : 18,
    tabBarHeight: isCompact ? 38 : 44,
    cardOffset: 0,
    borderThin: 1,
    borderThick: 1.5,
    borderHeavy: 2,
  );

  const shape = AppShape(
    panelRadius: 6,
    buttonRadius: 6,
    inputRadius: 6,
    dialogRadius: 10,
    sheetRadius: 12,
  );

  final interText = GoogleFonts.interTextTheme();
  final interFamily = GoogleFonts.inter().fontFamily;
  final monoFamily = GoogleFonts.jetBrainsMono().fontFamily!;
  final baseTextTheme = interText.apply(bodyColor: ink, displayColor: ink);

  final typography = AppTypography(
    base: baseTextTheme,
    codeFontFamily: monoFamily,
    displayWeight: FontWeight.w600,
    titleWeight: FontWeight.w600,
    bodyWeight: FontWeight.w400,
  );

  final palette = AppPalette(
    methodColors: ClassicPalette.methodColors,
    methodFallback: inkSoft,
    statusSuccess: ClassicPalette.statusSuccess,
    statusWarning: ClassicPalette.statusWarning,
    statusError: ClassicPalette.statusError,
    statusAccentSuccess: ClassicPalette.statusAccentSuccess,
    statusAccentWarning: ClassicPalette.statusAccentWarning,
    statusAccentError: ClassicPalette.statusAccentError,
    codeBackground: code,
    variableResolved: ClassicPalette.statusAccentSuccess,
    variableUnresolved: ClassicPalette.statusAccentError,
    selectorActive: accent,
    diffAddedForeground: ClassicPalette.statusSuccess,
    diffAddedBackground: ClassicPalette.statusSuccess.withValues(alpha: 0.12),
    diffRemovedForeground: ClassicPalette.statusError,
    diffRemovedBackground: ClassicPalette.statusError.withValues(alpha: 0.12),
  );

  // Legible text/icon color on the accent and on the error color.
  final onAccent = palette.onColor(accent);
  final onError = palette.onColor(ClassicPalette.statusError);

  final decoration = AppDecoration(
    panelBox: classicPanelBox,
    tabShape: classicTabShape,
    wrapInteractive: ({required child, onTap, scaleDown}) => ClassicPress(
      onTap: onTap,
      scaleDown: scaleDown,
      animate: !reduceEffects,
      child: child,
    ),
    scaffoldBackground: classicScaffoldBackground,
  );

  final labelStyle = TextStyle(
    fontFamily: interFamily,
    fontSize: layout.fontSizeNormal,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    primaryColor: accent,
    switchTheme: accentSwitchTheme(thumbWhenOn: surface, trackWhenOn: accent),
    scaffoldBackgroundColor: scaffold,
    canvasColor: scaffold,
    cardColor: surface,
    dividerColor: border,
    hoverColor: ink.withValues(alpha: isDark ? 0.06 : 0.04),
    splashColor: ink.withValues(alpha: 0.08),
    colorScheme:
        (isDark ? const ColorScheme.dark() : const ColorScheme.light())
            .copyWith(
      primary: accent,
      onPrimary: onAccent,
      secondary: inkSoft,
      onSecondary: surface,
      surface: surface,
      onSurface: ink,
      error: ClassicPalette.statusError,
      onError: onError,
    ),
    textTheme: baseTextTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scaffold,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: baseTextTheme.titleMedium?.copyWith(
        fontSize: layout.fontSizeSubtitle,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      shape: Border(bottom: BorderSide(color: border, width: layout.borderThin)),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      labelColor: accent,
      unselectedLabelColor: inkSoft,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: accent, width: layout.borderThick),
        ),
      ),
      labelStyle: labelStyle.copyWith(color: accent),
      unselectedLabelStyle: labelStyle.copyWith(color: inkSoft),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.buttonRadius),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: layout.buttonPaddingHorizontal,
          vertical: layout.buttonPaddingVertical,
        ),
        textStyle: labelStyle.copyWith(color: onAccent),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: border, width: layout.borderThin),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.buttonRadius),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: layout.buttonPaddingHorizontal,
          vertical: layout.buttonPaddingVertical,
        ),
        textStyle: labelStyle.copyWith(color: ink),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: labelStyle.copyWith(color: accent),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(shape.inputRadius),
        borderSide: BorderSide(color: border, width: layout.borderThin),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(shape.inputRadius),
        borderSide: BorderSide(color: border, width: layout.borderThin),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(shape.inputRadius),
        borderSide: BorderSide(color: accent, width: layout.borderThick),
      ),
      labelStyle: TextStyle(color: inkSoft),
      hintStyle: TextStyle(color: inkSoft.withValues(alpha: 0.6)),
      contentPadding: EdgeInsets.symmetric(
        horizontal: layout.inputPadding,
        vertical: layout.inputPaddingVertical,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.panelRadius),
        side: BorderSide(color: border, width: layout.borderThin),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.dialogRadius),
        side: BorderSide(color: border, width: layout.borderThin),
      ),
      titleTextStyle: baseTextTheme.titleLarge?.copyWith(
        fontSize: layout.fontSizeSubtitle,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      contentTextStyle: baseTextTheme.bodyMedium?.copyWith(color: ink),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: accent.withValues(alpha: 0.10),
      selectedColor: accent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.panelRadius),
        side: BorderSide(color: border, width: layout.borderThin),
      ),
    ),
  );

  return base.copyWith(
    extensions: [
      layout,
      palette,
      shape,
      typography,
      decoration,
      const AppCopy(emptyResponse: 'No response yet.'),
    ],
  );
}
```

- [ ] **Step 7: Add the id constant**

In `lib/core/theme/theme_ids.dart`, append:

```dart
const String kClassicThemeId = 'classic';
```

- [ ] **Step 8: Register the descriptor**

In `lib/core/theme/theme_registry.dart`:

Add the import (keep imports alphabetically ordered — it goes first, before `brutalist`):

```dart
import 'package:getman/core/theme/themes/classic/classic_theme.dart';
```

Add this entry to the `appThemes` map (place it first so CLASSIC heads the picker list):

```dart
  kClassicThemeId: ThemeDescriptor(
    id: kClassicThemeId,
    displayName: 'CLASSIC',
    builder: classicTheme,
  ),
```

Do **not** change `defaultThemeId` in this task (that is Task 2).

- [ ] **Step 9: Extend the existing cross-theme tests to cover CLASSIC**

In `test/core/theme/themes/glass_theme_test.dart`, add `'classic'` to both hardcoded theme-id lists so the new theme is covered:

- In the `'every theme defines a switchTheme ...'` test, change
  `for (final id in ['brutalist', 'editorial', 'rpg', 'dracula', 'glass'])`
  to
  `for (final id in ['brutalist', 'editorial', 'rpg', 'dracula', 'glass', 'classic'])`.
- In the `'non-glass themes keep the null indicator fallback ...'` test, change
  `for (final id in ['brutalist', 'editorial', 'rpg', 'dracula'])`
  to
  `for (final id in ['brutalist', 'editorial', 'rpg', 'dracula', 'classic'])`.

(CLASSIC uses `accentSwitchTheme` so its ON thumb=`surface` ≠ track=`accent`, and it sets no `brandedTabIndicator`, so both assertions hold.)

- [ ] **Step 10: Run the new + cross-theme tests to verify they pass**

Run: `fvm flutter test test/core/theme/themes/classic_theme_test.dart test/core/theme/themes/glass_theme_test.dart test/core/theme/contrast_test.dart test/core/theme/theme_registry_test.dart`
Expected: PASS (contrast suite now auto-covers CLASSIC method/status legibility).

- [ ] **Step 11: Run the analysis gate**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test`
Expected: `No issues found!` for both analyzers; formatter reports 0 changed (or formats the new files — re-stage if so).

- [ ] **Step 12: Run the full test suite**

Run: `fvm flutter test`
Expected: 100% green (default theme unchanged this task, so nothing else shifts).

- [ ] **Step 13: Commit**

```bash
git add lib/core/theme/themes/classic/ lib/core/theme/theme_ids.dart lib/core/theme/theme_registry.dart test/core/theme/themes/classic_theme_test.dart test/core/theme/themes/glass_theme_test.dart
git commit -m "feat(theme): add CLASSIC — calm, native-style theme

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z"
```

---

### Task 2: Make CLASSIC the default for fresh installs

**Files:**
- Modify: `lib/core/theme/theme_registry.dart:29` (`defaultThemeId`)
- Modify: `lib/features/settings/domain/entities/settings_entity.dart:18` (`themeId` default)
- Modify: `lib/features/settings/data/models/settings_model.dart:21` (constructor default) and `:52` (`fromJson` fallback)
- Modify (generated): `lib/features/settings/data/models/settings_model.g.dart` (regenerate)
- Test: `test/features/settings/data/models/settings_model_test.dart:7-9` (flip assertion)
- Test: `test/core/theme/themes/classic_theme_test.dart` (append a `defaultThemeId` assertion)

**Interfaces:**
- Consumes: `kClassicThemeId` (Task 1), `defaultThemeId` (registry).
- Produces: `defaultThemeId == kClassicThemeId`; `const SettingsEntity().themeId == 'classic'`.

- [ ] **Step 1: Update the tests first (failing)**

In `test/features/settings/data/models/settings_model_test.dart`, change the first test:

```dart
    test('fromEntity default themeId is classic', () {
      final model = SettingsModel.fromEntity(const SettingsEntity());
      expect(model.themeId, 'classic');
    });
```

In `test/core/theme/themes/classic_theme_test.dart`, add inside the `group('classicTheme', ...)`:

```dart
    test('is the app default theme', () {
      expect(defaultThemeId, kClassicThemeId);
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/features/settings/data/models/settings_model_test.dart test/core/theme/themes/classic_theme_test.dart`
Expected: FAIL — default is still `brutalist`.

- [ ] **Step 3: Flip the registry default**

In `lib/core/theme/theme_registry.dart`, change:

```dart
const String defaultThemeId = kBrutalistThemeId;
```

to:

```dart
const String defaultThemeId = kClassicThemeId;
```

- [ ] **Step 4: Flip the entity default**

In `lib/features/settings/domain/entities/settings_entity.dart`, change `this.themeId = kBrutalistThemeId,` to `this.themeId = kClassicThemeId,`. Confirm the file imports `package:getman/core/theme/theme_ids.dart` (it already references `kBrutalistThemeId`, so the import exists — no new import needed).

- [ ] **Step 5: Flip the model defaults**

In `lib/features/settings/data/models/settings_model.dart`:
- Constructor: change `this.themeId = kBrutalistThemeId,` to `this.themeId = kClassicThemeId,`.
- `fromJson`: change `themeId: json['themeId'] as String? ?? kBrutalistThemeId,` to `themeId: json['themeId'] as String? ?? kClassicThemeId,`.

- [ ] **Step 6: Regenerate the Hive adapter**

Run: `fvm dart run build_runner build --delete-conflicting-outputs`
Expected: success; `lib/features/settings/data/models/settings_model.g.dart:31` now reads `themeId: fields[7] == null ? 'classic' : fields[7] as String,`.

Verify: `grep -n "fields\[7\] == null" lib/features/settings/data/models/settings_model.g.dart` → shows `'classic'`.

- [ ] **Step 7: Run the targeted tests to verify they pass**

Run: `fvm flutter test test/features/settings/data/models/settings_model_test.dart test/core/theme/themes/classic_theme_test.dart test/core/theme/theme_registry_test.dart`
Expected: PASS.

- [ ] **Step 8: Run the full suite (catch default-theme-dependent tests)**

Run: `fvm flutter test`
Expected: 100% green. If a widget test that relied on the *default* (e.g. it builds the app with `const SettingsEntity()` and asserts brutalist-specific styling) now fails, fix it by pinning that test to brutalist explicitly via `SettingsEntity(themeId: kBrutalistThemeId)` — do **not** weaken the new default. (None is expected; most widget tests wrap a chosen theme directly.)

- [ ] **Step 9: Run the analysis gate**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test`
Expected: 0 issues from all three; format clean.

- [ ] **Step 10: Commit**

```bash
git add lib/core/theme/theme_registry.dart lib/features/settings/ test/features/settings/data/models/settings_model_test.dart test/core/theme/themes/classic_theme_test.dart
git commit -m "feat(theme): default new installs to CLASSIC

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PYoFHzTfGFGP7FR3fNkk1z"
```

---

### Task 3: Manual verification in the running app

**Files:** none (verification only).

- [ ] **Step 1: Launch the app**

Run: `fvm flutter run -d macos`
Expected: app boots; a fresh install (or after clearing the `settings` box) shows the CLASSIC theme by default.

- [ ] **Step 2: Visual check — light & dark**

In Settings → Appearance, confirm `CLASSIC` is listed (heading the list) and selected by default. Toggle dark mode and the compact toggle. Verify against the spec's intent:
- Panels read as soft cards (1px hairline + subtle shadow, ~6px radius), not heavy borders or hard offset shadows.
- Padding is tighter than the other themes; no "huge paddings".
- The only saturated color is the indigo accent (SEND button, active tab underline, input focus ring, links/selected items); surfaces are neutral gray.
- HTTP method badges and status bands are legible (white/black auto-contrast text).

- [ ] **Step 3: Switch away and back**

Switch to BRUTALIST, then back to CLASSIC, in both light and dark. Confirm no layout breakage, no invisible switch thumbs, tabs/inputs/buttons all render correctly.

- [ ] **Step 4: Final full gate**

Run: `fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test tools && fvm flutter test`
Expected: 0 issues from all analyzers, format clean, tests 100% green.

---

### Task 4: Sync the wiki

**Files:** in the separate `Getman.wiki.git` repo (not this repo). Per the CLAUDE.md §7 "Keep the wiki in sync" mandate — a new theme + a changed default is a user-facing change.

- [ ] **Step 1: Clone the wiki**

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki
ls /tmp/getman-wiki
```

- [ ] **Step 2: Find the themes/appearance page**

Run: `grep -ril "brutalist\|theme\|appearance" /tmp/getman-wiki`
Identify the page that documents the theme list / Appearance settings (and check `_Sidebar.md`).

- [ ] **Step 3: Edit the page**

Add `CLASSIC` to the documented theme list with a one-line description ("A calm, native-style theme — neutral grays, a muted-indigo accent, hairline borders and tight spacing; the **default** for new installs."). Keep wording accurate to the app (verbatim UI label `CLASSIC`). If the page names a default theme anywhere, update it to CLASSIC.

- [ ] **Step 4: Commit & push**

```bash
cd /tmp/getman-wiki
git add -A
git commit -m "docs: add CLASSIC theme (new default)"
git push origin master
```

Expected: push succeeds; the page updates at <https://github.com/thiagomiranda3/Getman/wiki>.

---

## Self-Review

**Spec coverage:**
- Palette (light/dark, methods, status, variables, diff) → Task 1 Step 3 + builder Step 6. ✓
- Typography (Inter + JetBrains Mono, calm weights) → Task 1 Step 6 (`typography`). ✓
- Shape radii → Task 1 Step 6 (`shape`). ✓
- Density overrides (both normal & compact) → Task 1 Step 6 (`layout.copyWith`). ✓
- Decorations (`panelBox` soft card, `tabShape` accent indicator, `ClassicPress`, identity scaffold, default frost/indicator) → Task 1 Steps 4–6. ✓
- `AppCopy.emptyResponse` → Task 1 Step 6. ✓
- Registration + no widget edits → Task 1 Steps 7–8. ✓
- Default switch (registry + entity + model + regen) → Task 2. ✓
- Test updates (settings default assertion; cross-theme coverage; contrast auto-cover; smoke test) → Tasks 1–2. ✓
- Verification gate → Task 3. ✓
- Wiki → Task 4. ✓

**Placeholder scan:** No TBD/TODO; all code blocks are complete; exact density numbers specified (no "finalized later"). ✓

**Type consistency:** `classicTheme(Brightness, {bool isCompact, bool reduceEffects})` matches `AppThemeBuilder`. `ClassicPress` params (`onTap`, `scaleDown`, `animate`, `child`) match the call site in the builder. `classicPanelBox`/`classicTabShape`/`classicScaffoldBackground` signatures match the `app_decoration.dart` typedefs. `kClassicThemeId` used identically across registry, settings, and tests. `palette.onColor(...)` is a real method on `AppPalette`. ✓
