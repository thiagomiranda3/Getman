// Shared SwitchThemeData factory for the pre-refactor inline switch colors
// (secondary-colored thumb / primary-colored track when ON), installed by
// brutalist/classic/dracula/rpg/editorial; glass ships its own richer
// SwitchThemeData instead, and AURIS composes the external kit's ThemeData
// without calling this factory.
import 'package:flutter/material.dart';

/// Reproduces the switch styling the settings/rule UIs used to hardcode inline
/// (`activeThumbColor: secondary`, `activeTrackColor: primary` — i.e. a
/// secondary-colored thumb on a primary track when ON; Material defaults when
/// OFF) now that those call sites no longer set per-widget colors.
///
/// Brutalist, Classic, Dracula, Arcane Quest (rpg), and Editorial each install
/// this so their switches look exactly as before. Glass deliberately does NOT
/// use it — it ships its own richer [SwitchThemeData] with an always-visible
/// white thumb, because glass's `secondary == primary == accent` made the old
/// inline colors render an invisible blue-on-blue thumb. AURIS also doesn't
/// call this — it composes the external `auris` kit's own `ThemeData`, which
/// brings its own switch styling.
SwitchThemeData accentSwitchTheme({
  required Color thumbWhenOn,
  required Color trackWhenOn,
}) => SwitchThemeData(
  thumbColor: WidgetStateProperty.resolveWith<Color?>(
    (states) => states.contains(WidgetState.selected) ? thumbWhenOn : null,
  ),
  trackColor: WidgetStateProperty.resolveWith<Color?>(
    (states) => states.contains(WidgetState.selected) ? trackWhenOn : null,
  ),
);
