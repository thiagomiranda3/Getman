// Shared card chrome for a rule/assertion row: enable toggle + delete button
// wrapping the row's own fields.

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Shared card chrome for a rule/assertion row: enable toggle + delete.
class RuleCard extends StatelessWidget {
  const RuleCard({
    required this.enabled,
    required this.onToggle,
    required this.onDelete,
    required this.children,
    super.key,
  });
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Container(
      margin: EdgeInsets.only(bottom: layout.isCompact ? 8 : 12),
      padding: EdgeInsets.all(layout.isCompact ? 8 : 12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor, width: layout.borderThin),
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
              SizedBox(width: layout.tabSpacing),
              Column(
                children: [
                  Switch(
                    value: enabled,
                    onChanged: onToggle,
                  ),
                  context.appDecoration.wrapInteractive(
                    child: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: theme.colorScheme.error,
                        size: layout.iconSize,
                      ),
                      onPressed: onDelete,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
