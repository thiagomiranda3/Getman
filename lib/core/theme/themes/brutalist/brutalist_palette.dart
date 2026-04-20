import 'package:flutter/material.dart';

class BrutalistPalette {
  BrutalistPalette._();

  static const Color backgroundLight = Color(0xFFF3F4F6);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color textLight = Color(0xFF000000);
  static const Color borderLight = Color(0xFF000000);

  static const Color backgroundDark = Color(0xFF1A1A1A);
  static const Color surfaceDark = Color(0xFF242424);
  static const Color textDark = Color(0xFFE0E0E0);
  static const Color borderDark = Color(0xFF404040);

  static const Color primary = Color(0xFFFFD700);
  static const Color primaryDark = Color(0xFFFFD700);

  static const Color secondary = Color(0xFF6D28D9);
  static const Color secondaryDark = Color(0xFF6330BD);

  static const Map<String, Color> methodColors = {
    'GET': Color(0xFF4ADE80),
    'POST': Color(0xFF60A5FA),
    'PUT': Color(0xFFFB923C),
    'DELETE': Color(0xFFF87171),
    'PATCH': Color(0xFFA78BFA),
  };

  static const Color methodFallback = Colors.grey;
}
