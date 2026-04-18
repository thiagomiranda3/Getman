import 'package:flutter/material.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';

class MethodBadge extends StatelessWidget {
  final String method;
  final bool small;
  const MethodBadge({super.key, required this.method, this.small = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;
    final color = NeoBrutalistTheme.getMethodColor(method);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? layout.badgePaddingHorizontal : 10, 
        vertical: layout.badgePaddingVertical
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: theme.dividerColor, width: 2),
      ),
      child: Text(
        method,
        style: TextStyle(
          color: Colors.black, 
          fontWeight: FontWeight.w900, 
          fontSize: small ? layout.fontSizeSmall : layout.fontSizeNormal
        ),
      ),
    );
  }
}
