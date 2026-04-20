import 'package:flutter/material.dart';

class EditorialPalette {
  EditorialPalette._();

  static const Color paperLight = Color(0xFFF2EAD8);
  static const Color paperDark = Color(0xFF141210);

  static const Color inkLight = Color(0xFF1A1411);
  static const Color inkDark = Color(0xFFEDE4D0);

  static const Color inkSoftLight = Color(0xFF5B4A3E);
  static const Color inkSoftDark = Color(0xFFA89684);

  static const Color accent = Color(0xFF9C3A23);

  static const Color codeBackgroundLight = Color(0xFFEAE0C9);
  static const Color codeBackgroundDark = Color(0xFF1F1A15);

  static const Map<String, Color> methodColors = {
    'GET': Color(0xFF5F7A3E),
    'POST': Color(0xFF2B3A5E),
    'PUT': Color(0xFFB07D2E),
    'DELETE': Color(0xFF9C3A23),
    'PATCH': Color(0xFF6B4270),
  };

  static const Color statusSuccess = Color(0xFF5F7A3E);
  static const Color statusWarning = Color(0xFFB07D2E);
  static const Color statusError = Color(0xFF9C3A23);

  static const Color statusAccentSuccess = Color(0xFF3E5428);
  static const Color statusAccentWarning = Color(0xFF8A5F20);
  static const Color statusAccentError = Color(0xFF6E2716);
}
