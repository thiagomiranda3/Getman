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
