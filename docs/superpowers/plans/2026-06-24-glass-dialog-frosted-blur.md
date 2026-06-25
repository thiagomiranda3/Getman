# Glass Frosted-Card Dialog Blur Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Liquid-Glass-theme dialogs a real backdrop blur clipped to the dialog card so the existing ~40% translucent panel is readable, without touching any other theme.

**Architecture:** A new nullable `dialogSurface` hook on the `AppDecoration` theme extension. When non-null (glass at full effects only), `ResponsiveDialogScaffold` renders the centered dialog as a base `Dialog` whose card is built by the hook (`ClipRRect` → `BackdropFilter` → translucent fill). When null (every other theme, and glass under `reduceEffects`), it returns the existing `AlertDialog` unchanged — backed by a new opaque glass dialog color for the no-blur fallback.

**Tech Stack:** Flutter, Dart, `ThemeExtension`, `BackdropFilter`/`ImageFilter`.

## Global Constraints

- `fvm` for all Flutter/Dart commands (`fvm flutter test ...`, never bare).
- `package:getman/...` imports only (no relative imports).
- No hardcoded sizes/colors/radii in widgets, except documented Material-`AlertDialog`-default padding/inset constants (named consts with a comment). Radius comes from `context.appShape.dialogRadius`.
- Heavy effects must degrade to identity/opaque under `reduceEffects`: glass full effects → translucent + blur; glass `reduceEffects` → opaque, no blur.
- Non-glass themes and all existing dialog call sites must be byte-for-byte unaffected.
- Done-bar: `fvm flutter analyze`, `fvm dart run custom_lint`, `fvm dart run bloc_tools:bloc lint lib` all 0 issues; `fvm dart format` clean; `fvm flutter test` green.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. One concern per commit.

---

### Task 1: Add the `dialogSurface` hook to `AppDecoration`

**Files:**
- Modify: `lib/core/theme/extensions/app_decoration.dart`
- Test: `test/core/theme/extensions/app_decoration_test.dart` (create if absent; otherwise append)

**Interfaces:**
- Consumes: nothing.
- Produces: a new field on `AppDecoration`:
  `final Widget Function(BuildContext context, {required Widget child, required BorderRadius borderRadius})? dialogSurface;`
  defaulting to `null`, carried through `copyWith`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/extensions/app_decoration_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/extensions/app_decoration.dart';

AppDecoration _base() => AppDecoration(
      panelBox: (context, {color, borderWidth, offset, borderRadius}) =>
          const BoxDecoration(),
      tabShape: (context, {required active, required hovered, required isFirst}) =>
          const BoxDecoration(),
      wrapInteractive: ({required child, onTap, scaleDown}) => child,
      scaffoldBackground: (context, {required child}) => child,
    );

void main() {
  group('AppDecoration.dialogSurface', () {
    test('defaults to null', () {
      expect(_base().dialogSurface, isNull);
    });

    test('copyWith carries a provided dialogSurface', () {
      Widget builder(
        BuildContext context, {
        required Widget child,
        required BorderRadius borderRadius,
      }) =>
          child;
      final updated = _base().copyWith(dialogSurface: builder);
      expect(updated.dialogSurface, same(builder));
    });

    test('copyWith without dialogSurface keeps the existing one', () {
      Widget builder(
        BuildContext context, {
        required Widget child,
        required BorderRadius borderRadius,
      }) =>
          child;
      final withHook = _base().copyWith(dialogSurface: builder);
      final unchanged = withHook.copyWith();
      expect(unchanged.dialogSurface, same(builder));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/extensions/app_decoration_test.dart`
Expected: FAIL — `The named parameter 'dialogSurface' isn't defined` (compile error).

- [ ] **Step 3: Add the field + a typedef**

In `lib/core/theme/extensions/app_decoration.dart`, after the `FrostWrapper` typedef block (around line 38), add:

```dart
/// Per-theme frosted dialog surface. When non-null, `ResponsiveDialogScaffold`
/// renders the centered dialog as a custom card built from this (clip + blur +
/// translucent fill) instead of a plain `AlertDialog`. Null for every theme
/// that uses an opaque dialog (all themes except Liquid Glass at full effects).
typedef DialogSurfaceBuilder =
    Widget Function(
      BuildContext context, {
      required Widget child,
      required BorderRadius borderRadius,
    });
```

In the constructor (after `this.brandedTabIndicator,`):

```dart
    this.dialogSurface,
```

As a field (after the `brandedTabIndicator` field, ~line 75):

```dart
  /// See [DialogSurfaceBuilder]. Glass sets this at full effects; everything
  /// else leaves it null and keeps the standard `AlertDialog`.
  final DialogSurfaceBuilder? dialogSurface;
```

In `copyWith`'s parameter list (after the `brandedTabIndicator` param):

```dart
    DialogSurfaceBuilder? dialogSurface,
```

In `copyWith`'s returned `AppDecoration(...)` (after the `brandedTabIndicator:` line):

```dart
      dialogSurface: dialogSurface ?? this.dialogSurface,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/extensions/app_decoration_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/core/theme/extensions/app_decoration.dart test/core/theme/extensions/app_decoration_test.dart
git add lib/core/theme/extensions/app_decoration.dart test/core/theme/extensions/app_decoration_test.dart
git commit -m "feat(theme): add nullable dialogSurface hook to AppDecoration

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Glass opaque dialog color + `glassDialogSurface` builder + wire into the theme

**Files:**
- Modify: `lib/core/theme/themes/glass/glass_palette.dart`
- Modify: `lib/core/theme/themes/glass/glass_decorations.dart`
- Modify: `lib/core/theme/themes/glass/glass_theme.dart`
- Test: `test/core/theme/themes/glass_theme_test.dart` (append to the existing `group('glassTheme', ...)`)

**Interfaces:**
- Consumes: `AppDecoration.dialogSurface` (Task 1); `kGlassBlurSigma` (existing, `glass_decorations.dart:14`).
- Produces:
  - `GlassPalette.dialogLight` / `GlassPalette.dialogDark` (opaque `Color`s).
  - `Widget glassDialogSurface(BuildContext context, {required Widget child, required BorderRadius borderRadius})` in `glass_decorations.dart`.
  - `glassTheme(...)` assigns `dialogSurface: glassDialogSurface` only when `!reduceEffects`, and sets `dialogTheme.backgroundColor` to the opaque dialog color.

- [ ] **Step 1: Write the failing tests**

Append inside `group('glassTheme', () { ... })` in `test/core/theme/themes/glass_theme_test.dart`:

```dart
    test('dialogSurface hook is set only at full effects', () {
      for (final b in [Brightness.light, Brightness.dark]) {
        final full = glassTheme(b).extension<AppDecoration>()!;
        final reduced =
            glassTheme(b, reduceEffects: true).extension<AppDecoration>()!;
        expect(full.dialogSurface, isNotNull, reason: 'full effects → frosted');
        expect(reduced.dialogSurface, isNull, reason: 'reduced → opaque AlertDialog');
      }
    });

    test('dialog background is an opaque colour (readable without blur)', () {
      for (final b in [Brightness.light, Brightness.dark]) {
        for (final r in [false, true]) {
          final bg = glassTheme(b, reduceEffects: r).dialogTheme.backgroundColor!;
          expect(bg.a, 1.0, reason: 'glass dialog bg must be fully opaque ($b r=$r)');
        }
      }
    });

    testWidgets('glassDialogSurface blurs its backdrop (BackdropFilter present)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: glassTheme(Brightness.dark),
          home: Builder(
            builder: (ctx) => glassDialogSurface(
              ctx,
              borderRadius: BorderRadius.circular(24),
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
```

Add the import for `glassDialogSurface` at the top of the test file (it lives in `glass_decorations.dart`):

```dart
import 'package:getman/core/theme/themes/glass/glass_decorations.dart';
```

> Note on `Color.a`: this project is on a Flutter that exposes the 0.0–1.0 `Color.a` component accessor (the codebase already uses `withValues(alpha:)`). If `bg.a` does not resolve, use `bg.opacity == 1.0` instead — both assert full opacity.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/theme/themes/glass_theme_test.dart`
Expected: FAIL — `glassDialogSurface` is undefined and `dialogSurface` is null at full effects.

- [ ] **Step 3a: Add the opaque dialog colours**

In `lib/core/theme/themes/glass/glass_palette.dart`, after the panel-surface block (after line 16):

```dart
  // ── Opaque dialog surface (reduceEffects fallback + frosted-card fill base) ──
  // Dialogs render without the in-app backdrop blur, so they need a solid,
  // readable surface when blur is off. A near-white cool tint (light) and an
  // opaque charcoal (dark), distinct from the translucent panel above.
  static const Color dialogLight = Color(0xFFF4F6FC);
  static const Color dialogDark = Color(0xFF20222E);
```

- [ ] **Step 3b: Add the `glassDialogSurface` builder**

In `lib/core/theme/themes/glass/glass_decorations.dart`, after `glassFrost` (after line 69):

```dart
/// The frosted **dialog** card: like [glassFrost] (clip + real backdrop blur)
/// but it also paints the translucent panel fill + hairline border, so the card
/// is a complete surface the dialog content sits in. Used via
/// `AppDecoration.dialogSurface` at full effects only.
Widget glassDialogSurface(
  BuildContext context, {
  required Widget child,
  required BorderRadius borderRadius,
}) {
  final theme = Theme.of(context);
  final layout = context.appLayout;
  return RepaintBoundary(
    child: ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: kGlassBlurSigma,
          sigmaY: kGlassBlurSigma,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.cardColor, // translucent panel (~40%)
            borderRadius: borderRadius,
            border: Border.all(
              color: theme.dividerColor,
              width: layout.borderThin,
            ),
          ),
          child: child,
        ),
      ),
    ),
  );
}
```

- [ ] **Step 3c: Wire it into the theme**

In `lib/core/theme/themes/glass/glass_theme.dart`:

1. Replace the `effectiveDecoration` block (lines 111–113) so the dialog hook is layered on at full effects alongside frost:

```dart
  final effectiveDecoration = reduceEffects
      ? decoration
      : decoration.copyWith(
          frost: glassFrost,
          dialogSurface: glassDialogSurface,
        );
```

2. Compute the opaque dialog colour near the other palette locals (after the `panel` local, ~line 24):

```dart
  final dialogBg = isDark ? GlassPalette.dialogDark : GlassPalette.dialogLight;
```

3. In the `dialogTheme: DialogThemeData(` block, change `backgroundColor: panel,` (line 269) to:

```dart
      backgroundColor: dialogBg,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/theme/themes/glass_theme_test.dart`
Expected: PASS (existing tests + the 3 new ones).

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/core/theme/themes/glass/glass_palette.dart lib/core/theme/themes/glass/glass_decorations.dart lib/core/theme/themes/glass/glass_theme.dart test/core/theme/themes/glass_theme_test.dart
git add lib/core/theme/themes/glass/glass_palette.dart lib/core/theme/themes/glass/glass_decorations.dart lib/core/theme/themes/glass/glass_theme.dart test/core/theme/themes/glass_theme_test.dart
git commit -m "feat(glass): frosted dialog surface + opaque dialog fallback colour

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Render the frosted card in `ResponsiveDialogScaffold`

**Files:**
- Modify: `lib/core/ui/widgets/responsive_dialog.dart`
- Test: `test/core/ui/widgets/responsive_dialog_test.dart` (create if absent)

**Interfaces:**
- Consumes: `AppDecoration.dialogSurface` (Task 1), `glassTheme` (Task 2), `context.appShape.dialogRadius`, `context.appLayout`.
- Produces: no new public symbols. `ResponsiveDialogScaffold`'s centered branch now renders a base `Dialog` with the frosted surface when `dialogSurface != null`; otherwise the existing `AlertDialog`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/widgets/responsive_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> _pumpDialog(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => const ResponsiveDialogScaffold(
                  title: Text('SETTINGS'),
                  content: Text('body'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('glass full effects → frosted card with a BackdropFilter, no AlertDialog',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000); // wide → centered (not fullscreen)
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpDialog(tester, resolveTheme('glass')(Brightness.dark, isCompact: false));
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('glass reduced effects → AlertDialog, no BackdropFilter',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpDialog(
      tester,
      resolveTheme('glass')(Brightness.dark, isCompact: false, reduceEffects: true),
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('non-glass theme → AlertDialog, no BackdropFilter (regression guard)',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpDialog(
      tester,
      resolveTheme('brutalist')(Brightness.dark, isCompact: false),
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
```

> Why the wide `physicalSize`: `ResponsiveDialogScaffold` renders the fullscreen `Scaffold` page on narrow viewports (`context.isDialogFullscreen`). A wide view forces the centered (`AlertDialog`/frosted-card) branch this task changes.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/ui/widgets/responsive_dialog_test.dart`
Expected: FAIL — the glass full-effects test finds an `AlertDialog` and no `BackdropFilter` (frosted-card path not implemented yet).

- [ ] **Step 3: Implement the frosted-card branch + `_DialogBody`**

In `lib/core/ui/widgets/responsive_dialog.dart`, replace the centered branch (the `if (!context.isDialogFullscreen) { return AlertDialog(...); }` block, lines 26–33) with:

```dart
    if (!context.isDialogFullscreen) {
      final surface = context.appDecoration.dialogSurface;
      if (surface == null) {
        return AlertDialog(
          title: DefaultTextStyle.merge(child: title, style: const TextStyle()),
          content: content,
          contentPadding: contentPadding,
          actions: actions,
        );
      }
      // Frosted-card path (glass, full effects). Reuse the base Dialog for the
      // same centering / insetPadding / min-width as AlertDialog, but transparent
      // so the frosted surface is the only visible card.
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: surface(
          context,
          borderRadius: BorderRadius.circular(context.appShape.dialogRadius),
          child: _DialogBody(
            title: title,
            content: content,
            actions: actions,
            contentPadding: contentPadding,
          ),
        ),
      );
    }
```

At the bottom of the file (after the `ResponsiveDialogScaffold` class, before `showResponsiveDialog`), add the private body widget. The padding constants mirror Material's `AlertDialog` defaults:

```dart
// Material AlertDialog default paddings, reproduced so the frosted-card dialog
// matches the standard dialog layout exactly.
const EdgeInsets _kDialogTitlePadding = EdgeInsets.fromLTRB(24, 24, 24, 0);
const EdgeInsets _kDialogContentPadding = EdgeInsets.fromLTRB(24, 20, 24, 24);
const EdgeInsets _kDialogActionsPadding = EdgeInsets.fromLTRB(8, 0, 8, 8);

/// The inner column of a frosted-card dialog: title, scrollable content, and an
/// actions bar — mirroring `AlertDialog`'s structure so content does not reflow.
class _DialogBody extends StatelessWidget {
  const _DialogBody({
    required this.title,
    required this.content,
    this.actions,
    this.contentPadding,
  });

  final Widget title;
  final Widget content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final dialogTheme = Theme.of(context).dialogTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: _kDialogTitlePadding,
          child: DefaultTextStyle.merge(
            style: dialogTheme.titleTextStyle ?? const TextStyle(),
            child: title,
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: contentPadding ?? _kDialogContentPadding,
            child: DefaultTextStyle.merge(
              style: dialogTheme.contentTextStyle ?? const TextStyle(),
              child: content,
            ),
          ),
        ),
        if (actions != null && actions!.isNotEmpty)
          Padding(
            padding: _kDialogActionsPadding,
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              overflowAlignment: OverflowBarAlignment.end,
              children: actions!,
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/ui/widgets/responsive_dialog_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the broader dialog/theme suites (shared-widget regression guard)**

Run: `fvm flutter test test/core/ui/widgets/ test/core/theme/`
Expected: PASS. (`ResponsiveDialogScaffold` is shared; this confirms confirm/name-prompt/theme dialog tests still pass. If a test asserted `find.byType(AlertDialog)` while pumping under glass full effects, update that test to the brutalist/default theme or to `findsNothing` — but only if it was implicitly relying on the old glass behavior.)

- [ ] **Step 6: Commit**

```bash
fvm dart format lib/core/ui/widgets/responsive_dialog.dart test/core/ui/widgets/responsive_dialog_test.dart
git add lib/core/ui/widgets/responsive_dialog.dart test/core/ui/widgets/responsive_dialog_test.dart
git commit -m "feat(glass): render dialogs as a frosted blurred card

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Full gate + visual smoke

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Run the full analysis + format + test gate**

Run:
```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test
fvm flutter test
```
Expected: analyze 0 issues; custom_lint 0; bloc_lint 0; format reports 0 changed; all tests green. Fix any failure before proceeding (these are independent passes).

- [ ] **Step 2: Visual smoke (recommended)**

Run: `fvm flutter run -d macos` (or `-d linux`). Switch to the **Liquid Glass** theme, open **Settings** (and a confirm dialog), and confirm: the dialog now reads as a frosted card — text is legible, the wallpaper behind the card is blurred (not sharply showing through), and the card edges are crisp. Toggle "reduce effects" and confirm the dialog becomes an opaque, readable card with no blur. Switch to another theme (e.g. Brutalist) and confirm its dialogs are unchanged.

- [ ] **Step 3: No wiki change required**

This is an internal visual polish — no new user-facing control, label, setting, or shortcut — so per CLAUDE.md §7 the wiki needs no edit. (Note it in the PR description instead.)

---

## Notes for the implementer

- The `dialogSurface` hook deliberately mirrors the existing nullable `brandedTabIndicator` hook (same null-default, same `copyWith` pattern) — follow that precedent exactly.
- Do not change panel opacity (`GlassPalette.panelLight/panelDark`) — the brainstorm decision is to keep ~40% and let the blur carry readability.
- Do not touch modal bottom sheets — out of scope.
- `glassDialogSurface` reads the translucent fill from `theme.cardColor` (which the glass theme sets to `panel`) and the border from `theme.dividerColor` — do not hardcode the glass colours in the builder.
