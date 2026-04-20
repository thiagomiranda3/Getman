# Pluggable Themes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monolithic `NeoBrutalistTheme` with a pluggable architecture: five `ThemeExtension` classes + a theme registry. The brutalist aesthetic is preserved pixel-for-pixel and becomes the first registered theme. A `themeId` is added to Settings so a future picker can switch themes live, like dark-mode/compact-mode today.

**Architecture:** Five `ThemeExtension` subclasses (`AppLayout`, `AppPalette`, `AppShape`, `AppTypography`, `AppDecoration`) attached to `ThemeData`. `AppDecoration` holds closures for panel/tab/bounce behavior so polymorphism is stored as data. Each theme lives in `lib/core/theme/themes/<name>/` and exports one `ThemeData Function(Brightness, {bool isCompact})`. A registry maps `themeId` strings to builders. `main.dart` reads `themeId` from settings and picks the builder.

**Tech Stack:** Flutter (SDK via `fvm`), `flutter_bloc`, `hive` + `hive_flutter`, `google_fonts`, `equatable`.

**Spec:** `docs/superpowers/specs/2026-04-20-pluggable-themes-design.md`

---

## File Structure

**New files:**

- `lib/core/theme/app_theme.dart` — the five `ThemeExtension` classes and `AppThemeAccess` `BuildContext` extension.
- `lib/core/theme/theme_ids.dart` — `const kBrutalistThemeId = 'brutalist'`.
- `lib/core/theme/theme_registry.dart` — `AppThemeBuilder` typedef, `appThemes` map, `defaultThemeId`, `resolveTheme(String?)` helper.
- `lib/core/theme/themes/brutalist/brutalist_palette.dart` — color constants.
- `lib/core/theme/themes/brutalist/brutalist_decorations.dart` — `brutalPanelBox`, `brutalTabShape` free functions.
- `lib/core/theme/themes/brutalist/brutalist_bounce.dart` — the `BrutalBounce` `StatefulWidget`.
- `lib/core/theme/themes/brutalist/brutalist_theme.dart` — `brutalistTheme(Brightness, {bool isCompact})`.
- `test/core/theme/app_layout_test.dart`
- `test/core/theme/app_palette_test.dart`
- `test/core/theme/app_shape_test.dart`
- `test/core/theme/app_typography_test.dart`
- `test/core/theme/app_decoration_test.dart`
- `test/core/theme/themes/brutalist_theme_test.dart`
- `test/core/theme/theme_registry_test.dart`
- `test/features/settings/data/models/settings_model_test.dart`

**Modified files:**

- `lib/features/settings/domain/entities/settings_entity.dart` — add `themeId`.
- `lib/features/settings/data/models/settings_model.dart` — add `HiveField(7) themeId`.
- `lib/features/settings/presentation/bloc/settings_event.dart` — add `UpdateThemeId`.
- `lib/features/settings/presentation/bloc/settings_bloc.dart` — handler for `UpdateThemeId`.
- `lib/main.dart` — import registry, call `resolveTheme(...)`.
- `lib/features/tabs/presentation/widgets/request_view.dart` — migrate call sites.
- `lib/features/home/presentation/widgets/side_menu.dart` — migrate call sites.
- `lib/features/home/presentation/screens/main_screen.dart` — migrate call sites.
- `lib/core/ui/widgets/method_badge.dart` — migrate call sites.
- `lib/core/ui/widgets/splitter.dart` — migrate call sites.
- `test/widget_test.dart` — swap `NeoBrutalistTheme.*` for new API.

**Deleted files (Task 14):**

- `lib/core/theme/neo_brutalist_theme.dart`
- `lib/core/utils/status_color.dart`

---

## Cut-over strategy

To avoid a broken intermediate state:

1. Tasks 1–8 scaffold the new module. The old `NeoBrutalistTheme.theme(...)` is still wired to `main.dart` — nothing visible changes yet. The class named `LayoutExtension` is renamed to `AppLayout` in Task 1 (all 6 usage sites are fixed in that same task), so the old theme now attaches `AppLayout` under the hood. That means widgets continue to work and no widget imports change during Tasks 1–8.
2. Tasks 9–10 add the Settings `themeId` field.
3. Task 11 switches `main.dart` to the registry. At this moment the new `brutalistTheme` becomes the live theme. It attaches all five extensions, so widgets that still call `NeoBrutalistTheme.brutalBox(context, ...)` / `NeoBrutalistTheme.getMethodColor(...)` continue to work because those static methods are still present in the old file.
4. Tasks 12a–12e migrate widgets one file at a time. At each step both old and new APIs work, so each task can be verified in isolation.
5. Tasks 13–14 delete `neo_brutalist_theme.dart` and `status_color.dart`, then run the final verification.

---

## Verification discipline

After every commit: `fvm flutter analyze` prints exactly `No issues found!`, and `fvm flutter test` is 100% green. If either fails, fix it before the next task.

`debugPrint` is the only allowed logger — the default lint disallows `print`.

---

### Task 1: Introduce `AppLayout` (renamed from `LayoutExtension`) + two new font-size fields

**Files:**
- Create: `lib/core/theme/app_theme.dart`
- Modify: `lib/core/theme/neo_brutalist_theme.dart` (remove the `LayoutExtension` class; import `AppLayout` from `app_theme.dart`; use `AppLayout` in `_createTheme`)
- Modify: `lib/features/tabs/presentation/widgets/request_view.dart` (imports + type references)
- Modify: `lib/features/home/presentation/widgets/side_menu.dart`
- Modify: `lib/features/home/presentation/screens/main_screen.dart`
- Modify: `lib/core/ui/widgets/method_badge.dart`
- Modify: `lib/core/ui/widgets/splitter.dart`
- Test: `test/core/theme/app_layout_test.dart`

**Why two new fields:** the spec §4 requires eliminating every hardcoded `fontSize` literal in widgets. Two literals don't map to an existing field:
- `request_view.dart:613, 839` use `fontSize: 13` for the JSON code editor → new field `fontSizeCode` (13 normal / 12 compact).
- `main_screen.dart:173, neo_brutalist_theme.dart:353` use `fontSize: 18` for a header title → new field `fontSizeSubtitle` (18 normal / 14 compact).

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/app_layout_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';

void main() {
  group('AppLayout', () {
    test('normal and compact constants differ on pagePadding', () {
      expect(AppLayout.normal.pagePadding, isNot(AppLayout.compact.pagePadding));
    });

    test('includes fontSizeCode and fontSizeSubtitle', () {
      expect(AppLayout.normal.fontSizeCode, 13.0);
      expect(AppLayout.compact.fontSizeCode, 12.0);
      expect(AppLayout.normal.fontSizeSubtitle, 18.0);
      expect(AppLayout.compact.fontSizeSubtitle, 14.0);
    });

    test('copyWith preserves non-overridden fields', () {
      final copy = AppLayout.normal.copyWith(pagePadding: 99.0);
      expect(copy.pagePadding, 99.0);
      expect(copy.sectionSpacing, AppLayout.normal.sectionSpacing);
      expect(copy.fontSizeCode, AppLayout.normal.fontSizeCode);
    });

    test('lerp interpolates numerics and snaps ints/bools to other', () {
      final mid = AppLayout.normal.lerp(AppLayout.compact, 0.5) as AppLayout;
      expect(
        mid.pagePadding,
        closeTo((AppLayout.normal.pagePadding + AppLayout.compact.pagePadding) / 2, 0.001),
      );
      expect(mid.isCompact, AppLayout.compact.isCompact);
      expect(mid.tabTitleMaxLength, AppLayout.compact.tabTitleMaxLength);
    });

    test('lerp with a different type returns this', () {
      final result = AppLayout.normal.lerp(null, 0.5);
      expect(result, AppLayout.normal);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/app_layout_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:getman/core/theme/app_theme.dart'`.

- [ ] **Step 3: Create `lib/core/theme/app_theme.dart` with `AppLayout`**

```dart
import 'package:flutter/material.dart';

class AppLayout extends ThemeExtension<AppLayout> {
  final double pagePadding;
  final double sectionSpacing;
  final double verticalDividerWidth;
  final double iconSize;
  final double smallIconSize;
  final double badgePaddingHorizontal;
  final double badgePaddingVertical;
  final double fontSizeTitle;
  final double fontSizeSmall;
  final double fontSizeNormal;
  final double fontSizeCode;
  final double fontSizeSubtitle;
  final double buttonPaddingHorizontal;
  final double buttonPaddingVertical;
  final double inputPadding;
  final double inputPaddingVertical;
  final double cardOffset;
  final double headerPaddingVertical;
  final double headerFontSize;
  final double tabBarHeight;
  final double tabCloseIconSize;
  final double tabPaddingHorizontal;
  final double tabFontSize;
  final int tabTitleMaxLength;
  final double tabSpacing;
  final double addIconSize;
  final double dirtyStarSize;
  final bool isCompact;
  final double depthPaddingMultiplier;
  final double sideMenuWidth;
  final double borderThin;
  final double borderThick;
  final double borderHeavy;
  final double dialogWidth;
  final double splitterGrabSize;
  final double splitterLineSize;

  const AppLayout({
    required this.isCompact,
    required this.pagePadding,
    required this.sectionSpacing,
    required this.verticalDividerWidth,
    required this.iconSize,
    required this.smallIconSize,
    required this.badgePaddingHorizontal,
    required this.badgePaddingVertical,
    required this.fontSizeTitle,
    required this.fontSizeSmall,
    required this.fontSizeNormal,
    required this.fontSizeCode,
    required this.fontSizeSubtitle,
    required this.buttonPaddingHorizontal,
    required this.buttonPaddingVertical,
    required this.inputPadding,
    required this.inputPaddingVertical,
    required this.cardOffset,
    required this.headerPaddingVertical,
    required this.headerFontSize,
    required this.tabBarHeight,
    required this.tabCloseIconSize,
    required this.tabPaddingHorizontal,
    required this.tabFontSize,
    required this.tabTitleMaxLength,
    required this.tabSpacing,
    required this.addIconSize,
    required this.dirtyStarSize,
    required this.depthPaddingMultiplier,
    required this.sideMenuWidth,
    required this.borderThin,
    required this.borderThick,
    required this.borderHeavy,
    required this.dialogWidth,
    required this.splitterGrabSize,
    required this.splitterLineSize,
  });

  @override
  AppLayout copyWith({
    bool? isCompact,
    double? pagePadding,
    double? sectionSpacing,
    double? verticalDividerWidth,
    double? iconSize,
    double? smallIconSize,
    double? badgePaddingHorizontal,
    double? badgePaddingVertical,
    double? fontSizeTitle,
    double? fontSizeSmall,
    double? fontSizeNormal,
    double? fontSizeCode,
    double? fontSizeSubtitle,
    double? buttonPaddingHorizontal,
    double? buttonPaddingVertical,
    double? inputPadding,
    double? inputPaddingVertical,
    double? cardOffset,
    double? headerPaddingVertical,
    double? headerFontSize,
    double? tabBarHeight,
    double? tabCloseIconSize,
    double? tabPaddingHorizontal,
    double? tabFontSize,
    int? tabTitleMaxLength,
    double? tabSpacing,
    double? addIconSize,
    double? dirtyStarSize,
    double? depthPaddingMultiplier,
    double? sideMenuWidth,
    double? borderThin,
    double? borderThick,
    double? borderHeavy,
    double? dialogWidth,
    double? splitterGrabSize,
    double? splitterLineSize,
  }) {
    return AppLayout(
      isCompact: isCompact ?? this.isCompact,
      pagePadding: pagePadding ?? this.pagePadding,
      sectionSpacing: sectionSpacing ?? this.sectionSpacing,
      verticalDividerWidth: verticalDividerWidth ?? this.verticalDividerWidth,
      iconSize: iconSize ?? this.iconSize,
      smallIconSize: smallIconSize ?? this.smallIconSize,
      badgePaddingHorizontal: badgePaddingHorizontal ?? this.badgePaddingHorizontal,
      badgePaddingVertical: badgePaddingVertical ?? this.badgePaddingVertical,
      fontSizeTitle: fontSizeTitle ?? this.fontSizeTitle,
      fontSizeSmall: fontSizeSmall ?? this.fontSizeSmall,
      fontSizeNormal: fontSizeNormal ?? this.fontSizeNormal,
      fontSizeCode: fontSizeCode ?? this.fontSizeCode,
      fontSizeSubtitle: fontSizeSubtitle ?? this.fontSizeSubtitle,
      buttonPaddingHorizontal: buttonPaddingHorizontal ?? this.buttonPaddingHorizontal,
      buttonPaddingVertical: buttonPaddingVertical ?? this.buttonPaddingVertical,
      inputPadding: inputPadding ?? this.inputPadding,
      inputPaddingVertical: inputPaddingVertical ?? this.inputPaddingVertical,
      cardOffset: cardOffset ?? this.cardOffset,
      headerPaddingVertical: headerPaddingVertical ?? this.headerPaddingVertical,
      headerFontSize: headerFontSize ?? this.headerFontSize,
      tabBarHeight: tabBarHeight ?? this.tabBarHeight,
      tabCloseIconSize: tabCloseIconSize ?? this.tabCloseIconSize,
      tabPaddingHorizontal: tabPaddingHorizontal ?? this.tabPaddingHorizontal,
      tabFontSize: tabFontSize ?? this.tabFontSize,
      tabTitleMaxLength: tabTitleMaxLength ?? this.tabTitleMaxLength,
      tabSpacing: tabSpacing ?? this.tabSpacing,
      addIconSize: addIconSize ?? this.addIconSize,
      dirtyStarSize: dirtyStarSize ?? this.dirtyStarSize,
      depthPaddingMultiplier: depthPaddingMultiplier ?? this.depthPaddingMultiplier,
      sideMenuWidth: sideMenuWidth ?? this.sideMenuWidth,
      borderThin: borderThin ?? this.borderThin,
      borderThick: borderThick ?? this.borderThick,
      borderHeavy: borderHeavy ?? this.borderHeavy,
      dialogWidth: dialogWidth ?? this.dialogWidth,
      splitterGrabSize: splitterGrabSize ?? this.splitterGrabSize,
      splitterLineSize: splitterLineSize ?? this.splitterLineSize,
    );
  }

  @override
  AppLayout lerp(ThemeExtension<AppLayout>? other, double t) {
    if (other is! AppLayout) return this;
    double l(double a, double b) => (b - a) * t + a;
    return AppLayout(
      isCompact: other.isCompact,
      pagePadding: l(pagePadding, other.pagePadding),
      sectionSpacing: l(sectionSpacing, other.sectionSpacing),
      verticalDividerWidth: l(verticalDividerWidth, other.verticalDividerWidth),
      iconSize: l(iconSize, other.iconSize),
      smallIconSize: l(smallIconSize, other.smallIconSize),
      badgePaddingHorizontal: l(badgePaddingHorizontal, other.badgePaddingHorizontal),
      badgePaddingVertical: l(badgePaddingVertical, other.badgePaddingVertical),
      fontSizeTitle: l(fontSizeTitle, other.fontSizeTitle),
      fontSizeSmall: l(fontSizeSmall, other.fontSizeSmall),
      fontSizeNormal: l(fontSizeNormal, other.fontSizeNormal),
      fontSizeCode: l(fontSizeCode, other.fontSizeCode),
      fontSizeSubtitle: l(fontSizeSubtitle, other.fontSizeSubtitle),
      buttonPaddingHorizontal: l(buttonPaddingHorizontal, other.buttonPaddingHorizontal),
      buttonPaddingVertical: l(buttonPaddingVertical, other.buttonPaddingVertical),
      inputPadding: l(inputPadding, other.inputPadding),
      inputPaddingVertical: l(inputPaddingVertical, other.inputPaddingVertical),
      cardOffset: l(cardOffset, other.cardOffset),
      headerPaddingVertical: l(headerPaddingVertical, other.headerPaddingVertical),
      headerFontSize: l(headerFontSize, other.headerFontSize),
      tabBarHeight: l(tabBarHeight, other.tabBarHeight),
      tabCloseIconSize: l(tabCloseIconSize, other.tabCloseIconSize),
      tabPaddingHorizontal: l(tabPaddingHorizontal, other.tabPaddingHorizontal),
      tabFontSize: l(tabFontSize, other.tabFontSize),
      tabTitleMaxLength: other.tabTitleMaxLength,
      tabSpacing: l(tabSpacing, other.tabSpacing),
      addIconSize: l(addIconSize, other.addIconSize),
      dirtyStarSize: l(dirtyStarSize, other.dirtyStarSize),
      depthPaddingMultiplier: l(depthPaddingMultiplier, other.depthPaddingMultiplier),
      sideMenuWidth: l(sideMenuWidth, other.sideMenuWidth),
      borderThin: l(borderThin, other.borderThin),
      borderThick: l(borderThick, other.borderThick),
      borderHeavy: l(borderHeavy, other.borderHeavy),
      dialogWidth: l(dialogWidth, other.dialogWidth),
      splitterGrabSize: l(splitterGrabSize, other.splitterGrabSize),
      splitterLineSize: l(splitterLineSize, other.splitterLineSize),
    );
  }

  static const normal = AppLayout(
    isCompact: false,
    pagePadding: 24.0,
    sectionSpacing: 24.0,
    verticalDividerWidth: 48.0,
    iconSize: 24.0,
    smallIconSize: 16.0,
    badgePaddingHorizontal: 10.0,
    badgePaddingVertical: 2.0,
    fontSizeTitle: 14.0,
    fontSizeSmall: 10.0,
    fontSizeNormal: 12.0,
    fontSizeCode: 13.0,
    fontSizeSubtitle: 18.0,
    buttonPaddingHorizontal: 24.0,
    buttonPaddingVertical: 16.0,
    inputPadding: 16.0,
    inputPaddingVertical: 8.0,
    cardOffset: 6.0,
    headerPaddingVertical: 20.0,
    headerFontSize: 24.0,
    tabBarHeight: 60.0,
    tabCloseIconSize: 16.0,
    tabPaddingHorizontal: 16.0,
    tabFontSize: 11.0,
    tabTitleMaxLength: 25,
    tabSpacing: 8.0,
    addIconSize: 24.0,
    dirtyStarSize: 16.0,
    depthPaddingMultiplier: 20.0,
    sideMenuWidth: 300.0,
    borderThin: 2.0,
    borderThick: 3.0,
    borderHeavy: 4.0,
    dialogWidth: 400.0,
    splitterGrabSize: 40.0,
    splitterLineSize: 3.0,
  );

  static const compact = AppLayout(
    isCompact: true,
    pagePadding: 12.0,
    sectionSpacing: 12.0,
    verticalDividerWidth: 24.0,
    iconSize: 18.0,
    smallIconSize: 14.0,
    badgePaddingHorizontal: 6.0,
    badgePaddingVertical: 1.0,
    fontSizeTitle: 12.0,
    fontSizeSmall: 9.0,
    fontSizeNormal: 11.0,
    fontSizeCode: 12.0,
    fontSizeSubtitle: 14.0,
    buttonPaddingHorizontal: 16.0,
    buttonPaddingVertical: 12.0,
    inputPadding: 10.0,
    inputPaddingVertical: 6.0,
    cardOffset: 3.0,
    headerPaddingVertical: 12.0,
    headerFontSize: 18.0,
    tabBarHeight: 40.0,
    tabCloseIconSize: 12.0,
    tabPaddingHorizontal: 8.0,
    tabFontSize: 9.0,
    tabTitleMaxLength: 15,
    tabSpacing: 4.0,
    addIconSize: 18.0,
    dirtyStarSize: 12.0,
    depthPaddingMultiplier: 12.0,
    sideMenuWidth: 240.0,
    borderThin: 2.0,
    borderThick: 3.0,
    borderHeavy: 4.0,
    dialogWidth: 320.0,
    splitterGrabSize: 28.0,
    splitterLineSize: 2.0,
  );
}
```

- [ ] **Step 4: Purge the old `LayoutExtension` class and wire `AppLayout` into the old theme**

In `lib/core/theme/neo_brutalist_theme.dart`:
- Add near the top: `import 'app_theme.dart';`
- Delete the entire `class LayoutExtension ...` (lines 4–266) — the whole class, both static constants, `copyWith`, `lerp`.
- In `_createTheme`, change:
  ```dart
  final LayoutExtension layout = isCompact ? LayoutExtension.compact : LayoutExtension.normal;
  ```
  to:
  ```dart
  final AppLayout layout = isCompact ? AppLayout.compact : AppLayout.normal;
  ```
- The `extensions: [layout]` line stays as-is (attaches `AppLayout` now).

- [ ] **Step 5: Update the six widget / test files that reference `LayoutExtension`**

In each of these files, replace `LayoutExtension` with `AppLayout` (type references only — no API change):
- `lib/features/tabs/presentation/widgets/request_view.dart`
- `lib/features/home/presentation/widgets/side_menu.dart`
- `lib/features/home/presentation/screens/main_screen.dart`
- `lib/core/ui/widgets/method_badge.dart`
- `lib/core/ui/widgets/splitter.dart`
- `test/widget_test.dart`

Use `Grep` for `LayoutExtension` across `lib/**/*.dart` and `test/**/*.dart`, and in each hit replace `LayoutExtension` with `AppLayout`. Also remove the `import 'package:getman/core/theme/neo_brutalist_theme.dart';` line from files whose only reason to import it was `LayoutExtension`, adding `import 'package:getman/core/theme/app_theme.dart';` instead. (Files that also use `NeoBrutalistTheme.*` keep the old import too.)

- [ ] **Step 6: Verify**

Run:
```
fvm flutter analyze
fvm flutter test
```
Expected: analyze → `No issues found!`; test → all green including the new `app_layout_test.dart`.

- [ ] **Step 7: Commit**

```bash
git add lib/core/theme/app_theme.dart lib/core/theme/neo_brutalist_theme.dart lib/features/tabs/presentation/widgets/request_view.dart lib/features/home/presentation/widgets/side_menu.dart lib/features/home/presentation/screens/main_screen.dart lib/core/ui/widgets/method_badge.dart lib/core/ui/widgets/splitter.dart test/widget_test.dart test/core/theme/app_layout_test.dart
git commit -m "refactor(theme): extract AppLayout extension and add fontSizeCode/fontSizeSubtitle"
```

---

### Task 2: Add `AppPalette` extension (colors not in `ColorScheme`)

**Files:**
- Modify: `lib/core/theme/app_theme.dart` (append `AppPalette` class)
- Test: `test/core/theme/app_palette_test.dart`

`AppPalette` holds method colors, HTTP status colors (regular + accent), and two neutrals used ad-hoc today.

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/app_palette_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';

void main() {
  const fallback = Colors.grey;
  final palette = AppPalette(
    methodColors: const {
      'GET': Color(0xFF4ADE80),
      'POST': Color(0xFF60A5FA),
    },
    methodFallback: fallback,
    statusSuccess: Colors.green,
    statusWarning: Colors.orange,
    statusError: Colors.red,
    statusAccentSuccess: Colors.greenAccent,
    statusAccentWarning: Colors.orangeAccent,
    statusAccentError: Colors.redAccent,
    codeBackground: const Color(0xFF111111),
    mutedHover: const Color(0x1A000000),
  );

  group('AppPalette', () {
    test('methodColor returns map entry for known methods (case-insensitive)', () {
      expect(palette.methodColor('GET'), const Color(0xFF4ADE80));
      expect(palette.methodColor('get'), const Color(0xFF4ADE80));
      expect(palette.methodColor('POST'), const Color(0xFF60A5FA));
    });

    test('methodColor returns fallback for unknown methods', () {
      expect(palette.methodColor('OPTIONS'), fallback);
    });

    test('statusColor maps 2xx/3xx/4xx+ to success/warning/error', () {
      expect(palette.statusColor(204), Colors.green);
      expect(palette.statusColor(301), Colors.orange);
      expect(palette.statusColor(404), Colors.red);
      expect(palette.statusColor(500), Colors.red);
    });

    test('statusAccent maps 2xx/3xx/4xx+ to accent variants', () {
      expect(palette.statusAccent(204), Colors.greenAccent);
      expect(palette.statusAccent(301), Colors.orangeAccent);
      expect(palette.statusAccent(404), Colors.redAccent);
    });

    test('copyWith preserves non-overridden fields', () {
      final copy = palette.copyWith(codeBackground: const Color(0xFF222222));
      expect(copy.codeBackground, const Color(0xFF222222));
      expect(copy.methodFallback, fallback);
      expect(copy.statusSuccess, Colors.green);
    });

    test('lerp interpolates colors and picks other.methodColors map', () {
      final other = palette.copyWith(
        methodColors: const {'GET': Color(0xFF000000)},
        statusSuccess: Colors.white,
      );
      final mid = palette.lerp(other, 1.0) as AppPalette;
      expect(mid.methodColors['GET'], const Color(0xFF000000));
      expect(mid.statusSuccess, Colors.white);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/app_palette_test.dart`
Expected: FAIL — `AppPalette` undefined.

- [ ] **Step 3: Implement `AppPalette`**

Append to `lib/core/theme/app_theme.dart`:

```dart
class AppPalette extends ThemeExtension<AppPalette> {
  final Map<String, Color> methodColors;
  final Color methodFallback;
  final Color statusSuccess;
  final Color statusWarning;
  final Color statusError;
  final Color statusAccentSuccess;
  final Color statusAccentWarning;
  final Color statusAccentError;
  final Color codeBackground;
  final Color mutedHover;

  const AppPalette({
    required this.methodColors,
    required this.methodFallback,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusError,
    required this.statusAccentSuccess,
    required this.statusAccentWarning,
    required this.statusAccentError,
    required this.codeBackground,
    required this.mutedHover,
  });

  Color methodColor(String method) =>
      methodColors[method.toUpperCase()] ?? methodFallback;

  Color statusColor(int code) {
    if (code >= 200 && code < 300) return statusSuccess;
    if (code >= 400) return statusError;
    return statusWarning;
  }

  Color statusAccent(int code) {
    if (code >= 200 && code < 300) return statusAccentSuccess;
    if (code >= 400) return statusAccentError;
    return statusAccentWarning;
  }

  @override
  AppPalette copyWith({
    Map<String, Color>? methodColors,
    Color? methodFallback,
    Color? statusSuccess,
    Color? statusWarning,
    Color? statusError,
    Color? statusAccentSuccess,
    Color? statusAccentWarning,
    Color? statusAccentError,
    Color? codeBackground,
    Color? mutedHover,
  }) {
    return AppPalette(
      methodColors: methodColors ?? this.methodColors,
      methodFallback: methodFallback ?? this.methodFallback,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusWarning: statusWarning ?? this.statusWarning,
      statusError: statusError ?? this.statusError,
      statusAccentSuccess: statusAccentSuccess ?? this.statusAccentSuccess,
      statusAccentWarning: statusAccentWarning ?? this.statusAccentWarning,
      statusAccentError: statusAccentError ?? this.statusAccentError,
      codeBackground: codeBackground ?? this.codeBackground,
      mutedHover: mutedHover ?? this.mutedHover,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      methodColors: other.methodColors,
      methodFallback: Color.lerp(methodFallback, other.methodFallback, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusError: Color.lerp(statusError, other.statusError, t)!,
      statusAccentSuccess: Color.lerp(statusAccentSuccess, other.statusAccentSuccess, t)!,
      statusAccentWarning: Color.lerp(statusAccentWarning, other.statusAccentWarning, t)!,
      statusAccentError: Color.lerp(statusAccentError, other.statusAccentError, t)!,
      codeBackground: Color.lerp(codeBackground, other.codeBackground, t)!,
      mutedHover: Color.lerp(mutedHover, other.mutedHover, t)!,
    );
  }
}
```

- [ ] **Step 4: Verify**

Run: `fvm flutter test test/core/theme/app_palette_test.dart` → PASS.
Run: `fvm flutter analyze` → `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_theme.dart test/core/theme/app_palette_test.dart
git commit -m "feat(theme): add AppPalette extension for method + status colors"
```

---

### Task 3: Add `AppShape` extension

**Files:**
- Modify: `lib/core/theme/app_theme.dart` (append `AppShape`)
- Test: `test/core/theme/app_shape_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/app_shape_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';

void main() {
  group('AppShape', () {
    const a = AppShape(panelRadius: 4, buttonRadius: 4, inputRadius: 4, dialogRadius: 8);
    const b = AppShape(panelRadius: 12, buttonRadius: 12, inputRadius: 12, dialogRadius: 20);

    test('copyWith preserves non-overridden fields', () {
      final copy = a.copyWith(panelRadius: 99);
      expect(copy.panelRadius, 99);
      expect(copy.buttonRadius, 4);
      expect(copy.inputRadius, 4);
      expect(copy.dialogRadius, 8);
    });

    test('lerp interpolates radii', () {
      final mid = a.lerp(b, 0.5) as AppShape;
      expect(mid.panelRadius, 8);
      expect(mid.buttonRadius, 8);
      expect(mid.inputRadius, 8);
      expect(mid.dialogRadius, 14);
    });

    test('lerp with wrong type returns this', () {
      expect(a.lerp(null, 0.5), a);
    });
  });
}
```

- [ ] **Step 2: Run test** → FAIL (`AppShape` undefined).

- [ ] **Step 3: Implement `AppShape`**

Append to `lib/core/theme/app_theme.dart`:

```dart
class AppShape extends ThemeExtension<AppShape> {
  final double panelRadius;
  final double buttonRadius;
  final double inputRadius;
  final double dialogRadius;

  const AppShape({
    required this.panelRadius,
    required this.buttonRadius,
    required this.inputRadius,
    required this.dialogRadius,
  });

  @override
  AppShape copyWith({
    double? panelRadius,
    double? buttonRadius,
    double? inputRadius,
    double? dialogRadius,
  }) {
    return AppShape(
      panelRadius: panelRadius ?? this.panelRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      inputRadius: inputRadius ?? this.inputRadius,
      dialogRadius: dialogRadius ?? this.dialogRadius,
    );
  }

  @override
  AppShape lerp(ThemeExtension<AppShape>? other, double t) {
    if (other is! AppShape) return this;
    double l(double a, double b) => (b - a) * t + a;
    return AppShape(
      panelRadius: l(panelRadius, other.panelRadius),
      buttonRadius: l(buttonRadius, other.buttonRadius),
      inputRadius: l(inputRadius, other.inputRadius),
      dialogRadius: l(dialogRadius, other.dialogRadius),
    );
  }
}
```

- [ ] **Step 4: Verify & Commit**

```
fvm flutter test test/core/theme/app_shape_test.dart
fvm flutter analyze
git add lib/core/theme/app_theme.dart test/core/theme/app_shape_test.dart
git commit -m "feat(theme): add AppShape extension for panel/button/input/dialog radii"
```

---

### Task 4: Add `AppTypography` extension

**Files:**
- Modify: `lib/core/theme/app_theme.dart` (append `AppTypography`)
- Test: `test/core/theme/app_typography_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/app_typography_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';

void main() {
  group('AppTypography', () {
    final a = AppTypography(
      base: const TextTheme(bodyMedium: TextStyle(fontSize: 14)),
      codeFontFamily: 'JetBrainsMono',
      displayWeight: FontWeight.w900,
      titleWeight: FontWeight.w700,
      bodyWeight: FontWeight.w500,
    );

    test('copyWith preserves non-overridden fields', () {
      final copy = a.copyWith(codeFontFamily: 'FiraCode');
      expect(copy.codeFontFamily, 'FiraCode');
      expect(copy.displayWeight, FontWeight.w900);
      expect(copy.base.bodyMedium?.fontSize, 14);
    });

    test('lerp returns a typography with other.codeFontFamily', () {
      final b = a.copyWith(codeFontFamily: 'Monaco');
      final mid = a.lerp(b, 1.0) as AppTypography;
      expect(mid.codeFontFamily, 'Monaco');
    });

    test('lerp with wrong type returns this', () {
      expect(a.lerp(null, 0.5), a);
    });
  });
}
```

- [ ] **Step 2: Run test** → FAIL.

- [ ] **Step 3: Implement `AppTypography`**

Append to `lib/core/theme/app_theme.dart`:

```dart
class AppTypography extends ThemeExtension<AppTypography> {
  final TextTheme base;
  final String codeFontFamily;
  final FontWeight displayWeight;
  final FontWeight titleWeight;
  final FontWeight bodyWeight;

  const AppTypography({
    required this.base,
    required this.codeFontFamily,
    required this.displayWeight,
    required this.titleWeight,
    required this.bodyWeight,
  });

  @override
  AppTypography copyWith({
    TextTheme? base,
    String? codeFontFamily,
    FontWeight? displayWeight,
    FontWeight? titleWeight,
    FontWeight? bodyWeight,
  }) {
    return AppTypography(
      base: base ?? this.base,
      codeFontFamily: codeFontFamily ?? this.codeFontFamily,
      displayWeight: displayWeight ?? this.displayWeight,
      titleWeight: titleWeight ?? this.titleWeight,
      bodyWeight: bodyWeight ?? this.bodyWeight,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      base: TextTheme.lerp(base, other.base, t),
      codeFontFamily: other.codeFontFamily,
      displayWeight: other.displayWeight,
      titleWeight: other.titleWeight,
      bodyWeight: other.bodyWeight,
    );
  }
}
```

- [ ] **Step 4: Verify & Commit**

```
fvm flutter test test/core/theme/app_typography_test.dart
fvm flutter analyze
git add lib/core/theme/app_theme.dart test/core/theme/app_typography_test.dart
git commit -m "feat(theme): add AppTypography extension"
```

---

### Task 5: Add `AppDecoration` extension + `AppThemeAccess` BuildContext extension + `theme_ids.dart`

**Files:**
- Modify: `lib/core/theme/app_theme.dart` (append `AppDecoration` + `AppThemeAccess`)
- Create: `lib/core/theme/theme_ids.dart`
- Test: `test/core/theme/app_decoration_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/app_decoration_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';

BoxDecoration _noopPanel(BuildContext ctx, {Color? color, double? borderWidth, double? offset, BorderRadius? borderRadius}) =>
    const BoxDecoration();
BoxDecoration _noopTab(BuildContext ctx, {required bool active}) => const BoxDecoration();
Widget _noopWrap({required Widget child, VoidCallback? onTap, double? scaleDown}) => child;

void main() {
  group('AppDecoration', () {
    final a = AppDecoration(
      panelBox: _noopPanel,
      tabShape: _noopTab,
      wrapInteractive: _noopWrap,
    );

    test('copyWith swaps provided closures and keeps others', () {
      BoxDecoration newPanel(BuildContext ctx, {Color? color, double? borderWidth, double? offset, BorderRadius? borderRadius}) =>
          const BoxDecoration(color: Colors.red);
      final copy = a.copyWith(panelBox: newPanel);
      expect(identical(copy.panelBox, newPanel), isTrue);
      expect(identical(copy.tabShape, a.tabShape), isTrue);
      expect(identical(copy.wrapInteractive, a.wrapInteractive), isTrue);
    });

    test('lerp returns this regardless of target', () {
      final b = a.copyWith();
      expect(a.lerp(b, 0.5), a);
      expect(a.lerp(null, 0.5), a);
    });
  });
}
```

- [ ] **Step 2: Run test** → FAIL (`AppDecoration` undefined).

- [ ] **Step 3: Implement `AppDecoration` and `AppThemeAccess`**

Append to `lib/core/theme/app_theme.dart`:

```dart
typedef PanelBoxBuilder = BoxDecoration Function(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
});

typedef TabShapeBuilder = BoxDecoration Function(
  BuildContext context, {
  required bool active,
});

typedef InteractiveWrapper = Widget Function({
  required Widget child,
  VoidCallback? onTap,
  double? scaleDown,
});

class AppDecoration extends ThemeExtension<AppDecoration> {
  final PanelBoxBuilder panelBox;
  final TabShapeBuilder tabShape;
  final InteractiveWrapper wrapInteractive;

  const AppDecoration({
    required this.panelBox,
    required this.tabShape,
    required this.wrapInteractive,
  });

  @override
  AppDecoration copyWith({
    PanelBoxBuilder? panelBox,
    TabShapeBuilder? tabShape,
    InteractiveWrapper? wrapInteractive,
  }) {
    return AppDecoration(
      panelBox: panelBox ?? this.panelBox,
      tabShape: tabShape ?? this.tabShape,
      wrapInteractive: wrapInteractive ?? this.wrapInteractive,
    );
  }

  @override
  AppDecoration lerp(ThemeExtension<AppDecoration>? other, double t) => this;
}

extension AppThemeAccess on BuildContext {
  AppLayout get appLayout => Theme.of(this).extension<AppLayout>()!;
  AppPalette get appPalette => Theme.of(this).extension<AppPalette>()!;
  AppShape get appShape => Theme.of(this).extension<AppShape>()!;
  AppTypography get appTypography => Theme.of(this).extension<AppTypography>()!;
  AppDecoration get appDecoration => Theme.of(this).extension<AppDecoration>()!;
}
```

- [ ] **Step 4: Create `lib/core/theme/theme_ids.dart`**

```dart
const String kBrutalistThemeId = 'brutalist';
```

- [ ] **Step 5: Verify & Commit**

```
fvm flutter test test/core/theme/app_decoration_test.dart
fvm flutter analyze
git add lib/core/theme/app_theme.dart lib/core/theme/theme_ids.dart test/core/theme/app_decoration_test.dart
git commit -m "feat(theme): add AppDecoration + BuildContext access + theme ids"
```

---

### Task 6: Brutalist subpackage — palette, bounce, decorations

**Files:**
- Create: `lib/core/theme/themes/brutalist/brutalist_palette.dart`
- Create: `lib/core/theme/themes/brutalist/brutalist_bounce.dart`
- Create: `lib/core/theme/themes/brutalist/brutalist_decorations.dart`

The old `NeoBrutalistTheme` static color constants, `BrutalBounce` widget, and `brutalBox`/`brutalTab` static helpers are **copied** here (not moved yet — old file stays fully functional until Task 14).

- [ ] **Step 1: Create `brutalist_palette.dart`**

```dart
import 'package:flutter/material.dart';

class BrutalistPalette {
  BrutalistPalette._();

  static const Color backgroundLight = Color(0xFFF3F4F6);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color textLight = Color(0xFF000000);
  static const Color borderLight = Color(0xFF000000);

  static const Color backgroundDark = Color(0xFF1A1A1A);
  static const Color surfaceDark = Color(0xFF242424);
  static const Color textDark = Color(0xFFE0E0E0);
  static const Color borderDark = Color(0xFF404040);

  static const Color primary = Color(0xFFFFD700);
  static const Color primaryDark = Color(0xFFFFD700);

  static const Color secondary = Color(0xFF6D28D9);
  static const Color secondaryDark = Color(0xFF6330BD);

  static const Color lightGray = Color(0xFFE5E7EB);

  static const Map<String, Color> methodColors = {
    'GET': Color(0xFF4ADE80),
    'POST': Color(0xFF60A5FA),
    'PUT': Color(0xFFFB923C),
    'DELETE': Color(0xFFF87171),
    'PATCH': Color(0xFFA78BFA),
  };

  static const Color methodFallback = Colors.grey;
}
```

- [ ] **Step 2: Create `brutalist_bounce.dart`**

```dart
import 'package:flutter/material.dart';

class BrutalBounce extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  const BrutalBounce({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.95,
  });

  @override
  State<BrutalBounce> createState() => _BrutalBounceState();
}

class _BrutalBounceState extends State<BrutalBounce> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleDown).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant BrutalBounce oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scaleDown != widget.scaleDown) {
      _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleDown).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
```

Note the added `didUpdateWidget` override: `scaleDown` is a parameter of `wrapInteractive`, so callers may pass different values for different widgets and reuse the same `BrutalBounce` instance. This keeps the animation in sync.

- [ ] **Step 3: Create `brutalist_decorations.dart`**

```dart
import 'package:flutter/material.dart';
import '../../app_theme.dart';

BoxDecoration brutalistPanelBox(
  BuildContext context, {
  Color? color,
  double? borderWidth,
  double? offset,
  BorderRadius? borderRadius,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final shape = context.appShape;
  final border = theme.dividerColor;
  return BoxDecoration(
    color: color ?? theme.cardColor,
    borderRadius: borderRadius ?? BorderRadius.circular(shape.panelRadius),
    border: Border.all(color: border, width: borderWidth ?? layout.borderThick),
    boxShadow: [
      BoxShadow(
        color: border,
        offset: Offset(offset ?? layout.borderHeavy, offset ?? layout.borderHeavy),
        blurRadius: 0,
      ),
    ],
  );
}

BoxDecoration brutalistTabShape(
  BuildContext context, {
  required bool active,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  final border = theme.dividerColor;
  return BoxDecoration(
    color: active ? theme.primaryColor : theme.cardColor,
    border: Border(
      right: BorderSide(color: border, width: layout.borderThin),
      bottom: active ? BorderSide.none : BorderSide(color: border, width: layout.borderThin),
      top: active ? BorderSide(color: border, width: layout.borderHeavy) : BorderSide.none,
    ),
  );
}
```

- [ ] **Step 4: Verify & Commit**

```
fvm flutter analyze
fvm flutter test
```
Both should pass — no new tests yet, but the new files must compile.

```bash
git add lib/core/theme/themes/brutalist/
git commit -m "feat(theme): add brutalist subpackage (palette, bounce, decorations)"
```

---

### Task 7: Implement `brutalistTheme` builder

**Files:**
- Create: `lib/core/theme/themes/brutalist/brutalist_theme.dart`
- Test: `test/core/theme/themes/brutalist_theme_test.dart`

The builder composes all five extensions + Material `ThemeData`. It is a faithful port of `NeoBrutalistTheme._createTheme`, using the new extensions instead of inline literals. The old file is not touched in this task.

- [ ] **Step 1: Write the failing composition test**

Create `test/core/theme/themes/brutalist_theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';

void main() {
  group('brutalistTheme', () {
    for (final b in [Brightness.light, Brightness.dark]) {
      for (final c in [false, true]) {
        test('attaches all five extensions for brightness=$b isCompact=$c', () {
          final theme = brutalistTheme(b, isCompact: c);
          expect(theme.extension<AppLayout>(), isNotNull);
          expect(theme.extension<AppPalette>(), isNotNull);
          expect(theme.extension<AppShape>(), isNotNull);
          expect(theme.extension<AppTypography>(), isNotNull);
          expect(theme.extension<AppDecoration>(), isNotNull);
          expect(theme.extension<AppLayout>()!.isCompact, c);
          expect(theme.brightness, b);
        });
      }
    }

    testWidgets('panelBox returns a BoxDecoration with brutalist hard shadow (blurRadius: 0)', (tester) async {
      final theme = brutalistTheme(Brightness.light);
      late BoxDecoration decoration;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(
          builder: (ctx) {
            decoration = ctx.appDecoration.panelBox(ctx);
            return const SizedBox.shrink();
          },
        ),
      ));
      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow!.first.blurRadius, 0);
      expect(decoration.boxShadow!.first.offset, Offset(ctxLayoutHeavy(theme), ctxLayoutHeavy(theme)));
    });

    testWidgets('wrapInteractive returns a widget that scales on tap-down', (tester) async {
      final theme = brutalistTheme(Brightness.light);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ctx.appDecoration.wrapInteractive(
                child: const SizedBox(width: 40, height: 40, key: ValueKey('target')),
                onTap: () {},
              ),
            ),
          ),
        ),
      ));

      final target = find.byKey(const ValueKey('target'));
      expect(target, findsOneWidget);
      expect(find.byType(ScaleTransition), findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 50));
      final scaleBefore = tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value;
      expect(scaleBefore, lessThan(1.0));
      await gesture.up();
      await tester.pumpAndSettle();
      final scaleAfter = tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value;
      expect(scaleAfter, 1.0);
    });
  });
}

double ctxLayoutHeavy(ThemeData t) => t.extension<AppLayout>()!.borderHeavy;
```

- [ ] **Step 2: Run test** → FAIL (builder does not exist).

- [ ] **Step 3: Implement `brutalistTheme`**

Create `lib/core/theme/themes/brutalist/brutalist_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import 'brutalist_bounce.dart';
import 'brutalist_decorations.dart';
import 'brutalist_palette.dart';

ThemeData brutalistTheme(Brightness brightness, {bool isCompact = false}) {
  final bool isDark = brightness == Brightness.dark;
  final Color background = isDark ? BrutalistPalette.backgroundDark : BrutalistPalette.backgroundLight;
  final Color surface = isDark ? BrutalistPalette.surfaceDark : BrutalistPalette.surfaceLight;
  final Color text = isDark ? BrutalistPalette.textDark : BrutalistPalette.textLight;
  final Color border = isDark ? BrutalistPalette.borderDark : BrutalistPalette.borderLight;
  final Color currentPrimary = isDark ? BrutalistPalette.primaryDark : BrutalistPalette.primary;
  final Color currentSecondary = isDark ? BrutalistPalette.secondaryDark : BrutalistPalette.secondary;

  final AppLayout layout = isCompact ? AppLayout.compact : AppLayout.normal;
  const AppShape shape = AppShape(panelRadius: 4, buttonRadius: 4, inputRadius: 4, dialogRadius: 8);

  final baseTextTheme = GoogleFonts.lexendTextTheme().apply(bodyColor: text, displayColor: text).copyWith(
    bodyMedium: GoogleFonts.lexendTextTheme().bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: text),
    bodySmall: GoogleFonts.lexendTextTheme().bodySmall?.copyWith(fontSize: 12, color: text),
    titleMedium: GoogleFonts.lexendTextTheme().titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: text),
    titleLarge: GoogleFonts.lexendTextTheme().titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: text),
  );

  final typography = AppTypography(
    base: baseTextTheme,
    codeFontFamily: GoogleFonts.jetBrainsMono().fontFamily!,
    displayWeight: FontWeight.w900,
    titleWeight: FontWeight.w700,
    bodyWeight: FontWeight.w500,
  );

  final palette = AppPalette(
    methodColors: BrutalistPalette.methodColors,
    methodFallback: BrutalistPalette.methodFallback,
    statusSuccess: Colors.green.shade700,
    statusWarning: Colors.orange.shade700,
    statusError: Colors.red.shade700,
    statusAccentSuccess: Colors.greenAccent,
    statusAccentWarning: Colors.orangeAccent,
    statusAccentError: Colors.redAccent,
    codeBackground: isDark ? BrutalistPalette.backgroundDark : Colors.white,
    mutedHover: Colors.black.withValues(alpha: 0.05),
  );

  final decoration = AppDecoration(
    panelBox: brutalistPanelBox,
    tabShape: brutalistTabShape,
    wrapInteractive: ({required child, onTap, scaleDown}) =>
        BrutalBounce(onTap: onTap, scaleDown: scaleDown ?? 0.95, child: child),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    primaryColor: currentPrimary,
    scaffoldBackgroundColor: background,
    canvasColor: surface,
    dividerColor: border,
    hoverColor: currentPrimary.withValues(alpha: 0.1),
    splashColor: currentPrimary.withValues(alpha: 0.2),
    colorScheme: isDark
        ? ColorScheme.dark(
            primary: currentPrimary,
            secondary: currentSecondary,
            surface: BrutalistPalette.surfaceDark,
            onPrimary: BrutalistPalette.textLight,
            onSecondary: Colors.white,
            onSurface: BrutalistPalette.textDark,
          )
        : ColorScheme.light(
            primary: currentPrimary,
            secondary: currentSecondary,
            surface: BrutalistPalette.surfaceLight,
            onPrimary: BrutalistPalette.textLight,
            onSecondary: Colors.white,
            onSurface: BrutalistPalette.textLight,
          ),
    textTheme: baseTextTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: layout.fontSizeSubtitle, color: text, fontWeight: FontWeight.w900),
      shape: Border(bottom: BorderSide(color: border, width: layout.borderThick)),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      labelColor: BrutalistPalette.textLight,
      unselectedLabelColor: text,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: currentPrimary,
        border: Border(
          top: BorderSide(color: border, width: layout.borderThick),
          left: BorderSide(color: border, width: layout.borderThick),
          right: BorderSide(color: border, width: layout.borderThick),
        ),
      ),
      labelStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: layout.fontSizeNormal),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: currentPrimary,
        foregroundColor: BrutalistPalette.textLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.buttonRadius),
          side: BorderSide(color: border, width: layout.borderThick),
        ),
        padding: EdgeInsets.symmetric(horizontal: layout.buttonPaddingHorizontal, vertical: layout.buttonPaddingVertical),
        textStyle: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: FontWeight.w900, color: BrutalistPalette.textLight),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.hovered)) return Colors.white.withValues(alpha: 0.2);
          if (states.contains(WidgetState.pressed)) return Colors.black.withValues(alpha: 0.1);
          return null;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: BorderSide(color: border, width: layout.borderThick),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(shape.buttonRadius)),
        padding: EdgeInsets.symmetric(horizontal: layout.buttonPaddingHorizontal, vertical: layout.buttonPaddingVertical),
        textStyle: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: FontWeight.w900),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: currentSecondary,
        textStyle: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: FontWeight.w900),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: border, width: layout.borderThick),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: border, width: layout.borderThick),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: currentSecondary, width: layout.borderThick),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      labelStyle: TextStyle(color: text, fontWeight: FontWeight.bold),
      hintStyle: TextStyle(color: text.withValues(alpha: 0.5)),
      contentPadding: EdgeInsets.symmetric(horizontal: layout.inputPadding, vertical: layout.inputPadding),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.panelRadius),
        side: BorderSide(color: border, width: layout.borderThick),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.dialogRadius),
        side: BorderSide(color: border, width: layout.borderHeavy),
      ),
      titleTextStyle: TextStyle(color: text, fontSize: layout.fontSizeSubtitle, fontWeight: FontWeight.w900),
      contentTextStyle: TextStyle(color: text, fontSize: layout.fontSizeTitle),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: currentPrimary,
      selectedColor: BrutalistPalette.textLight,
      titleTextStyle: TextStyle(fontWeight: FontWeight.bold, color: text),
      subtitleTextStyle: TextStyle(color: text.withValues(alpha: 0.7)),
    ),
  );

  return base.copyWith(extensions: [layout, palette, shape, typography, decoration]);
}
```

- [ ] **Step 4: Verify & Commit**

```
fvm flutter test test/core/theme/themes/brutalist_theme_test.dart
fvm flutter analyze
```

Both should be green.

```bash
git add lib/core/theme/themes/brutalist/brutalist_theme.dart test/core/theme/themes/brutalist_theme_test.dart
git commit -m "feat(theme): brutalistTheme builder + composition tests"
```

---

### Task 8: Theme registry + `resolveTheme`

**Files:**
- Create: `lib/core/theme/theme_registry.dart`
- Test: `test/core/theme/theme_registry_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/theme_registry_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';

void main() {
  group('theme_registry', () {
    test('appThemes contains the default entry', () {
      expect(appThemes[defaultThemeId], isNotNull);
    });

    test('resolveTheme returns default for null', () {
      final builder = resolveTheme(null);
      expect(builder, appThemes[defaultThemeId]);
    });

    test('resolveTheme returns default for unknown id', () {
      final builder = resolveTheme('does-not-exist');
      expect(builder, appThemes[defaultThemeId]);
    });

    test('resolveTheme returns registered builder for known id', () {
      final builder = resolveTheme(kBrutalistThemeId);
      expect(builder, appThemes[kBrutalistThemeId]);
    });

    test('registered builder returns a usable ThemeData', () {
      final theme = resolveTheme(kBrutalistThemeId)(Brightness.light, isCompact: false);
      expect(theme, isA<ThemeData>());
    });
  });
}
```

- [ ] **Step 2: Run test** → FAIL.

- [ ] **Step 3: Create `lib/core/theme/theme_registry.dart`**

```dart
import 'package:flutter/material.dart';
import 'theme_ids.dart';
import 'themes/brutalist/brutalist_theme.dart';

typedef AppThemeBuilder = ThemeData Function(Brightness brightness, {bool isCompact});

const String defaultThemeId = kBrutalistThemeId;

const Map<String, AppThemeBuilder> appThemes = {
  kBrutalistThemeId: brutalistTheme,
};

AppThemeBuilder resolveTheme(String? themeId) =>
    appThemes[themeId] ?? appThemes[defaultThemeId]!;
```

- [ ] **Step 4: Verify & Commit**

```
fvm flutter test test/core/theme/theme_registry_test.dart
fvm flutter analyze
git add lib/core/theme/theme_registry.dart test/core/theme/theme_registry_test.dart
git commit -m "feat(theme): add theme registry and resolveTheme helper"
```

---

### Task 9: Add `themeId` to Settings (entity + Hive model)

**Files:**
- Modify: `lib/features/settings/domain/entities/settings_entity.dart`
- Modify: `lib/features/settings/data/models/settings_model.dart`
- Regenerate: `lib/features/settings/data/models/settings_model.g.dart` (via build_runner)
- Test: `test/features/settings/data/models/settings_model_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/settings/data/models/settings_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';

void main() {
  group('SettingsModel themeId', () {
    test('fromEntity default themeId is brutalist', () {
      final model = SettingsModel.fromEntity(const SettingsEntity());
      expect(model.themeId, 'brutalist');
    });

    test('json roundtrip preserves themeId', () {
      final model = SettingsModel(themeId: 'editorial');
      final roundTripped = SettingsModel.fromJson(model.toJson());
      expect(roundTripped.themeId, 'editorial');
    });

    test('entity roundtrip preserves themeId', () {
      const entity = SettingsEntity(themeId: 'editorial');
      final model = SettingsModel.fromEntity(entity);
      expect(model.toEntity().themeId, 'editorial');
    });

    test('copyWith overrides themeId but keeps other fields', () {
      final original = SettingsModel(themeId: 'brutalist', historyLimit: 50);
      final copy = original.copyWith(themeId: 'editorial');
      expect(copy.themeId, 'editorial');
      expect(copy.historyLimit, 50);
    });
  });
}
```

- [ ] **Step 2: Run test** → FAIL (`SettingsEntity` and `SettingsModel` don't accept `themeId`).

- [ ] **Step 3: Edit `SettingsEntity`**

Replace the entire file `lib/features/settings/domain/entities/settings_entity.dart`:

```dart
import 'package:equatable/equatable.dart';

class SettingsEntity extends Equatable {
  final int historyLimit;
  final bool saveResponseInHistory;
  final bool isDarkMode;
  final bool isCompactMode;
  final bool isVerticalLayout;
  final double splitRatio;
  final double sideMenuWidth;
  final String themeId;

  const SettingsEntity({
    this.historyLimit = 100,
    this.saveResponseInHistory = false,
    this.isDarkMode = false,
    this.isCompactMode = false,
    this.isVerticalLayout = false,
    this.splitRatio = 0.5,
    this.sideMenuWidth = 300.0,
    this.themeId = 'brutalist',
  });

  SettingsEntity copyWith({
    int? historyLimit,
    bool? saveResponseInHistory,
    bool? isDarkMode,
    bool? isCompactMode,
    bool? isVerticalLayout,
    double? splitRatio,
    double? sideMenuWidth,
    String? themeId,
  }) {
    return SettingsEntity(
      historyLimit: historyLimit ?? this.historyLimit,
      saveResponseInHistory: saveResponseInHistory ?? this.saveResponseInHistory,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      isCompactMode: isCompactMode ?? this.isCompactMode,
      isVerticalLayout: isVerticalLayout ?? this.isVerticalLayout,
      splitRatio: splitRatio ?? this.splitRatio,
      sideMenuWidth: sideMenuWidth ?? this.sideMenuWidth,
      themeId: themeId ?? this.themeId,
    );
  }

  @override
  List<Object?> get props => [
    historyLimit,
    saveResponseInHistory,
    isDarkMode,
    isCompactMode,
    isVerticalLayout,
    splitRatio,
    sideMenuWidth,
    themeId,
  ];
}
```

- [ ] **Step 4: Edit `SettingsModel`**

Replace the entire file `lib/features/settings/data/models/settings_model.dart`:

```dart
import 'package:hive/hive.dart';
import '../../domain/entities/settings_entity.dart';

part 'settings_model.g.dart';

@HiveType(typeId: 0)
class SettingsModel extends HiveObject {
  @HiveField(0, defaultValue: 100)
  int historyLimit;

  @HiveField(1, defaultValue: false)
  bool saveResponseInHistory;

  @HiveField(2, defaultValue: false)
  bool isDarkMode;

  @HiveField(3, defaultValue: false)
  bool isCompactMode;

  @HiveField(4, defaultValue: false)
  bool isVerticalLayout;

  @HiveField(5, defaultValue: 0.5)
  double splitRatio;

  @HiveField(6, defaultValue: 300.0)
  double sideMenuWidth;

  @HiveField(7, defaultValue: 'brutalist')
  String themeId;

  SettingsModel({
    this.historyLimit = 100,
    this.saveResponseInHistory = false,
    this.isDarkMode = false,
    this.isCompactMode = false,
    this.isVerticalLayout = false,
    this.splitRatio = 0.5,
    this.sideMenuWidth = 300.0,
    this.themeId = 'brutalist',
  });

  SettingsModel copyWith({
    int? historyLimit,
    bool? saveResponseInHistory,
    bool? isDarkMode,
    bool? isCompactMode,
    bool? isVerticalLayout,
    double? splitRatio,
    double? sideMenuWidth,
    String? themeId,
  }) {
    return SettingsModel(
      historyLimit: historyLimit ?? this.historyLimit,
      saveResponseInHistory: saveResponseInHistory ?? this.saveResponseInHistory,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      isCompactMode: isCompactMode ?? this.isCompactMode,
      isVerticalLayout: isVerticalLayout ?? this.isVerticalLayout,
      splitRatio: splitRatio ?? this.splitRatio,
      sideMenuWidth: sideMenuWidth ?? this.sideMenuWidth,
      themeId: themeId ?? this.themeId,
    );
  }

  Map<String, dynamic> toJson() => {
    'historyLimit': historyLimit,
    'saveResponseInHistory': saveResponseInHistory,
    'isDarkMode': isDarkMode,
    'isCompactMode': isCompactMode,
    'isVerticalLayout': isVerticalLayout,
    'splitRatio': splitRatio,
    'sideMenuWidth': sideMenuWidth,
    'themeId': themeId,
  };

  factory SettingsModel.fromJson(Map<String, dynamic> json) => SettingsModel(
    historyLimit: json['historyLimit'] ?? 100,
    saveResponseInHistory: json['saveResponseInHistory'] ?? false,
    isDarkMode: json['isDarkMode'] ?? false,
    isCompactMode: json['isCompactMode'] ?? false,
    isVerticalLayout: json['isVerticalLayout'] ?? false,
    splitRatio: json['splitRatio'] ?? 0.5,
    sideMenuWidth: (json['sideMenuWidth'] ?? 300.0).toDouble(),
    themeId: json['themeId'] ?? 'brutalist',
  );

  factory SettingsModel.fromEntity(SettingsEntity entity) => SettingsModel(
    historyLimit: entity.historyLimit,
    saveResponseInHistory: entity.saveResponseInHistory,
    isDarkMode: entity.isDarkMode,
    isCompactMode: entity.isCompactMode,
    isVerticalLayout: entity.isVerticalLayout,
    splitRatio: entity.splitRatio,
    sideMenuWidth: entity.sideMenuWidth,
    themeId: entity.themeId,
  );

  SettingsEntity toEntity() => SettingsEntity(
    historyLimit: historyLimit,
    saveResponseInHistory: saveResponseInHistory,
    isDarkMode: isDarkMode,
    isCompactMode: isCompactMode,
    isVerticalLayout: isVerticalLayout,
    splitRatio: splitRatio,
    sideMenuWidth: sideMenuWidth,
    themeId: themeId,
  );
}
```

- [ ] **Step 5: Regenerate the Hive adapter**

Run:
```
dart run build_runner build --delete-conflicting-outputs
```
Expected: `Succeeded after …` with `settings_model.g.dart` updated to include a `readByte() == 7` branch for `themeId`.

- [ ] **Step 6: Verify & Commit**

```
fvm flutter test test/features/settings/data/models/settings_model_test.dart
fvm flutter analyze
fvm flutter test
```
All green.

```bash
git add lib/features/settings/domain/entities/settings_entity.dart lib/features/settings/data/models/settings_model.dart lib/features/settings/data/models/settings_model.g.dart test/features/settings/data/models/settings_model_test.dart
git commit -m "feat(settings): add themeId field (HiveField 7, default 'brutalist')"
```

---

### Task 10: `UpdateThemeId` event + bloc handler

**Files:**
- Modify: `lib/features/settings/presentation/bloc/settings_event.dart`
- Modify: `lib/features/settings/presentation/bloc/settings_bloc.dart`

- [ ] **Step 1: Append `UpdateThemeId` to `settings_event.dart`**

Add to `lib/features/settings/presentation/bloc/settings_event.dart`:

```dart
class UpdateThemeId extends SettingsEvent {
  final String themeId;
  const UpdateThemeId(this.themeId);
  @override
  List<Object?> get props => [themeId];
}
```

- [ ] **Step 2: Register handler in `settings_bloc.dart`**

In the constructor of `SettingsBloc`, add after the existing `on<…>` registrations:

```dart
on<UpdateThemeId>(_onUpdateThemeId);
```

And add the handler method:

```dart
Future<void> _onUpdateThemeId(UpdateThemeId event, Emitter<SettingsState> emit) async {
  final newSettings = state.settings.copyWith(themeId: event.themeId);
  await saveSettingsUseCase(newSettings);
  emit(state.copyWith(settings: newSettings));
}
```

- [ ] **Step 3: Verify & Commit**

```
fvm flutter analyze
fvm flutter test
```
Both green.

```bash
git add lib/features/settings/presentation/bloc/settings_event.dart lib/features/settings/presentation/bloc/settings_bloc.dart
git commit -m "feat(settings): add UpdateThemeId event + handler"
```

---

### Task 11: Swap `main.dart` to use the registry

**Files:**
- Modify: `lib/main.dart`

After this task, the new `brutalistTheme` builder becomes the live theme. `NeoBrutalistTheme.theme(...)` is no longer called, but `NeoBrutalistTheme.brutalBox` / `brutalTab` / `getMethodColor` remain present as static helpers so widgets that still call them continue to work.

- [ ] **Step 1: Edit `lib/main.dart`**

Replace the import:
```dart
import 'core/theme/neo_brutalist_theme.dart';
```
with:
```dart
import 'core/theme/theme_registry.dart';
```

Replace the two theme lines inside `MaterialApp.router`:
```dart
theme: NeoBrutalistTheme.theme(Brightness.light, isCompact: settings.isCompactMode),
darkTheme: NeoBrutalistTheme.theme(Brightness.dark, isCompact: settings.isCompactMode),
```
with:
```dart
theme: resolveTheme(settings.themeId)(Brightness.light, isCompact: settings.isCompactMode),
darkTheme: resolveTheme(settings.themeId)(Brightness.dark, isCompact: settings.isCompactMode),
```

- [ ] **Step 2: Verify**

```
fvm flutter analyze
fvm flutter test
```
Both green.

Also run the app and smoke-test:
```
fvm flutter run -d macos
```
Verify the app looks identical to before. Toggle dark mode (Settings), toggle compact mode, open a dialog, click a button (bounce is present), send a request. Kill the app when satisfied.

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat(theme): swap main.dart to resolveTheme registry"
```

---

### Task 12a: Migrate `splitter.dart` and `method_badge.dart`

**Files:**
- Modify: `lib/core/ui/widgets/splitter.dart`
- Modify: `lib/core/ui/widgets/method_badge.dart`

Smallest widgets first — good smoke test for the new API.

- [ ] **Step 1: Migrate `method_badge.dart`**

Open the file. Replace `NeoBrutalistTheme.getMethodColor(method)` with `context.appPalette.methodColor(method)`. Update imports: remove `import 'package:getman/core/theme/neo_brutalist_theme.dart';`, add `import 'package:getman/core/theme/app_theme.dart';`.

- [ ] **Step 2: Migrate `splitter.dart`**

Change `BorderRadius.circular(2)` to `BorderRadius.circular(context.appShape.panelRadius / 2)` (the original 2 was half of the panel radius 4; keeps the visual). Update imports: add `import 'package:getman/core/theme/app_theme.dart';` if not already importing.

- [ ] **Step 3: Verify**

```
fvm flutter analyze
fvm flutter test
```
Green. The `widget_test.dart` will still have `NeoBrutalistTheme.getMethodColor` assertion — that's fine, it's still a valid static call in the old file. We update that test in Task 12e.

- [ ] **Step 4: Commit**

```bash
git add lib/core/ui/widgets/splitter.dart lib/core/ui/widgets/method_badge.dart
git commit -m "refactor(ui): migrate splitter + method_badge to AppTheme API"
```

---

### Task 12b: Migrate `main_screen.dart`

**Files:**
- Modify: `lib/features/home/presentation/screens/main_screen.dart`

Replacements (use `Grep` + `Edit` — exact count per pattern):
- `BrutalBounce(onTap: X, child: Y)` (2 occurrences) → `context.appDecoration.wrapInteractive(onTap: X, child: Y)`.
- `NeoBrutalistTheme.brutalBox(context, ...)` (0 occurrences in this file — grep confirms).
- `fontSize: 18` on the `NO OPEN TABS` title → `fontSize: context.appLayout.fontSizeSubtitle`.
- `fontSize: 12` on the sub-hint → `fontSize: context.appLayout.fontSizeNormal`.
- `fontSize: 12` in `_buildShortcutHint` → `fontSize: context.appLayout.fontSizeNormal`.
- `BorderRadius.circular(4)` → `BorderRadius.circular(context.appShape.panelRadius)`.
- `const EdgeInsets.symmetric(horizontal: 24, vertical: 16)` on the "NEW REQUEST" button: keep (it's an inline button style override that was already scaled); swap to `EdgeInsets.symmetric(horizontal: context.appLayout.buttonPaddingHorizontal, vertical: context.appLayout.buttonPaddingVertical)` for consistency, and drop the `const`.

Update imports: remove `import 'package:getman/core/theme/neo_brutalist_theme.dart';`, add `import 'package:getman/core/theme/app_theme.dart';` and `import 'package:getman/core/theme/themes/brutalist/brutalist_bounce.dart';` only if `BrutalBounce` is still directly referenced. (It should no longer be after this migration — grep `BrutalBounce` in the file after edits, expect zero hits.)

- [ ] **Step 1: Make the edits** (follow the list above)

- [ ] **Step 2: Verify**

```
fvm flutter analyze
fvm flutter test
```
Green.

- [ ] **Step 3: Commit**

```bash
git add lib/features/home/presentation/screens/main_screen.dart
git commit -m "refactor(home): migrate main_screen.dart to AppTheme API"
```

---

### Task 12c: Migrate `side_menu.dart`

**Files:**
- Modify: `lib/features/home/presentation/widgets/side_menu.dart`

Replacements:
- `BrutalBounce(...)` (4 occurrences) → `context.appDecoration.wrapInteractive(...)`.
- `NeoBrutalistTheme.brutalBox(context, ...)` (1 occurrence at line 724) → `context.appDecoration.panelBox(context, ...)`.
- `BorderRadius.circular(4)` (2 occurrences at lines 362, 566, 755) → `BorderRadius.circular(context.appShape.panelRadius)`.
- `fontSize: 12` at line 394 → `fontSize: context.appLayout.fontSizeNormal`.

Update imports: remove `NeoBrutalistTheme` import, add `app_theme.dart` import.

- [ ] **Step 1: Edits**
- [ ] **Step 2: Verify** (`fvm flutter analyze && fvm flutter test`)
- [ ] **Step 3: Commit**

```bash
git add lib/features/home/presentation/widgets/side_menu.dart
git commit -m "refactor(home): migrate side_menu.dart to AppTheme API"
```

---

### Task 12d: Migrate `request_view.dart`

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/request_view.dart`

Replacements:
- `BrutalBounce(...)` (6 occurrences at 407, 425, 460, 468, 639, 1138) → `context.appDecoration.wrapInteractive(...)`.
- `NeoBrutalistTheme.brutalBox(context, offset: N)` (3 occurrences at 336, 566, 770) → `context.appDecoration.panelBox(context, offset: N)`.
- `NeoBrutalistTheme.getMethodColor(m)` (2 occurrences at 359, 373) → `context.appPalette.methodColor(m)`.
- `BorderRadius.circular(4)` (3 occurrences at 223, 927, 1107) → `BorderRadius.circular(context.appShape.panelRadius)`.
- `fontSize: 12` at line 226 → `context.appLayout.fontSizeNormal`.
- `fontSize: 13` at lines 613 and 839 (code editor) → `context.appLayout.fontSizeCode`.

Update imports.

- [ ] **Step 1: Edits**
- [ ] **Step 2: Verify**
- [ ] **Step 3: Commit**

```bash
git add lib/features/tabs/presentation/widgets/request_view.dart
git commit -m "refactor(tabs): migrate request_view.dart to AppTheme API"
```

---

### Task 12e: Update `test/widget_test.dart`

**Files:**
- Modify: `test/widget_test.dart`

Replace the old imports and helper. Final file content:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_methods.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/theme_ids.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_palette.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';

Widget _wrap(Widget child, {bool dark = false, bool compact = false}) {
  return MaterialApp(
    theme: resolveTheme(kBrutalistThemeId)(
      dark ? Brightness.dark : Brightness.light,
      isCompact: compact,
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('MethodBadge renders every supported HTTP method without crashing', (tester) async {
    for (final method in HttpMethods.all) {
      await tester.pumpWidget(_wrap(MethodBadge(method: method)));
      expect(find.text(method), findsOneWidget);
    }
  });

  testWidgets('MethodBadge uses the palette-driven method color', (tester) async {
    await tester.pumpWidget(_wrap(const MethodBadge(method: 'GET')));
    final container = tester.widget<Container>(
      find.ancestor(of: find.text('GET'), matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, BrutalistPalette.methodColors['GET']);
  });

  testWidgets('MethodBadge renders in both compact and normal layouts', (tester) async {
    await tester.pumpWidget(_wrap(const MethodBadge(method: 'POST'), compact: true));
    expect(find.text('POST'), findsOneWidget);

    await tester.pumpWidget(_wrap(const MethodBadge(method: 'POST')));
    expect(find.text('POST'), findsOneWidget);
  });

  testWidgets('MethodBadge renders in dark theme', (tester) async {
    await tester.pumpWidget(_wrap(const MethodBadge(method: 'DELETE'), dark: true));
    expect(find.text('DELETE'), findsOneWidget);
  });
}
```

- [ ] **Step 1: Edit the file** as above.
- [ ] **Step 2: Verify** (`fvm flutter analyze && fvm flutter test`)
- [ ] **Step 3: Commit**

```bash
git add test/widget_test.dart
git commit -m "test: update widget_test.dart to use theme registry + BrutalistPalette"
```

---

### Task 13: Delete the old theme file and `StatusColor`

**Files:**
- Delete: `lib/core/theme/neo_brutalist_theme.dart`
- Delete: `lib/core/utils/status_color.dart`

- [ ] **Step 1: Grep for leftover references**

Run (using the Grep tool or equivalent):
- `NeoBrutalistTheme` across `lib/**/*.dart` and `test/**/*.dart` — expect zero hits.
- `BrutalBounce` across `lib/**/*.dart` and `test/**/*.dart` — expect hits **only** in `lib/core/theme/themes/brutalist/brutalist_bounce.dart` and `lib/core/theme/themes/brutalist/brutalist_theme.dart` (the class and its one internal usage).
- `StatusColor` across `lib/**/*.dart` and `test/**/*.dart` — expect zero hits. (If any remain from places we didn't inventory, replace with `context.appPalette.statusColor(code)` / `.statusAccent(code)` and re-run the grep.)
- `LayoutExtension` — expect zero hits.

- [ ] **Step 2: Delete the files**

```
rm lib/core/theme/neo_brutalist_theme.dart
rm lib/core/utils/status_color.dart
```

- [ ] **Step 3: Verify**

```
fvm flutter analyze
fvm flutter test
```
Both green.

- [ ] **Step 4: Commit**

```bash
git add -A lib/core/theme/neo_brutalist_theme.dart lib/core/utils/status_color.dart
git commit -m "chore: remove obsolete NeoBrutalistTheme and StatusColor"
```

---

### Task 14: Final verification

**Files:** none.

- [ ] **Step 1: Clean analyze + tests**

Run:
```
fvm flutter analyze
fvm flutter test
```
Expected: `No issues found!` and 100% green.

- [ ] **Step 2: Update CLAUDE.md**

The project doc currently references `NeoBrutalistTheme`, `LayoutExtension`, `StatusColor`, and `BrutalBounce` as existing constructs. Sync §2, §4.8, §6 of `CLAUDE.md` with the new reality:
- Replace "`NeoBrutalistTheme.theme(...)`" with "the active theme builder from `theme_registry.dart`".
- Replace "`LayoutExtension`" with "`AppLayout`".
- Replace "`NeoBrutalistTheme.getMethodColor()`" with "`context.appPalette.methodColor()`".
- Replace "`StatusColor.forCode()` / `.forCodeAccent()`" with "`context.appPalette.statusColor() / .statusAccent()`".
- Replace "`NeoBrutalistTheme.brutalBox(...)`" with "`context.appDecoration.panelBox(...)`".
- Replace the `BrutalBounce` bullet with "`context.appDecoration.wrapInteractive({child, onTap, scaleDown})` — wraps a tappable element in theme-defined interaction behavior (brutalist = scale bounce). Never reference `BrutalBounce` directly outside `lib/core/theme/themes/brutalist/`."
- Update §2 file tree to reflect the new `core/theme/` directory layout.

- [ ] **Step 3: Run the app on macOS**

```
fvm flutter run -d macos
```

Manual checklist:
- [ ] App visually identical to prior build.
- [ ] Dark-mode toggle flips colors correctly.
- [ ] Compact-mode toggle shrinks paddings/fonts correctly.
- [ ] Open a dialog — shadow and radius match brutalist aesthetic.
- [ ] Tap buttons — scale bounce still fires.
- [ ] Drag a tab — tab shape border matches prior behavior.
- [ ] Send a request — response area renders, status code pill uses palette color.
- [ ] Open a collections folder in the side menu — hover/selected tile styling intact.
- [ ] JSON code editor in body / response panel renders at the expected font size.

- [ ] **Step 4: Commit the CLAUDE.md sync**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for pluggable theme architecture"
```

Implementation complete.

---

## Self-review notes

- Every spec section is covered: §2 (architecture) → Tasks 1–8; §3 (runtime flow) → Tasks 9–11; §4 (widget migration) → Tasks 12a–12e; §5 (testing) → tests added in Tasks 1–9; §6 (migration plan) → Tasks 1–14; §7 (risks) → addressed inline (Hive `defaultValue`, closure `lerp` returns `this`, `BrutalBounce` ends up only inside `themes/brutalist/`, CLAUDE.md updated).
- Types and names are consistent across tasks: `AppLayout`, `AppPalette`, `AppShape`, `AppTypography`, `AppDecoration`, `AppThemeAccess`, `PanelBoxBuilder`, `TabShapeBuilder`, `InteractiveWrapper`, `brutalistTheme`, `brutalistPanelBox`, `brutalistTabShape`, `BrutalBounce`, `kBrutalistThemeId`, `defaultThemeId`, `appThemes`, `resolveTheme`, `UpdateThemeId`.
- No placeholders remain. No "TBD"/"TODO"/"similar to task N without code"/"handle edge cases" style instructions. The two new `AppLayout` fields (`fontSizeCode`, `fontSizeSubtitle`) are introduced in Task 1 and consumed in Tasks 12b/12d — aligned.
