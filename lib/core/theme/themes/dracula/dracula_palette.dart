// Raw Color constants for the Dracula theme (see class doc below).

import 'package:flutter/material.dart';

/// Dracula (dark) + Alucard (the official Dracula light companion) palettes.
///
/// Hex values are taken verbatim from the official Dracula spec
/// (<https://draculatheme.com/spec>): "Dracula Classic" for dark and
/// "Alucard Classic" for light.
class DraculaPalette {
  DraculaPalette._();

  // ── Dracula (dark) ────────────────────────────────────────────────────────
  static const Color backgroundDark = Color(0xFF282A36); // Background
  static const Color surfaceDark = Color(0xFF343746); // slightly elevated
  static const Color codeBackgroundDark = Color(0xFF21222C); // darkest
  static const Color textDark = Color(0xFFF8F8F2); // Foreground
  static const Color textSoftDark = Color(0xFF6272A4); // Comment
  static const Color borderDark = Color(0xFF44475A); // Selection
  static const Color primaryDark = Color(0xFFBD93F9); // Purple
  static const Color secondaryDark = Color(0xFFFF79C6); // Pink

  // ── Alucard (light) ───────────────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFFFFBEB); // Background
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color codeBackgroundLight = Color(0xFFF1ECD8); // warm cream
  static const Color textLight = Color(0xFF1F1F1F); // Foreground
  static const Color textSoftLight = Color(0xFF6C664B); // Comment
  static const Color borderLight = Color(0xFFCFCFDE); // Selection
  static const Color primaryLight = Color(0xFF644AC9); // Purple
  static const Color secondaryLight = Color(0xFFA3144D); // Pink

  // ── Method colors (Dracula accents) ───────────────────────────────────────
  static const Map<String, Color> methodColorsDark = {
    'GET': Color(0xFF50FA7B), // Green
    'POST': Color(0xFF8BE9FD), // Cyan
    'PUT': Color(0xFFFFB86C), // Orange
    'DELETE': Color(0xFFFF5555), // Red
    'PATCH': Color(0xFFBD93F9), // Purple
  };

  static const Map<String, Color> methodColorsLight = {
    'GET': Color(0xFF14710A), // Green
    'POST': Color(0xFF036A96), // Cyan
    'PUT': Color(0xFFA34D14), // Orange
    'DELETE': Color(0xFFCB3A2A), // Red
    'PATCH': Color(0xFF644AC9), // Purple
  };

  static const Color methodFallback = Color(0xFF6272A4); // Comment

  // ── Status colors ─────────────────────────────────────────────────────────
  // statusColor and statusAccent are both consumed as badge backgrounds
  // (legible text is guaranteed by AppPalette.onColor), so each maps to a
  // solid, saturated Dracula hue per brightness.
  static const Color statusSuccessDark = Color(0xFF50FA7B); // Green
  static const Color statusWarningDark = Color(0xFFFFB86C); // Orange
  static const Color statusErrorDark = Color(0xFFFF5555); // Red

  static const Color statusSuccessLight = Color(0xFF14710A); // Green
  static const Color statusWarningLight = Color(0xFFA34D14); // Orange
  static const Color statusErrorLight = Color(0xFFCB3A2A); // Red

  // ── Variable tokens ───────────────────────────────────────────────────────
  static const Color variableResolvedDark = Color(0xFF50FA7B); // Green
  static const Color variableUnresolvedDark = Color(0xFFFF5555); // Red
  static const Color variableResolvedLight = Color(0xFF14710A); // Green
  static const Color variableUnresolvedLight = Color(0xFFCB3A2A); // Red
}
