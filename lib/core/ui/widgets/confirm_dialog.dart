import 'package:flutter/material.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart'
    show NamePromptDialog;
import 'package:getman/core/ui/widgets/responsive_dialog.dart';

/// A yes/no confirmation for irreversible actions (delete, clear). Mirrors
/// [NamePromptDialog]'s contract: the confirm button closes the dialog first,
/// then runs [onConfirm], so the caller can safely fire navigation or bloc
/// events without a deactivated context. Destructive confirms are tinted with
/// the theme's error color.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    required this.title,
    required this.message,
    required this.onConfirm,
    super.key,
    this.confirmLabel = 'DELETE',
    this.cancelLabel = 'CANCEL',
    this.destructive = true,
  });
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final VoidCallback onConfirm;

  /// Convenience wrapper around [showResponsiveDialog].
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onConfirm,
    String confirmLabel = 'DELETE',
    String cancelLabel = 'CANCEL',
    bool destructive = true,
  }) {
    return showResponsiveDialog<void>(
      context,
      builder: (_) => ConfirmDialog(
        title: title,
        message: message,
        onConfirm: onConfirm,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ResponsiveDialogScaffold(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onConfirm();
          },
          style: destructive
              ? TextButton.styleFrom(foregroundColor: colorScheme.error)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
