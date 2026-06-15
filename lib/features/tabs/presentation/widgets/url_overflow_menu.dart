import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

enum _OverflowAction { generateCode, save, toggleLayout }

/// Narrow-layout overflow menu for the URL bar, collapsing the
/// generate-code / save / layout-toggle actions behind a single button.
class UrlOverflowMenu extends StatelessWidget {
  final double iconSize;
  final bool isSaved;
  final bool isVerticalLayout;
  final VoidCallback onGenerateCode;
  final VoidCallback onSave;
  final VoidCallback onToggleLayout;

  const UrlOverflowMenu({
    super.key,
    required this.iconSize,
    required this.isSaved,
    required this.isVerticalLayout,
    required this.onGenerateCode,
    required this.onSave,
    required this.onToggleLayout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return PopupMenuButton<_OverflowAction>(
      tooltip: 'More actions',
      position: PopupMenuPosition.under,
      color: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        side: BorderSide(color: theme.dividerColor, width: layout.borderThick),
      ),
      elevation: 0,
      icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurface, size: iconSize),
      onSelected: (action) {
        switch (action) {
          case _OverflowAction.generateCode:
            onGenerateCode();
            break;
          case _OverflowAction.save:
            onSave();
            break;
          case _OverflowAction.toggleLayout:
            onToggleLayout();
            break;
        }
      },
      itemBuilder: (popupContext) => [
        PopupMenuItem(
          value: _OverflowAction.save,
          child: _menuRow(
            context,
            isSaved ? Icons.save : Icons.save_as,
            isSaved ? 'UPDATE REQUEST' : 'SAVE TO COLLECTION',
            theme.colorScheme.secondary,
          ),
        ),
        PopupMenuItem(
          value: _OverflowAction.generateCode,
          child: _menuRow(context, Icons.code, 'GENERATE CODE', theme.colorScheme.secondary),
        ),
        PopupMenuItem(
          value: _OverflowAction.toggleLayout,
          child: _menuRow(
            context,
            isVerticalLayout ? Icons.view_column_rounded : Icons.view_agenda_rounded,
            isVerticalLayout ? 'HORIZONTAL LAYOUT' : 'VERTICAL LAYOUT',
            theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _menuRow(BuildContext context, IconData icon, String label, Color iconColor) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: layout.smallIconSize, color: iconColor),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontWeight: context.appTypography.displayWeight,
            fontSize: layout.fontSizeNormal,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
