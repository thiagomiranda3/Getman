// Shared SwitchThemeData factory for the pre-refactor inline switch colors
// (secondary-colored thumb / primary-colored track when ON) that every
// non-glass theme installs; glass ships its own richer SwitchThemeData
// instead.
import 'package:flutter/material.dart';

/// Reproduces the switch styling the settings/rule UIs used to hardcode inline
/// (`activeThumbColor: secondary`, `activeTrackColor: primary` — i.e. a
/// secondary-colored thumb on a primary track when ON; Material defaults when
/// OFF) now that those call sites no longer set per-widget colors.
///
/// Each non-glass theme installs this so its switches look exactly as before.
/// Glass deliberately does NOT use it — it ships its own richer
/// [SwitchThemeData] with an always-visible white thumb, because glass's
/// `secondary == primary == accent` made the old inline colors render an
/// invisible blue-on-blue thumb.
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
