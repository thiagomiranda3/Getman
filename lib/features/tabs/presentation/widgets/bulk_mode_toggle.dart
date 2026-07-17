// Small BULK/TABLE mode toggle shared by the params and headers editors:
// flips a KeyValueListEditor between row-editing and bulk-text editing.
// Used by ParamsTabView and HeadersTabView.
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Small header above the params/headers editor body offering the row⇄bulk
/// toggle. [bulk] is the current mode; [onToggle] flips it. The icon/label
/// describe the action the tap performs (Postman convention).
class BulkModeToggle extends StatelessWidget {
  const BulkModeToggle({
    required this.bulk,
    required this.onToggle,
    super.key,
  });

  final bool bulk;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final theme = Theme.of(context);
    // In bulk mode the action returns to rows; in row mode it goes to bulk.
    final label = bulk ? 'Edit as rows' : 'Bulk edit';
    final icon = bulk ? Icons.view_list_outlined : Icons.notes_outlined;

    return Align(
      alignment: Alignment.centerRight,
      child: context.appDecoration.wrapInteractive(
        onTap: onToggle,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.badgePaddingHorizontal,
            vertical: layout.badgePaddingVertical,
          ),
          child: Tooltip(
            message: label,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: layout.smallIconSize,
                  color: theme.colorScheme.secondary,
                ),
                SizedBox(width: layout.tabSpacing),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    fontWeight: typography.titleWeight,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
