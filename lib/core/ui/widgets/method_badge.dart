import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';

class MethodBadge extends StatelessWidget {
  const MethodBadge({required this.method, super.key, this.small = false});
  final String method;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return context.appComponents.methodBadge(
      context,
      method: method,
      small: small,
    );
  }
}
