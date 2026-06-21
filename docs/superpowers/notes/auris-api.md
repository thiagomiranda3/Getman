# Auris 0.2.0 — Verified API Reference

> Source: `~/.pub-cache/hosted/pub.dev/auris-0.2.0/lib/`
> Captured: 2026-06-20 for tasks C2 (AURIS theme) and D1 (auris component slots).
> ALL names below are EXACT — use these, not the plan sketches.

---

## Entry points

```dart
import 'package:auris/auris.dart';         // AurisTheme, AurisScheme, AurisBevelScale, AurisDepth,
                                            // AurisTokens, ChamferBorder, ChamferClipper, SlantClipper
import 'package:auris/auris_widgets.dart';  // all widgets below (also re-exports scheme + tokens)
```

---

## AurisTheme (abstract final class, no instantiation)

Both factories return a fully specified `ThemeData` with `AurisScheme` attached in `extensions`.

```dart
static ThemeData AurisTheme.dark({
  Color? accent,              // optional; overrides the amber/gold primary ramp
  double bevelScale = 1.0,    // multiplies all bevel roles
  double glowScale = 1.0,     // multiplies all depth glow intensity
})

static ThemeData AurisTheme.light({
  Color? accent,
  double bevelScale = 1.0,
  double glowScale = 1.0,
})
```

**Font families bundled in the package** (accessed as `package:auris/<Family>`):
- `Rajdhani` (display/headline/title): weights 500, 600, 700
- `ExoTwo` (body/label): weight 400
- `ShareTechMono` (data/monospace): weight 400

**AurisTokens font constants** (use these, not bare family names):
```dart
AurisTokens.fontDisplay   = 'packages/auris/Rajdhani'
AurisTokens.fontBody      = 'packages/auris/ExoTwo'
AurisTokens.fontMono      = 'packages/auris/ShareTechMono'

// Fallback chains:
AurisTokens.fontDisplayFallback = ['Roboto', 'Helvetica Neue', 'Arial', 'sans-serif']
AurisTokens.fontBodyFallback    = fontDisplayFallback  // same
AurisTokens.fontMonoFallback    = ['Roboto Mono', 'Menlo', 'Consolas', 'Courier New', 'monospace']
```

**TextTheme mapping:**
- `displayLarge..displaySmall`, `headlineLarge..headlineSmall`, `titleLarge..titleSmall` → Rajdhani
- `bodyLarge..bodySmall`, `labelLarge..labelSmall` → ExoTwo
- Monospace (data readouts) is NOT in TextTheme; accessed via `AurisTokens.fontMono` directly in widgets

---

## AurisScheme (ThemeExtension<AurisScheme>)

**Accessed from widgets via:** `Theme.of(context).extension<AurisScheme>()!` (force-unwrap — the scheme MUST be attached; `AurisTheme.dark/light` attaches it automatically).

### Factory

```dart
factory AurisScheme.resolve({
  Brightness brightness = Brightness.dark,
  Color? accent,
  double bevelScale = 1.0,
  double glowScale = 1.0,
})
```

### Public token fields

**Surfaces:**
```dart
Color surfacePage;    // 0xFF0A0A0C — page background (near-black void)
Color surfacePanel;   // 0xFF111115 — panel / card surface
Color surfaceInset;   // 0xFF16161C — inset / input surface
```

**Text roles:**
```dart
Color textBright;     // 0xFFF0E8D0 — primary readable text (warm white)
Color textMid;        // 0xFFA09060 — secondary / supporting text
Color textDim;        // 0xFF5A5040 — decorative-only dim text (NEVER for primary content)
```

**Primary ramp (amber/gold):**
```dart
Color primaryDim;       // 0xFFC8860A — inactive / dim amber
Color primaryActive;    // 0xFFF0A500 — active gold
Color primaryHighlight; // 0xFFFFD060 — focus / highlight (bright)
Color onPrimary;        // 0xFF0A0A0C — foreground on primary fills
```

**Secondary accent (cool slate):**
```dart
Color secondary;    // 0xFF8AABB0 — cool slate accent
Color secondaryDim; // 0xFF4A6870 — dim slate
```

**Borders:**
```dart
Color borderResting;   // 0xFF2A2510 — resting outline (decorative only)
Color borderBright;    // 0xFF4A4020 — hover / focus outline
Color get borderActive // primaryActive.withValues(alpha: 0.7) — open overlays
```

**Semantic:**
```dart
Color danger;        // 0xFFB03020
Color dangerBright;  // 0xFFE84838 — AA-safe on darkest surface
Color success;       // 0xFF4A8A60
Color successBright; // 0xFF6AB880
```

**Shape:**
```dart
AurisBevelScale bevel;
  // Fields: xs (3.0), sm (6.0), md (10.0), lg (14.0), xl (20.0) — multiplied by bevelScale
  double bevel.xs
  double bevel.sm
  double bevel.md   // component default
  double bevel.lg
  double bevel.xl
```

**Depth by intent:**
```dart
AurisDepth depthResting;    // AurisDepth.none — no glow
AurisDepth depthSubtle;     // faint amber glow
AurisDepth depthActive;     // active amber glow
AurisDepth depthDanger;     // danger red glow
AurisDepth depthSecondary;  // slate glow

// AurisDepth has:
List<BoxShadow> glow;
Color? borderColor;
Color? insetColor;
AurisDepth scaled(double factor);
```

**Misc:**
```dart
Brightness brightness;
double glowScale;  // the glow multiplier this scheme was resolved with
```

---

## AurisTokens (abstract final class, all static const)

Key values C2 needs:
```dart
// Colors (raw primitives — prefer AurisScheme fields in widgets)
Color void_   = 0xFF0A0A0C
Color panel   = 0xFF111115
Color panelAlt = 0xFF16161C
Color amber   = 0xFFC8860A
Color gold    = 0xFFF0A500
Color bright  = 0xFFFFD060
Color brightWhite = 0xFFF0E8D0
Color slate   = 0xFF8AABB0
Color slateDim = 0xFF4A6870
Color danger  = 0xFFB03020
Color dangerBright = 0xFFE84838
Color success = 0xFF4A8A60
Color successBright = 0xFF6AB880
Color textDim = 0xFF5A5040
Color textMid = 0xFFA09060
Color textBright = 0xFFE0C070   // NOTE: this is the TOKEN (golden-tinted bright)
                                 // scheme.textBright is 0xFFF0E8D0 (resolved "brightWhite")

// Bevel sizes
double bevelXs = 3.0
double bevelSm = 6.0
double bevelMd = 10.0
double bevelLg = 14.0
double bevelXl = 20.0

// Glow primitives (List<BoxShadow>)
glowNone, glowSubtle, glowActive, glowDanger, glowSlate

// Motion
Duration durationFast   = 120ms
Duration durationNormal = 200ms
Duration durationSlow   = 350ms
Curve curveDefault = Curves.easeInOut
Curve curveEnter   = Curves.easeOut
Curve curveExit    = Curves.easeIn

// Typography metrics
double trackingLabel   = 1.5
double trackingHeading = 1.8
double trackingButton  = 1.44
double trackingBody    = 0.5
```

---

## Widgets

> **Critical pattern:** every widget calls `Theme.of(context).extension<AurisScheme>()!`
> (force-unwrap). If `AurisScheme` is not attached to the `ThemeData` the widget will throw.
> Always wrap auris widgets inside a `MaterialApp` whose `theme` was built by `AurisTheme.dark/light()`,
> OR manually attach a `scheme` to `ThemeData.extensions`.

---

### AurisBadge

```dart
class AurisBadge extends StatelessWidget {
  const AurisBadge(
    String label, {
    Key? key,
    AurisBadgeVariant variant = AurisBadgeVariant.amber,  // default is amber
  });
}

enum AurisBadgeVariant {
  amber,    // dim amber (primaryDim) — DEFAULT
  gold,     // active gold (primaryActive)
  slate,    // cool slate (secondary)
  danger,   // danger red (dangerBright)
  success,  // success green (successBright)
  inactive, // dim text (textDim)
}
```

---

### AurisContainer (foundation primitive)

```dart
class AurisContainer extends StatelessWidget {
  const AurisContainer({
    Key? key,
    Widget? child,
    double? cut,             // chamfer leg length; null → scheme.bevel.md
    Color? fill,             // null → scheme.surfacePanel
    Color? borderColor,      // null → scheme.borderResting
    double borderWidth = 1.0,
    AurisDepth? depth,       // null → no glow
    EdgeInsetsGeometry? padding,
    double? width,
    double? height,
    AlignmentGeometry? alignment,
    bool clipChild = true,
  });
}
```

---

### AurisPanel

```dart
class AurisPanel extends StatelessWidget {
  const AurisPanel({
    Key? key,
    required String title,                              // rendered uppercase, Rajdhani
    required Widget child,
    String? code,                                       // optional mono code in header trailing
    bool accent = false,                               // gold border + subtle glow
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  });
}
```

---

### AurisStatCard

```dart
class AurisStatCard extends StatelessWidget {
  const AurisStatCard({
    Key? key,
    required String label,       // rendered uppercase
    required String value,       // large glowing primary value (Rajdhani w600 34px)
    String? unit,                // suffix after value (e.g. '%')
    String? delta,               // signed delta e.g. '+2.4%', '-0.8'
    bool deltaPositiveIsGood = true,
  });
}
```

---

### AurisSwitch

```dart
class AurisSwitch extends StatefulWidget {
  const AurisSwitch({
    Key? key,
    required bool value,
    required ValueChanged<bool>? onChanged,  // null → disabled
    String? label,                           // optional label before track
    (String off, String on)? statusLabels,  // optional mono status words after track
    FocusNode? focusNode,
    bool autofocus = false,
  });
}
```

---

### AurisTerminal

```dart
class AurisTerminal extends StatefulWidget {
  const AurisTerminal({
    Key? key,
    required List<AurisTerminalLine> lines,
    String title = 'TERMINAL',
    String? code,
    bool showCursor = true,
    double height = 200,
  });
}

// Line type:
enum AurisTerminalLineType {
  normal,   // textMid
  ok,       // successBright
  error,    // dangerBright
  augment,  // primaryActive (gold)
  warning,  // primaryDim (amber)
}

class AurisTerminalLine {
  const AurisTerminalLine(
    String text, {
    AurisTerminalLineType type = AurisTerminalLineType.normal,
  });
  final String text;
  final AurisTerminalLineType type;
}
```

---

### AurisDataRow

```dart
class AurisDataRow extends StatelessWidget {
  const AurisDataRow({
    Key? key,
    required String label,       // rendered uppercase
    String? value,               // monospace value (required if trailing is null)
    Widget? trailing,            // optional trailing widget (required if value is null)
    bool highlight = false,      // brightens value + adds active glow
    double height = 40,
  });
  // assert: value != null || trailing != null
}
```

---

### AurisSelect / AurisSelectOption

```dart
class AurisSelect<T> extends StatefulWidget {
  const AurisSelect({
    Key? key,
    required List<AurisSelectOption<T>> options,
    required T? value,                       // null → show placeholder
    required ValueChanged<T>? onChanged,    // null → disabled
    String placeholder = 'SELECT',
    double? width,
    FocusNode? focusNode,
  });
}

class AurisSelectOption<T> {
  const AurisSelectOption({required T value, required String label});
  final T value;
  final String label;   // rendered uppercase monospace in trigger + popup
}
```

---

### AurisProgressBar

```dart
class AurisProgressBar extends StatefulWidget {
  // Default constructor (no animation)
  const AurisProgressBar({
    Key? key,
    required double value,       // 0..1
    String? label,
    String? valueLabel,          // e.g. '68 / 100'
    int segments = 20,
    AurisProgressVariant variant = AurisProgressVariant.primary,
    double height = 10,
    double spacing = 2,
  });

  // Named constructor for animated value changes
  const AurisProgressBar.animated({
    Key? key,
    required double value,       // 0..1
    String? label,
    String? valueLabel,
    int segments = 20,
    AurisProgressVariant variant = AurisProgressVariant.primary,
    double height = 10,
    double spacing = 2,
  });
}

enum AurisProgressVariant {
  primary,    // gold (primaryActive) — DEFAULT
  secondary,  // slate (secondary)
  danger,     // dangerBright
  success,    // successBright
}
```

---

### AurisNotification

```dart
class AurisNotification extends StatelessWidget {
  const AurisNotification({
    Key? key,
    required String title,          // rendered uppercase
    String? message,
    String? code,                   // optional mono code by title
    AurisNotificationVariant variant = AurisNotificationVariant.info,
    VoidCallback? onDismiss,        // non-null → shows × dismiss button
  });
}

enum AurisNotificationVariant {
  info,     // gold accent (primaryActive)
  success,  // green (successBright)
  warning,  // amber (primaryDim — note: uses primaryActive accent color)
  error,    // red (dangerBright)
}
```

---

### AurisScanBracket

```dart
class AurisScanBracket extends StatefulWidget {
  const AurisScanBracket({
    Key? key,
    required Widget child,
    Color? color,                                // null → scheme.primaryActive
    double bracketLength = 14,
    double strokeWidth = 2,
    EdgeInsetsGeometry padding = const EdgeInsets.all(6),
    bool pulse = false,                          // opacity pulse (reduced motion: steady)
  });
}
```

---

### AurisHexOrnament

```dart
class AurisHexOrnament extends StatelessWidget {
  const AurisHexOrnament({
    Key? key,
    Color? color,              // null → scheme.borderBright
    double opacity = 0.5,
    double hexRadius = 18,
    double strokeWidth = 1,
  });
}
// Wrapped in IgnorePointer — decorative only. Size via parent constraint.
```

---

## Additional exported types

```dart
// From auris.dart:
class ChamferClipper   // clip to chamfered silhouette; ChamferClipper({required double cut})
class AurisChamferBorder  // ShapeBorder with chamfer; AurisChamferBorder({double cut = 0, BorderSide side = BorderSide.none})
class AurisChamferInputBorder // InputBorder variant (also exported by auris.dart) for chamfered text fields
class SlantClipper     // parallelogram clip (used by Switch + ProgressBar)
class AurisSlantBorder // ShapeBorder with slant; AurisSlantBorder({required double slant, BorderSide side})

// NOTE: the auris WIDGETS self-chamfer internally — C2/D1 generally do NOT construct
// these borders directly; they're available if a Getman-side surface wants the look.
```

---

## AurisScheme + ThemeData relationship

```
AurisTheme.dark()
  └─ AurisScheme.resolve(brightness: Brightness.dark)  ← same overrides forwarded
      └─ Returns AurisScheme (ThemeExtension)
  └─ ThemeData(
       ...all component themes derived from AurisScheme...,
       extensions: [scheme],   // ← ATTACHED HERE
     )
```

Every widget calls `Theme.of(context).extension<AurisScheme>()!` — no widget accepts explicit
`color:` parameters; they all source from the scheme. **C2 MUST ensure the `AurisScheme`
extension is always present in `ThemeData.extensions` for widgets to work.**

---

## Web-safety

`auris 0.2.0` has zero runtime dependencies beyond `flutter` SDK (confirmed from `pubspec.yaml`).
No `dart:io`, no `dart:html`, no platform plugins. Safe for web targets.

---

## Delta vs plan sketches

1. **`AurisTheme` is `abstract final class` — not instantiable.** `.dark()` / `.light()` are static methods on it. Plan said "factory methods" — correct in spirit, exact type is `static ThemeData`.
2. **No `AurisRadio`, `AurisStepIndicator` constructors documented above** — they exist in `auris_widgets.dart` but are not used in Getman's C2/D1 plan. Verify before use if needed.
3. **`AurisBadge` default variant is `amber`, not `gold`** — plan sketch said "verified default variant"; it is `AurisBadgeVariant.amber`.
4. **No explicit `color:` params on most widgets** — all colors come from `AurisScheme`. This is confirmed; C2/D1 must not pass raw colors to these widgets.
5. **`AurisNotification.warning` uses `primaryActive` for accent color** (not `primaryDim`), even though the warning line type in `AurisTerminal` uses `primaryDim`. Confirmed from source.
6. **Font family registered under package prefix** (`packages/auris/Rajdhani`, not bare `Rajdhani`). C2 must use `AurisTokens.fontDisplay/fontBody/fontMono`, not bare names, if referencing fonts directly.
