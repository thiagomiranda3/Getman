import 'package:flutter/material.dart';

/// Arcane Quest RPG palette — dark fantasy jewels + parchment light mode.
class RpgPalette {
  RpgPalette._();

  // Dark (the canonical RPG feel) — deep velvet night + torchlight gold.
  static const Color backgroundDark = Color(0xFF0A0714);
  static const Color surfaceDark = Color(0xFF171029);
  static const Color surfaceRaisedDark = Color(0xFF201637);
  static const Color textDark = Color(0xFFF0E4CC);
  static const Color textSoftDark = Color(0xFFB5A8C9);
  static const Color borderDark = Color(0xFF8B6914);
  static const Color codeBackgroundDark = Color(0xFF0F0A1F);

  // Light (aged parchment scroll).
  static const Color backgroundLight = Color(0xFFF4E8C9);
  static const Color surfaceLight = Color(0xFFEBDDB5);
  static const Color surfaceRaisedLight = Color(0xFFE2D2A6);
  static const Color textLight = Color(0xFF2C1810);
  static const Color textSoftLight = Color(0xFF6B5842);
  static const Color borderLight = Color(0xFF8B5A2B);
  static const Color codeBackgroundLight = Color(0xFFEAE0C9);

  // Signature accents.
  static const Color gold = Color(0xFFE8C547);
  static const Color goldDeep = Color(0xFFB88A1C);
  static const Color emerald = Color(0xFF4FD68D);
  static const Color emeraldDeep = Color(0xFF2D6A4F);
  static const Color ruby = Color(0xFFFF5C7A);
  static const Color rubyDeep = Color(0xFF8C2336);
  static const Color azure = Color(0xFF5AC8FA);
  static const Color amber = Color(0xFFFFA857);
  static const Color arcane = Color(0xFFC792EA);

  /// HTTP methods mapped to RPG rarity tiers.
  static const Map<String, Color> methodColors = {
    'GET': emerald, // common — reliable green
    'POST': azure, // rare — arcane blue
    'PUT': amber, // uncommon — ember amber
    'DELETE': ruby, // legendary peril — ruby red
    'PATCH': arcane, // epic — arcane purple
  };

  static const Color methodFallback = Color(0xFF9A8FB0);

  static const Color statusSuccess = emerald;
  static const Color statusWarning = Color(0xFFFFC857);
  static const Color statusError = ruby;
  static const Color statusAccentSuccess = emeraldDeep;
  static const Color statusAccentWarning = Color(0xFFB88A1C);
  static const Color statusAccentError = rubyDeep;
}
