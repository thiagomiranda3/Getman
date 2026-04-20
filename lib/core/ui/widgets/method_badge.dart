import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

class MethodBadge extends StatelessWidget {
  final String method;
  final bool small;
  const MethodBadge({super.key, required this.method, this.small = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<AppLayout>()!;
    final color = context.appPalette.methodColor(method);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal,
        vertical: layout.badgePaddingVertical,
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
      ),
      child: Text(
        method,
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w900,
          fontSize: small ? layout.fontSizeSmall : layout.fontSizeNormal,
        ),
      ),
    );
  }
}
