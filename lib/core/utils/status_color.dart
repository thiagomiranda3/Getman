import 'package:flutter/material.dart';

class StatusColor {
  StatusColor._();

  static Color forCode(int code) {
    if (code >= 200 && code < 300) return Colors.green.shade700;
    if (code >= 400) return Colors.red.shade700;
    return Colors.orange.shade700;
  }

  static Color forCodeAccent(int code) {
    if (code >= 200 && code < 300) return Colors.greenAccent;
    if (code >= 400) return Colors.redAccent;
    return Colors.orangeAccent;
  }
}
