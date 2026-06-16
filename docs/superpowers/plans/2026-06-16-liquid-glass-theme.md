# Liquid Glass Theme + Global Effects Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fifth theme, **LIQUID GLASS** (Apple-style frosted translucency with real backdrop blur, light "Clear" + dark "Smoked"), plus a global "reduce visual effects" setting that gates blur/animation across themes.

**Architecture:** A new self-contained theme under `lib/core/theme/themes/glass/`, registered via `ThemeDescriptor`. One new `AppDecoration.frost` hook (identity-default, so the other four themes are byte-for-byte unchanged) wraps panels in `ClipRRect + BackdropFilter`. A new persisted `SettingsEntity.reduceVisualEffects` flag is threaded into every theme builder (uniform signature) and the `resolveThemeData` cache; the glass builder uses it to choose `frost` vs identity, animated vs static wallpaper, and animated vs instant press. The glass `scaffoldBackgroundColor` is transparent so the theme's mesh-gradient wallpaper shows through and panels read as glass over it.

**Tech Stack:** Flutter, `flutter_bloc`, `hive_ce` (+ `hive_ce_generator`), `google_fonts` (Inter + JetBrains Mono), `dart:ui` `ImageFilter` for blur. Invoke Flutter as `fvm flutter ...`.

**Conventions (read once):**
- All commands use `fvm`. Verification bar (must all be clean before "done"): `fvm flutter analyze`, `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib`, `fvm dart format lib test tools`, `fvm flutter test`.
- The `.githooks/pre-commit` hook runs analyze + both lints + format on every commit. Commit messages end with the `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer.
- Imports are always `package:getman/...` (no relative imports), and directives are ordered (dart, then package) — the analyzer enforces both.
- `avoid_hardcoded_brand_colors` (custom_lint) forbids `Colors.black/white/red` **outside** `lib/core/theme/`. All glass color literals live under `lib/core/theme/themes/glass/`, so they are allowed there.

---

## File Structure

**New files:**
- `lib/core/theme/themes/glass/glass_palette.dart` — raw colors (light "Clear" + dark "Smoked").
- `lib/core/theme/themes/glass/glass_decorations.dart` — `glassPanelBox`, `glassTabShape`, `glassFrost`, `kGlassBlurSigma`, `GlassWallpaper` widget + `glassScaffoldBackground` / `glassStaticScaffoldBackground`.
- `lib/core/theme/themes/glass/glass_press.dart` — `GlassPress` interactive wrapper.
- `lib/core/theme/themes/glass/glass_theme.dart` — `glassTheme(Brightness, {isCompact, reduceEffects})`.
- `test/core/theme/themes/glass_theme_test.dart` — theme tests.

**Modified files:**
- `lib/core/theme/extensions/app_decoration.dart` — `FrostWrapper` typedef + `frost` field (identity default).
- `lib/core/theme/theme_ids.dart` — `kGlassThemeId`.
- `lib/core/theme/theme_registry.dart` — `AppThemeBuilder` typedef gains `reduceEffects`; register glass; `resolveTheme*` + cache gain the dimension.
- `lib/core/theme/themes/{brutalist,editorial,dracula,rpg}/*_theme.dart` — add `reduceEffects` param to the builder signature.
- `lib/core/theme/themes/rpg/rpg_decorations.dart` — add `rpgStaticScaffoldBackground`.
- `lib/core/theme/themes/rpg/rpg_sparkle.dart` — add `sparkle` flag.
- `lib/main.dart` — `buildWhen` + both `resolveThemeData` calls pass `reduceEffects`.
- `lib/features/settings/domain/entities/settings_entity.dart` — `reduceVisualEffects` field.
- `lib/features/settings/data/models/settings_model.dart` (+ regenerated `.g.dart`) — `@HiveField(22)`.
- `lib/features/settings/presentation/bloc/settings_event.dart` — `UpdateReduceVisualEffects`.
- `lib/features/settings/presentation/bloc/settings_bloc.dart` — handler.
- `lib/features/settings/presentation/widgets/settings_dialog.dart` — toggle UI.
- ~8 panel/overlay call sites — wrap in `frost`.
- `test/features/settings/data/models/settings_model_test.dart` — round-trip tests.

---

## Task 1: Add the `frost` hook to `AppDecoration` (identity default)

**Files:**
- Modify: `lib/core/theme/extensions/app_decoration.dart`
- Test: `test/core/theme/extensions/app_decoration_frost_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/extensions/app_decoration_frost_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('default frost returns the child unchanged (identity)', (
    tester,
  ) async {
    const child = SizedBox(key: ValueKey('frost_child'));
    late Widget result;
    await tester.pumpWidget(
      MaterialApp(
        theme: brutalistTheme(Brightness.light),
        home: Builder(
          builder: (ctx) {
            result = ctx.appDecoration.frost(ctx, child: child);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(identical(result, child), isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/core/theme/extensions/app_decoration_frost_test.dart`
Expected: FAIL — `The method 'frost' isn't defined for the type 'AppDecoration'`.

- [ ] **Step 3: Implement the `frost` hook**

In `lib/core/theme/extensions/app_decoration.dart`, add the typedef + identity function near the other typedefs (after `ScaffoldBackgroundWrapper`):

```dart
typedef FrostWrapper =
    Widget Function(
      BuildContext context, {
      required Widget child,
      BorderRadius? borderRadius,
    });

/// Default [FrostWrapper]: returns [child] unchanged. Themes that don't frost
/// (everything except Liquid Glass) inherit this via the constructor default,
/// so they are completely unaffected by the hook.
Widget _identityFrost(
  BuildContext context, {
  required Widget child,
  BorderRadius? borderRadius,
}) => child;
```

Then add the field + constructor default + copyWith param to `AppDecoration`:

```dart
class AppDecoration extends ThemeExtension<AppDecoration> {
  const AppDecoration({
    required this.panelBox,
    required this.tabShape,
    required this.wrapInteractive,
    required this.scaffoldBackground,
    this.frost = _identityFrost,
  });
  final PanelBoxBuilder panelBox;
  final TabShapeBuilder tabShape;
  final InteractiveWrapper wrapInteractive;
  final ScaffoldBackgroundWrapper scaffoldBackground;

  /// Wraps a panel in real frosted-glass blur (`ClipRRect` + `BackdropFilter`).
  /// Identity for every theme except Liquid Glass.
  final FrostWrapper frost;

  @override
  AppDecoration copyWith({
    PanelBoxBuilder? panelBox,
    TabShapeBuilder? tabShape,
    InteractiveWrapper? wrapInteractive,
    ScaffoldBackgroundWrapper? scaffoldBackground,
    FrostWrapper? frost,
  }) {
    return AppDecoration(
      panelBox: panelBox ?? this.panelBox,
      tabShape: tabShape ?? this.tabShape,
      wrapInteractive: wrapInteractive ?? this.wrapInteractive,
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      frost: frost ?? this.frost,
    );
  }

  @override
  AppDecoration lerp(ThemeExtension<AppDecoration>? other, double t) => this;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `fvm flutter test test/core/theme/extensions/app_decoration_frost_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/extensions/app_decoration.dart test/core/theme/extensions/app_decoration_frost_test.dart
git commit -m "feat(theme): add AppDecoration.frost hook (identity default)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Add the `reduceVisualEffects` setting (entity, model, event, handler)

**Files:**
- Modify: `lib/features/settings/domain/entities/settings_entity.dart`
- Modify: `lib/features/settings/data/models/settings_model.dart` (+ regenerate `settings_model.g.dart`)
- Modify: `lib/features/settings/presentation/bloc/settings_event.dart`
- Modify: `lib/features/settings/presentation/bloc/settings_bloc.dart`
- Test: `test/features/settings/data/models/settings_model_test.dart`

- [ ] **Step 1: Write the failing test**

Append this group inside `void main()` in `test/features/settings/data/models/settings_model_test.dart`:

```dart
  group('SettingsModel reduceVisualEffects', () {
    test('default is false (full effects)', () {
      expect(const SettingsEntity().reduceVisualEffects, isFalse);
      expect(SettingsModel().reduceVisualEffects, isFalse);
    });

    test('json roundtrip preserves the flag', () {
      final model = SettingsModel(reduceVisualEffects: true);
      final back = SettingsModel.fromJson(model.toJson());
      expect(back.reduceVisualEffects, isTrue);
    });

    test('entity roundtrip preserves the flag', () {
      const entity = SettingsEntity(reduceVisualEffects: true);
      final back = SettingsModel.fromEntity(entity).toEntity();
      expect(back.reduceVisualEffects, isTrue);
    });

    test('legacy json without the field defaults to false', () {
      final back = SettingsModel.fromJson({'historyLimit': 50});
      expect(back.reduceVisualEffects, isFalse);
    });

    test('copyWith overrides the flag but keeps other fields', () {
      const original = SettingsEntity(historyLimit: 50);
      final copy = original.copyWith(reduceVisualEffects: true);
      expect(copy.reduceVisualEffects, isTrue);
      expect(copy.historyLimit, 50);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/features/settings/data/models/settings_model_test.dart`
Expected: FAIL — `The named parameter 'reduceVisualEffects' isn't defined`.

- [ ] **Step 3: Add the field to `SettingsEntity`**

In `lib/features/settings/domain/entities/settings_entity.dart`:

1. Add to the constructor (after `this.isCompactMode = false,`):
```dart
    this.reduceVisualEffects = false,
```
2. Add the field (after `final bool isCompactMode;`):
```dart
  /// When `true`, themes drop expensive effects (backdrop blur, animated
  /// backgrounds) for performance. Default `false` = full effects everywhere.
  final bool reduceVisualEffects;
```
3. Add to `copyWith` params (after `bool? isCompactMode,`):
```dart
    bool? reduceVisualEffects,
```
4. Add to the `copyWith` body (after `isCompactMode: isCompactMode ?? this.isCompactMode,`):
```dart
      reduceVisualEffects: reduceVisualEffects ?? this.reduceVisualEffects,
```
5. Add to `props` (after `isCompactMode,`):
```dart
    reduceVisualEffects,
```

- [ ] **Step 4: Add the field to `SettingsModel`**

In `lib/features/settings/data/models/settings_model.dart`:

1. Constructor (after `this.isCompactMode = false,`): `this.reduceVisualEffects = false,`
2. `fromJson` (after the `isCompactMode:` line):
```dart
    reduceVisualEffects: json['reduceVisualEffects'] as bool? ?? false,
```
3. `fromEntity` (after the `isCompactMode:` line):
```dart
    reduceVisualEffects: entity.reduceVisualEffects,
```
4. New `@HiveField` (place after the `clientCertPassphrase` field at HiveField 21 — **22 is the next free id per CLAUDE.md §3**):
```dart
  @HiveField(22, defaultValue: false)
  bool reduceVisualEffects;
```
5. `copyWith` param (after `bool? isCompactMode,`): `bool? reduceVisualEffects,`
6. `copyWith` body (after the `isCompactMode:` line):
```dart
      reduceVisualEffects: reduceVisualEffects ?? this.reduceVisualEffects,
```
7. `toJson` (after `'isCompactMode': isCompactMode,`): `'reduceVisualEffects': reduceVisualEffects,`
8. `toEntity` (after the `isCompactMode:` line): `reduceVisualEffects: reduceVisualEffects,`

- [ ] **Step 5: Regenerate the Hive adapter**

Run: `fvm dart run build_runner build --delete-conflicting-outputs`
Expected: regenerates `settings_model.g.dart` with field 22; "Succeeded" output.

- [ ] **Step 6: Run the model test to verify it passes**

Run: `fvm flutter test test/features/settings/data/models/settings_model_test.dart`
Expected: PASS.

- [ ] **Step 7: Add the event**

In `lib/features/settings/presentation/bloc/settings_event.dart`, add after `UpdateCompactMode`:

```dart
class UpdateReduceVisualEffects extends SettingsEvent {
  const UpdateReduceVisualEffects({required this.value});
  final bool value;
  @override
  List<Object?> get props => [value];
}
```

- [ ] **Step 8: Add the handler**

In `lib/features/settings/presentation/bloc/settings_bloc.dart`, add inside the constructor body after the `on<UpdateCompactMode>(...)` registration:

```dart
    on<UpdateReduceVisualEffects>(
      (e, emit) =>
          _apply(emit, (s) => s.copyWith(reduceVisualEffects: e.value)),
    );
```

- [ ] **Step 9: Verify analyze + full model test**

Run: `fvm flutter analyze && fvm flutter test test/features/settings/`
Expected: "No issues found!" and all settings tests PASS.

- [ ] **Step 10: Commit**

```bash
git add lib/features/settings test/features/settings/data/models/settings_model_test.dart
git commit -m "feat(settings): add reduceVisualEffects flag + event/handler

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Thread `reduceEffects` through the theme builders, registry, and `main.dart`

**Files:**
- Modify: `lib/core/theme/theme_registry.dart`
- Modify: `lib/core/theme/themes/brutalist/brutalist_theme.dart`
- Modify: `lib/core/theme/themes/editorial/editorial_theme.dart`
- Modify: `lib/core/theme/themes/dracula/dracula_theme.dart`
- Modify: `lib/core/theme/themes/rpg/rpg_theme.dart`
- Modify: `lib/main.dart`

This task is a pure no-op refactor: every existing builder accepts the new param and ignores it (RPG uses it in Task 8). Tests stay green because the param defaults to `false`.

- [ ] **Step 1: Update the typedef + `resolveTheme*` + cache in `theme_registry.dart`**

Replace the `AppThemeBuilder` typedef:

```dart
typedef AppThemeBuilder =
    ThemeData Function(
      Brightness brightness, {
      bool isCompact,
      bool reduceEffects,
    });
```

Replace `resolveThemeData` (keep `resolveTheme`, `resolveThemeDescriptor`, `appThemes` as-is; only the cache and the data resolver change):

```dart
// Cache keyed by (resolved theme id, brightness, isCompact, reduceEffects).
// ThemeData is immutable and theme builders are pure functions of these inputs,
// so entries are safe to share indefinitely.
// Bounded: themes × brightness × compact × reduceEffects ≤ ~16 entries total.
final Map<(String, Brightness, bool, bool), ThemeData> _themeDataCache = {};

ThemeData resolveThemeData(
  String? themeId,
  Brightness brightness, {
  required bool isCompact,
  bool reduceEffects = false,
}) {
  final resolvedId = resolveThemeDescriptor(themeId).id;
  final key = (resolvedId, brightness, isCompact, reduceEffects);
  return _themeDataCache.putIfAbsent(
    key,
    () => resolveTheme(resolvedId)(
      brightness,
      isCompact: isCompact,
      reduceEffects: reduceEffects,
    ),
  );
}
```

- [ ] **Step 2: Add the param to all four existing builder signatures**

In each file, change the builder signature to add `, bool reduceEffects = false`:

- `brutalist_theme.dart`: `ThemeData brutalistTheme(Brightness brightness, {bool isCompact = false, bool reduceEffects = false}) {`
- `editorial_theme.dart`: `ThemeData editorialTheme(Brightness brightness, {bool isCompact = false, bool reduceEffects = false}) {`
- `dracula_theme.dart`: `ThemeData draculaTheme(Brightness brightness, {bool isCompact = false, bool reduceEffects = false}) {`
- `rpg_theme.dart`: `ThemeData rpgTheme(Brightness brightness, {bool isCompact = false, bool reduceEffects = false}) {`

(For brutalist/editorial/dracula the param is intentionally unused for now. To satisfy the `unused` lint on an unused parameter, no action is needed — unused **named parameters** are not flagged by `avoid_unused_constructor_parameters`/`unused_local_variable`. If `fvm flutter analyze` reports anything, add `// ignore: avoid_unused_parameters` is NOT needed; named params are fine. Verify in Step 4.)

- [ ] **Step 3: Wire `main.dart`**

In `lib/main.dart`:

1. Extend `buildWhen` (the `BlocBuilder<SettingsBloc, SettingsState>` around line 184) to add a fourth clause:
```dart
              buildWhen: (prev, next) =>
                  prev.settings.themeId != next.settings.themeId ||
                  prev.settings.isDarkMode != next.settings.isDarkMode ||
                  prev.settings.isCompactMode != next.settings.isCompactMode ||
                  prev.settings.reduceVisualEffects !=
                      next.settings.reduceVisualEffects,
```
2. Pass `reduceEffects` into both `resolveThemeData` calls:
```dart
                      theme: resolveThemeData(
                        settings.themeId,
                        Brightness.light,
                        isCompact: settings.isCompactMode,
                        reduceEffects: settings.reduceVisualEffects,
                      ),
                      darkTheme: resolveThemeData(
                        settings.themeId,
                        Brightness.dark,
                        isCompact: settings.isCompactMode,
                        reduceEffects: settings.reduceVisualEffects,
                      ),
```

- [ ] **Step 4: Run analyze + the theme tests**

Run: `fvm flutter analyze && fvm flutter test test/core/theme/`
Expected: "No issues found!" and all theme tests PASS (the registry/theme tests call builders with `isCompact:` only; the defaulted `reduceEffects` keeps them valid).

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme lib/main.dart
git commit -m "refactor(theme): thread reduceEffects through builders + registry cache

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Glass palette

**Files:**
- Create: `lib/core/theme/themes/glass/glass_palette.dart`

- [ ] **Step 1: Create the palette file**

```dart
import 'package:flutter/material.dart';

/// Apple "Liquid Glass" palette. Light = "Clear" (pastel wallpaper, near-white
/// frosted panels), dark = "Smoked" (deep jewel wallpaper, charcoal panels).
/// Panel/border/code surfaces are intentionally translucent — the theme's
/// wallpaper shows through and real backdrop blur frosts them.
class GlassPalette {
  GlassPalette._();

  // ── Accent (Apple system blue) ─────────────────────────────────────────────
  static const Color accentLight = Color(0xFF007AFF);
  static const Color accentDark = Color(0xFF0A84FF);

  // ── Translucent panel surfaces ─────────────────────────────────────────────
  static const Color panelLight = Color(0x6BFFFFFF); // white @ ~42%
  static const Color panelDark = Color(0x66282A3A); // smoked charcoal @ ~40%

  // ── Hairline "specular" borders ────────────────────────────────────────────
  static const Color borderLight = Color(0xB3FFFFFF); // white @ ~70%
  static const Color borderDark = Color(0x24FFFFFF); // white @ ~14%

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textLight = Color(0xFF1C1C1E);
  static const Color textSoftLight = Color(0x991C1C1E);
  static const Color textDark = Color(0xFFF2F2F7);
  static const Color textSoftDark = Color(0x99F2F2F7);

  // ── Translucent code-editor background ─────────────────────────────────────
  static const Color codeBackgroundLight = Color(0x4DFFFFFF); // white @ ~30%
  static const Color codeBackgroundDark = Color(0x4D11131F); // deep @ ~30%

  // ── Method colors (Apple system colors; one set, contrast via onColor) ──────
  static const Map<String, Color> methodColors = {
    'GET': Color(0xFF34C759), // green
    'POST': Color(0xFF0A84FF), // blue
    'PUT': Color(0xFFFF9F0A), // orange
    'PATCH': Color(0xFFAF52DE), // purple
    'DELETE': Color(0xFFFF3B30), // red
  };
  static const Color methodFallback = Color(0xFF8E8E93); // system gray

  // ── Status colors ──────────────────────────────────────────────────────────
  static const Color statusSuccess = Color(0xFF34C759);
  static const Color statusWarning = Color(0xFFFF9F0A);
  static const Color statusError = Color(0xFFFF3B30);

  // ── Variable tokens ─────────────────────────────────────────────────────────
  static const Color variableResolved = Color(0xFF34C759);
  static const Color variableUnresolved = Color(0xFFFF3B30);

  // ── Wallpaper mesh blobs ────────────────────────────────────────────────────
  // Each variant's wallpaper is a stack of soft radial blobs over a base.
  static const Color wallpaperBaseLight = Color(0xFFEEF2FB);
  static const List<Color> wallpaperBlobsLight = [
    Color(0xFFD8E8FF), // blue
    Color(0xFFFFD9EC), // pink
    Color(0xFFD6FFF0), // mint
  ];
  static const Color wallpaperBaseDark = Color(0xFF0C0F1A);
  static const List<Color> wallpaperBlobsDark = [
    Color(0xFF1D3A6B), // indigo
    Color(0xFF4A1F57), // violet
    Color(0xFF0F3D3A), // teal
  ];
}
```

- [ ] **Step 2: Verify it analyzes**

Run: `fvm flutter analyze lib/core/theme/themes/glass/glass_palette.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/core/theme/themes/glass/glass_palette.dart
git commit -m "feat(theme): glass palette (Clear light + Smoked dark)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Glass decorations (panelBox, tabShape, frost, wallpaper)

**Files:**
- Create: `lib/core/theme/themes/glass/glass_decorations.dart`
- Test: `test/core/theme/themes/glass_decorations_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/core/theme/themes/glass_decorations_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/glass/glass_decorations.dart';
import 'package:getman/core/theme/themes/glass/glass_theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('glassFrost wraps its child in a BackdropFilter', (tester) async {
    const child = SizedBox(key: ValueKey('panel'));
    await tester.pumpWidget(
      MaterialApp(
        theme: glassTheme(Brightness.dark),
        home: Builder(
          builder: (ctx) => glassFrost(ctx, child: child),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byKey(const ValueKey('panel')), findsOneWidget);
  });

  testWidgets('glassPanelBox is translucent (alpha < 1)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: glassTheme(Brightness.dark),
        home: Builder(
          builder: (ctx) {
            final box = ctx.appDecoration.panelBox(ctx);
            expect((box.color!.a) < 1.0, isTrue);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/core/theme/themes/glass_decorations_test.dart`
Expected: FAIL — `glass_decorations.dart` / `glass_theme.dart` don't exist (compile error). This is expected; the test compiles after Tasks 5–7.

- [ ] **Step 3: Create `glass_decorations.dart`**

```dart
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/glass/glass_palette.dart';

/// Gaussian blur radius for frosted panels. Single tunable so the whole theme's
/// blur intensity moves together.
const double kGlassBlurSigma = 18;

/// Translucent frosted panel: a glassy fill, a hairline "specular" border, and
/// a soft ambient shadow. The fill is translucent so the wallpaper (and, with
/// [glassFrost], the blurred backdrop) read through it. [offset] is accepted for
/// API parity but ignored — glass uses a soft, near-centered shadow.
BoxDecoration glassPanelBox(
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
        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ],
  );
}

/// Wraps [child] in real frosted-glass blur, clipped to rounded corners.
/// `RepaintBoundary` isolates the always-visible blur from sibling repaints.
Widget glassFrost(
  BuildContext context, {
  required Widget child,
  BorderRadius? borderRadius,
}) {
  final radius =
      borderRadius ?? BorderRadius.circular(context.appShape.panelRadius);
  return RepaintBoundary(
    child: ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: kGlassBlurSigma, sigmaY: kGlassBlurSigma),
        child: child,
      ),
    ),
  );
}

/// Rounded translucent tab pill. Active = accent fill; hover = faint accent
/// tint; inactive = transparent (the wallpaper shows behind it).
BoxDecoration glassTabShape(
  BuildContext context, {
  required bool active,
  required bool hovered,
  required bool isFirst,
}) {
  final theme = Theme.of(context);
  final shape = context.appShape;
  final accent = theme.primaryColor;
  final Color background;
  if (active) {
    background = accent;
  } else if (hovered) {
    background = accent.withValues(alpha: 0.14);
  } else {
    background = Colors.transparent;
  }
  return BoxDecoration(
    color: background,
    borderRadius: BorderRadius.circular(shape.buttonRadius),
  );
}

/// Full-effects wallpaper: animated drifting mesh gradient.
Widget glassScaffoldBackground(BuildContext context, {required Widget child}) =>
    GlassWallpaper(animate: true, child: child);

/// Reduced-effects wallpaper: the same mesh gradient, static (no controller).
Widget glassStaticScaffoldBackground(
  BuildContext context, {
  required Widget child,
}) => GlassWallpaper(animate: false, child: child);

/// Soft mesh-gradient wallpaper behind the whole app. The Scaffold above it is
/// transparent, so this is the visible background and panels frost over it.
/// When [animate] is true a slow 40s controller drifts the blobs; when false it
/// renders one static frame (no per-frame cost).
class GlassWallpaper extends StatefulWidget {
  const GlassWallpaper({required this.child, required this.animate, super.key});
  final Widget child;
  final bool animate;

  @override
  State<GlassWallpaper> createState() => _GlassWallpaperState();
}

class _GlassWallpaperState extends State<GlassWallpaper>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      WidgetsBinding.instance.addObserver(this);
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 40),
      );
      unawaited(_controller!.repeat());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null) return;
    if (state == AppLifecycleState.resumed) {
      if (!c.isAnimating) unawaited(c.repeat());
    } else {
      c.stop();
    }
  }

  @override
  void dispose() {
    if (widget.animate) WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? GlassPalette.wallpaperBaseDark
        : GlassPalette.wallpaperBaseLight;
    final blobs = isDark
        ? GlassPalette.wallpaperBlobsDark
        : GlassPalette.wallpaperBlobsLight;
    final controller = _controller;
    final wallpaper = controller == null
        ? _paint(base, blobs, 0)
        : AnimatedBuilder(
            animation: controller,
            builder: (_, _) => _paint(base, blobs, controller.value),
          );
    return Stack(
      children: [
        Positioned.fill(child: RepaintBoundary(child: wallpaper)),
        widget.child,
      ],
    );
  }

  // Three radial blobs whose centers drift on a slow loop (t in [0,1)).
  Widget _paint(Color base, List<Color> blobs, double t) {
    final drift = [
      Alignment(-0.8 + 0.2 * _wave(t), -0.9 + 0.15 * _wave(t + 0.33)),
      Alignment(0.9 - 0.2 * _wave(t + 0.5), -0.8 + 0.15 * _wave(t)),
      Alignment(0.4 * _wave(t + 0.66), 0.95 - 0.1 * _wave(t + 0.2)),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(color: base),
      child: Stack(
        children: [
          for (var i = 0; i < blobs.length; i++)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: drift[i],
                    radius: 1.1,
                    colors: [blobs[i].withValues(alpha: 0.55), Colors.transparent],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Smooth -1..1 oscillation without dart:math import in the hot path.
  double _wave(double t) {
    final x = (t % 1.0) * 2 - 1; // -1..1 sawtooth
    return 1 - (2 * x * x); // smooth-ish parabola, range -1..1
  }
}
```

- [ ] **Step 4: (Test runs after Task 7.)** Analyze the new file:

Run: `fvm flutter analyze lib/core/theme/themes/glass/glass_decorations.dart`
Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/themes/glass/glass_decorations.dart test/core/theme/themes/glass_decorations_test.dart
git commit -m "feat(theme): glass decorations (frost, panel, tab, wallpaper)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Glass press wrapper

**Files:**
- Create: `lib/core/theme/themes/glass/glass_press.dart`

- [ ] **Step 1: Create the press wrapper**

```dart
import 'dart:async';

import 'package:flutter/material.dart';

/// Soft Apple-style press feedback: a gentle scale-down on tap. When [animate]
/// is false (reduced visual effects) the scale animation is skipped — taps still
/// register, just without motion.
class GlassPress extends StatefulWidget {
  const GlassPress({
    required this.child,
    required this.animate,
    super.key,
    this.onTap,
    this.scaleDown = 0.98,
  });
  final Widget child;
  final bool animate;
  final VoidCallback? onTap;
  final double scaleDown;

  @override
  State<GlassPress> createState() => _GlassPressState();
}

class _GlassPressState extends State<GlassPress>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 120),
      );
      _scale = Tween<double>(begin: 1, end: widget.scaleDown).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.easeOut),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.child,
      );
    }
    final controller = _controller!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => controller.forward(),
      onTapUp: (_) {
        unawaited(controller.reverse());
        widget.onTap?.call();
      },
      onTapCancel: () => controller.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
```

- [ ] **Step 2: Verify it analyzes**

Run: `fvm flutter analyze lib/core/theme/themes/glass/glass_press.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/core/theme/themes/glass/glass_press.dart
git commit -m "feat(theme): glass press wrapper (animate-gated)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Glass theme builder + registration + tests

**Files:**
- Create: `lib/core/theme/themes/glass/glass_theme.dart`
- Modify: `lib/core/theme/theme_ids.dart`
- Modify: `lib/core/theme/theme_registry.dart`
- Test: `test/core/theme/themes/glass_theme_test.dart` (create)

- [ ] **Step 1: Add the id constant**

In `lib/core/theme/theme_ids.dart`, add:

```dart
const String kGlassThemeId = 'glass';
```

- [ ] **Step 2: Create the theme builder**

Create `lib/core/theme/themes/glass/glass_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/glass/glass_decorations.dart';
import 'package:getman/core/theme/themes/glass/glass_palette.dart';
import 'package:getman/core/theme/themes/glass/glass_press.dart';
import 'package:google_fonts/google_fonts.dart';

/// Apple "Liquid Glass" theme. Translucent frosted panels (real backdrop blur),
/// generous rounding, hairline highlight edges, Apple-blue accent. Light =
/// "Clear", dark = "Smoked". The Scaffold is transparent so [GlassWallpaper]
/// (installed via scaffoldBackground) is the visible background.
///
/// When [reduceEffects] is true: no backdrop blur (frost stays identity), a
/// static wallpaper, and instant (non-animated) presses.
ThemeData glassTheme(
  Brightness brightness, {
  bool isCompact = false,
  bool reduceEffects = false,
}) {
  final isDark = brightness == Brightness.dark;
  final accent = isDark ? GlassPalette.accentDark : GlassPalette.accentLight;
  final panel = isDark ? GlassPalette.panelDark : GlassPalette.panelLight;
  final border = isDark ? GlassPalette.borderDark : GlassPalette.borderLight;
  final text = isDark ? GlassPalette.textDark : GlassPalette.textLight;
  final textSoft = isDark
      ? GlassPalette.textSoftDark
      : GlassPalette.textSoftLight;
  final codeBackground = isDark
      ? GlassPalette.codeBackgroundDark
      : GlassPalette.codeBackgroundLight;
  const onAccent = Colors.white;

  final layout = isCompact ? AppLayout.compact : AppLayout.normal;
  const shape = AppShape(
    panelRadius: 20,
    buttonRadius: 14,
    inputRadius: 14,
    dialogRadius: 24,
    sheetRadius: 28,
  );

  final inter = GoogleFonts.interTextTheme();
  final baseTextTheme = inter
      .apply(bodyColor: text, displayColor: text)
      .copyWith(
        bodyMedium: inter.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: text,
        ),
        bodySmall: inter.bodySmall?.copyWith(fontSize: 12, color: text),
        titleMedium: inter.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleLarge: inter.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: text,
        ),
      );

  final typography = AppTypography(
    base: baseTextTheme,
    codeFontFamily: GoogleFonts.jetBrainsMono().fontFamily!,
    displayWeight: FontWeight.w700,
    titleWeight: FontWeight.w600,
    bodyWeight: FontWeight.w400,
  );

  final palette = AppPalette(
    methodColors: GlassPalette.methodColors,
    methodFallback: GlassPalette.methodFallback,
    statusSuccess: GlassPalette.statusSuccess,
    statusWarning: GlassPalette.statusWarning,
    statusError: GlassPalette.statusError,
    statusAccentSuccess: GlassPalette.statusSuccess,
    statusAccentWarning: GlassPalette.statusWarning,
    statusAccentError: GlassPalette.statusError,
    codeBackground: codeBackground,
    variableResolved: GlassPalette.variableResolved,
    variableUnresolved: GlassPalette.variableUnresolved,
    selectorActive: accent,
    diffAddedForeground: GlassPalette.statusSuccess,
    diffAddedBackground: GlassPalette.statusSuccess.withValues(alpha: 0.16),
    diffRemovedForeground: GlassPalette.statusError,
    diffRemovedBackground: GlassPalette.statusError.withValues(alpha: 0.16),
  );

  // Full effects: real frost + animated wallpaper + animated press.
  // Reduced: frost stays the identity default, static wallpaper, instant press.
  final decoration = reduceEffects
      ? AppDecoration(
          panelBox: glassPanelBox,
          tabShape: glassTabShape,
          wrapInteractive: ({required child, onTap, scaleDown}) => GlassPress(
            animate: false,
            onTap: onTap,
            scaleDown: scaleDown ?? 0.98,
            child: child,
          ),
          scaffoldBackground: glassStaticScaffoldBackground,
        )
      : AppDecoration(
          panelBox: glassPanelBox,
          tabShape: glassTabShape,
          wrapInteractive: ({required child, onTap, scaleDown}) => GlassPress(
            animate: true,
            onTap: onTap,
            scaleDown: scaleDown ?? 0.98,
            child: child,
          ),
          scaffoldBackground: glassScaffoldBackground,
          frost: glassFrost,
        );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    primaryColor: accent,
    // Transparent so GlassWallpaper (scaffoldBackground) is the visible base
    // and panels frost over it.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: panel,
    cardColor: panel,
    dividerColor: border,
    hoverColor: accent.withValues(alpha: 0.1),
    splashColor: accent.withValues(alpha: 0.2),
    colorScheme:
        (isDark
                ? ColorScheme.dark(primary: accent, secondary: accent)
                : ColorScheme.light(primary: accent, secondary: accent))
            .copyWith(
              onPrimary: onAccent,
              onSecondary: onAccent,
              surface: panel,
              onSurface: text,
            ),
    textTheme: baseTextTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: layout.fontSizeSubtitle,
        color: text,
        fontWeight: FontWeight.w700,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      labelColor: onAccent,
      unselectedLabelColor: textSoft,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(shape.buttonRadius),
      ),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
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
        textStyle: TextStyle(
          fontSize: layout.fontSizeTitle,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: BorderSide(color: border, width: layout.borderThin),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.buttonRadius),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: layout.buttonPaddingHorizontal,
          vertical: layout.buttonPaddingVertical,
        ),
        textStyle: TextStyle(
          fontSize: layout.fontSizeTitle,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: TextStyle(
          fontSize: layout.fontSizeTitle,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: border, width: layout.borderThin),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: border, width: layout.borderThin),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: accent, width: layout.borderThin),
        borderRadius: BorderRadius.circular(shape.inputRadius),
      ),
      labelStyle: TextStyle(color: textSoft, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: textSoft.withValues(alpha: 0.7)),
      contentPadding: EdgeInsets.symmetric(
        horizontal: layout.inputPadding,
        vertical: layout.inputPadding,
      ),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.panelRadius),
        side: BorderSide(color: border, width: layout.borderThin),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.dialogRadius),
        side: BorderSide(color: border, width: layout.borderThin),
      ),
      titleTextStyle: TextStyle(
        color: text,
        fontSize: layout.fontSizeSubtitle,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(color: text, fontSize: layout.fontSizeTitle),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: accent,
      selectedColor: onAccent,
      titleTextStyle: TextStyle(fontWeight: FontWeight.w600, color: text),
      subtitleTextStyle: TextStyle(color: textSoft),
    ),
  );

  return base.copyWith(
    extensions: [
      layout,
      palette,
      shape,
      typography,
      decoration,
      const AppCopy(emptyResponse: 'SEND A REQUEST TO SEE THE RESPONSE'),
    ],
  );
}
```

- [ ] **Step 3: Register the theme**

In `lib/core/theme/theme_registry.dart`:
1. Add the import (in alphabetical order among the `themes/...` imports, before `rpg`):
```dart
import 'package:getman/core/theme/themes/glass/glass_theme.dart';
```
2. Add the descriptor to the `appThemes` map (after the dracula entry):
```dart
  kGlassThemeId: ThemeDescriptor(
    id: kGlassThemeId,
    displayName: 'LIQUID GLASS',
    builder: glassTheme,
  ),
```

- [ ] **Step 4: Write the theme test**

Create `test/core/theme/themes/glass_theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/themes/glass/glass_theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('glassTheme', () {
    for (final b in [Brightness.light, Brightness.dark]) {
      for (final c in [false, true]) {
        for (final r in [false, true]) {
          testWidgets(
            'attaches all six extensions (brightness=$b compact=$c reduce=$r)',
            (tester) async {
              final theme = glassTheme(b, isCompact: c, reduceEffects: r);
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

    testWidgets('frost wraps in BackdropFilter when effects are full', (
      tester,
    ) async {
      final theme = glassTheme(Brightness.dark);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (ctx) =>
                ctx.appDecoration.frost(ctx, child: const SizedBox()),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('frost is identity when effects are reduced', (tester) async {
      final theme = glassTheme(Brightness.dark, reduceEffects: true);
      const child = SizedBox(key: ValueKey('c'));
      late Widget result;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (ctx) {
              result = ctx.appDecoration.frost(ctx, child: child);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(identical(result, child), isTrue);
    });
  });
}
```

- [ ] **Step 5: Run all theme tests (incl. the Task-5 decorations test, now compilable)**

Run: `fvm flutter test test/core/theme/`
Expected: PASS — registry test auto-covers the new descriptor; glass theme + decorations tests pass.

- [ ] **Step 6: Analyze + lints**

Run: `fvm flutter analyze && fvm dart run custom_lint`
Expected: "No issues found!" both.

- [ ] **Step 7: Commit**

```bash
git add lib/core/theme/themes/glass/glass_theme.dart lib/core/theme/theme_ids.dart lib/core/theme/theme_registry.dart test/core/theme/themes/glass_theme_test.dart
git commit -m "feat(theme): register LIQUID GLASS theme

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: RPG gating (static background + sparkle flag under reduceEffects)

**Files:**
- Modify: `lib/core/theme/themes/rpg/rpg_sparkle.dart`
- Modify: `lib/core/theme/themes/rpg/rpg_decorations.dart`
- Modify: `lib/core/theme/themes/rpg/rpg_theme.dart`

- [ ] **Step 1: Add a `sparkle` flag to `RpgSparkle`**

In `lib/core/theme/themes/rpg/rpg_sparkle.dart`:
1. Add the field + constructor param:
```dart
  const RpgSparkle({
    required this.child,
    super.key,
    this.onTap,
    this.scaleDown = 0.96,
    this.sparkle = true,
  });
```
```dart
  final double scaleDown;

  /// When false (reduced visual effects), tap-down skips the particle burst;
  /// the scale-press still fires (it's cheap and transient).
  final bool sparkle;
```
2. In `onTapDown`, guard the burst:
```dart
      onTapDown: (details) {
        unawaited(_scaleController.forward());
        if (widget.sparkle) _emitBurst(details.localPosition);
      },
```

- [ ] **Step 2: Add a static scaffold background to `rpg_decorations.dart`**

Add this function right after `rpgScaffoldBackground` (it reuses the existing radial vignette, minus the animated starfield):

```dart
/// Reduced-effects RPG background: the radial vignette only, no animated
/// starfield (no controller, no per-frame paint).
Widget rpgStaticScaffoldBackground(
  BuildContext context, {
  required Widget child,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  return Stack(
    children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.2,
              colors: [
                theme.scaffoldBackgroundColor,
                if (isDark)
                  Colors.black.withValues(alpha: 0.6)
                else
                  RpgPalette.goldDeep.withValues(alpha: 0.08),
              ],
            ),
          ),
        ),
      ),
      RepaintBoundary(child: child),
    ],
  );
}
```

- [ ] **Step 3: Gate them in `rpg_theme.dart`**

Replace the `AppDecoration(...)` block (currently lines ~120–126) with a `reduceEffects`-aware version:

```dart
  final decoration = AppDecoration(
    panelBox: rpgPanelBox,
    tabShape: rpgTabShape,
    wrapInteractive: ({required child, onTap, scaleDown}) => RpgSparkle(
      onTap: onTap,
      scaleDown: scaleDown ?? 0.96,
      sparkle: !reduceEffects,
      child: child,
    ),
    scaffoldBackground: reduceEffects
        ? rpgStaticScaffoldBackground
        : rpgScaffoldBackground,
  );
```

- [ ] **Step 4: Run RPG-relevant tests + analyze**

Run: `fvm flutter analyze && fvm flutter test test/core/theme/`
Expected: "No issues found!" and theme tests PASS. (If an `rpg_theme_test.dart` exists it still calls the builder with defaults — `reduceEffects` defaults to false → unchanged animated behavior.)

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/themes/rpg
git commit -m "feat(theme): gate RPG starfield + sparkles under reduceEffects

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Apply `frost` at the panel + overlay call sites

**Files (modify):**
- `lib/features/tabs/presentation/widgets/request_config_section.dart`
- `lib/features/tabs/presentation/widgets/response_section.dart`
- `lib/features/tabs/presentation/widgets/url_bar.dart`
- `lib/features/tabs/presentation/widgets/unified_request_panel.dart`
- `lib/features/realtime/presentation/widgets/realtime_panel.dart`
- `lib/features/environments/presentation/widgets/environments_dialog.dart`
- `lib/core/ui/widgets/variable_hover_popover.dart`
- `lib/features/home/presentation/widgets/tab_widget.dart`
- `lib/features/tabs/presentation/widgets/tab_switcher_sheet.dart`
- `lib/features/collections/presentation/widgets/node_action_sheet.dart`
- `lib/features/command_palette/presentation/widgets/command_palette.dart`

**The recipe (apply per site):** wrap the existing `Container(decoration: context.appDecoration.panelBox(...))` (or the overlay's surface `Container`) in `context.appDecoration.frost(...)`. For non-glass themes `frost` is the identity passthrough, so these are visual no-ops everywhere except Liquid Glass.

```dart
context.appDecoration.frost(
  context,
  borderRadius: BorderRadius.circular(context.appShape.panelRadius),
  child: <the existing Container>,
)
```

> **Do NOT frost** `collection_node_row.dart:236` — it's the drag-feedback chip with a solid `primaryColor` fill; blur would be invisible and it's transient. Leave it as-is.

- [ ] **Step 1: request_config_section.dart**

Replace (around line 34):
```dart
          Expanded(
            child: Container(
              decoration: context.appDecoration.panelBox(context, offset: 0),
              child: TabBarView(
```
with:
```dart
          Expanded(
            child: context.appDecoration.frost(
              context,
              borderRadius: BorderRadius.circular(context.appShape.panelRadius),
              child: Container(
                decoration: context.appDecoration.panelBox(context, offset: 0),
                child: TabBarView(
```
…and add a matching closing `)` for the new `Container`/`frost`. (The original `Container(...)` closed with `),` before the `Expanded`'s `),`; after wrapping, the order from innermost is: `TabBarView(...)` → `Container` `)` → `frost` `)` → `Expanded` `)`.)

- [ ] **Step 2: response_section.dart**

Replace (around line 186):
```dart
                    Expanded(
                      child: Container(
                        decoration: context.appDecoration.panelBox(
                          context,
                          offset: 0,
                        ),
                        child: TabBarView(
```
with:
```dart
                    Expanded(
                      child: context.appDecoration.frost(
                        context,
                        borderRadius: BorderRadius.circular(
                          context.appShape.panelRadius,
                        ),
                        child: Container(
                          decoration: context.appDecoration.panelBox(
                            context,
                            offset: 0,
                          ),
                          child: TabBarView(
```
…and add the matching closing `)` for the new `frost(` after the existing `Container`'s `)`.

- [ ] **Step 3: Remaining panel sites (same recipe)**

Apply the recipe to each, wrapping the named `Container`:

| File | Anchor | Notes |
|---|---|---|
| `url_bar.dart` | the `return Container( padding: const EdgeInsets.all(6), decoration: …panelBox(context, offset: layout.cardOffset), …)` (~line 173) | `return context.appDecoration.frost(context, borderRadius: BorderRadius.circular(context.appShape.panelRadius), child: Container(…));` |
| `unified_request_panel.dart` | `Expanded(child: Container(decoration: …panelBox(context, offset: 0), …))` (~line 91) | same as Task 1 |
| `realtime_panel.dart` | `RepaintBoundary(child: Container(decoration: …panelBox(context, offset: 0), …))` (~line 75) | wrap the `Container` with `frost` **inside** the existing `RepaintBoundary` |
| `environments_dialog.dart` | `Expanded(child: Container(decoration: …panelBox(context, offset: 0), …))` (~line 238) | same as Task 1 |
| `variable_hover_popover.dart` | `Container(constraints: …, padding: …, decoration: …panelBox(context), …)` (~line 69) | wrap the `Container` (radius `context.appShape.panelRadius`) |
| `tab_widget.dart` | tooltip `Container(key: ValueKey('tab_tooltip_…'), …, decoration: …panelBox(context), …)` (~line 372) | wrap the `Container` |

- [ ] **Step 4: Overlay surfaces (bottom sheets + command palette)**

These build a top-level container with `color: theme.scaffoldBackgroundColor`. For glass that color is transparent, so frosting blurs the dimmed app behind the sheet (frosted glass); for other themes `frost` is identity and the color is opaque (unchanged). Wrap each sheet/palette's outermost content `Container` in `frost` using the **sheet** radius:

```dart
context.appDecoration.frost(
  context,
  borderRadius: BorderRadius.vertical(
    top: Radius.circular(context.appShape.sheetRadius),
  ),
  child: <the existing surface Container>,
)
```

Apply to:
- `tab_switcher_sheet.dart` — the `Container(... color: theme.scaffoldBackgroundColor ...)` (~line 57).
- `node_action_sheet.dart` — the sheet content `Container` (~line 25, and the second sheet at ~line 254 — wrap both).
- `command_palette.dart` — wrap the palette's outer surface `Container`; use the full `context.appShape.panelRadius` (it's a centered floating panel, not an edge sheet — use `BorderRadius.circular(context.appShape.panelRadius)`).

> If any of these surfaces is not a single `Container` you can wrap cleanly, wrap the smallest widget that owns the surface color + rounded shape. The only invariant: the translucent/transparent fill must sit *inside* the `frost` so the `BackdropFilter` samples the backdrop.

- [ ] **Step 5: Analyze + format + full test suite**

Run: `fvm flutter analyze && fvm dart format lib && fvm flutter test`
Expected: "No issues found!", formatter clean, all tests PASS.

- [ ] **Step 6: Manual smoke check (glass renders)**

Run: `fvm flutter run -d macos`
In the app: open Settings → THEME → **LIQUID GLASS**. Verify: frosted translucent panels over a soft wallpaper, rounded corners, blue accent. Toggle **REDUCE VISUAL EFFECTS** (added in Task 10) — panels should flatten (no blur), wallpaper static. Toggle back. Switch to another theme (e.g. BRUTALIST) and confirm it looks **identical** to before (frost is a no-op there).

- [ ] **Step 7: Commit**

```bash
git add lib/features lib/core/ui/widgets/variable_hover_popover.dart
git commit -m "feat(theme): route panels + overlays through frost hook

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Settings UI toggle

**Files:**
- Modify: `lib/features/settings/presentation/widgets/settings_dialog.dart`

- [ ] **Step 1: Add the switch**

In `settings_dialog.dart`, insert this `SwitchListTile` right after the `COMPACT MODE` `SwitchListTile` (before the `const Divider()` that precedes the `NETWORK` section, ~line 230):

```dart
                  SwitchListTile(
                    key: const ValueKey('reduce_effects_switch'),
                    activeThumbColor: theme.colorScheme.secondary,
                    activeTrackColor: theme.primaryColor,
                    secondary: Icon(Icons.auto_awesome, size: layout.iconSize),
                    title: Text(
                      'REDUCE VISUAL EFFECTS',
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                    subtitle: Text(
                      'Disables backdrop blur & animations for performance',
                      style: TextStyle(fontSize: layout.fontSizeSmall),
                    ),
                    value: settings.reduceVisualEffects,
                    onChanged: (val) => context.read<SettingsBloc>().add(
                      UpdateReduceVisualEffects(value: val),
                    ),
                  ),
```

- [ ] **Step 2: Analyze + format**

Run: `fvm flutter analyze && fvm dart format lib`
Expected: "No issues found!", formatter clean.

- [ ] **Step 3: Manual check**

Run: `fvm flutter run -d macos` → Settings → confirm the **REDUCE VISUAL EFFECTS** switch appears, toggles, and (on the glass theme) flips blur/animation live.

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/presentation/widgets/settings_dialog.dart
git commit -m "feat(settings): add REDUCE VISUAL EFFECTS toggle to settings UI

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Wiki sync

**Files:** the separate `Getman.wiki.git` repo (NOT this repo).

- [ ] **Step 1: Clone the wiki**

```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki
```

- [ ] **Step 2: Update the Themes page**

Edit the themes page (the file documenting BRUTALIST / EDITORIAL / ARCANE QUEST / DRACULA). Add a **LIQUID GLASS** entry: Apple-style frosted translucency with real backdrop blur, light "Clear" + dark "Smoked" variants, generous rounding, Apple system-blue accent. Use the verbatim UI label `LIQUID GLASS` (as shown in the THEME dropdown).

- [ ] **Step 3: Update the Settings page**

Document the new toggle with its verbatim label and subtitle:
- **REDUCE VISUAL EFFECTS** — "Disables backdrop blur & animations for performance." Default: off (full effects on every platform). Primarily affects the Liquid Glass theme (blur + animated wallpaper) and the Arcane Quest animated background; web users who see stutter can enable it.

- [ ] **Step 4: Commit + push the wiki**

```bash
cd /tmp/getman-wiki
git add -A
git commit -m "docs: document LIQUID GLASS theme + REDUCE VISUAL EFFECTS setting"
git push origin master
```

(No commit in the app repo for this task.)

---

## Task 12: Final verification bar

- [ ] **Step 1: Run the full done-bar**

```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test tools
fvm flutter test
```
Expected: every command clean — "No issues found!" (analyze), "No issues found!" (custom_lint), "0 issues found" (bloc lint), formatter reports 0 changed, all tests green.

- [ ] **Step 2: Final manual confirmation**

`fvm flutter run -d macos` → exercise LIQUID GLASS in both light & dark (toggle DARK MODE), with REDUCE VISUAL EFFECTS on and off; confirm dialogs, the tab switcher sheet, the node action sheet, and the command palette all render the glass surface; confirm other themes are visually unchanged.

- [ ] **Step 3: Final commit (if any formatting/cleanup remains)**

```bash
git add -A
git commit -m "chore(theme): final cleanup for Liquid Glass theme

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Notes & known limits (carried from the spec)

- **Desktop `AlertDialog` chrome** gets the glass `DialogTheme` (translucent `panel` fill + rounded), but **not** a bespoke `BackdropFilter` — Material builds its own surface and there's no clean injection point. Dialogs shown fullscreen (compact) via `ResponsiveDialogScaffold` sit on the transparent Scaffold, so the wallpaper shows behind them. This is a deliberate, documented v1 limit.
- **`scaffoldBackgroundColor` is transparent** for glass so the wallpaper is the visible background. Sub-areas that read `scaffoldBackgroundColor` (tab strip, add-tab button idle) therefore show the wallpaper — intended (more glass).
- The toggle is **global**: today it actively changes the glass theme (blur + wallpaper animation + press) and RPG (starfield + sparkles). It's threaded into all builders so future work can gate effects in the other themes without further plumbing.
