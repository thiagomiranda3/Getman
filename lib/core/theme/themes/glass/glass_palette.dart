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

  // ── Method colors (Apple system; one set, contrast via onColor) ────────────
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

  // ── Variable tokens ────────────────────────────────────────────────────────
  static const Color variableResolved = Color(0xFF34C759);
  static const Color variableUnresolved = Color(0xFFFF3B30);

  // ── Wallpaper mesh blobs ───────────────────────────────────────────────────
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
