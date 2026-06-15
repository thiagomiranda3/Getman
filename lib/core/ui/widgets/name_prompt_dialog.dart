import 'package:flutter/material.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';

/// Single-line name prompt used across collections / tabs for rename,
/// new-folder, save-to-collection, etc. Caller receives the final text via
/// [onConfirm] — pressing confirm closes the dialog first, so the caller can
/// safely trigger navigation or bloc events without a deactivated context.
class NamePromptDialog extends StatefulWidget {
  final String title;
  final String? initialText;
  final String? hintText;
  final String confirmLabel;
  final String cancelLabel;
  final ValueChanged<String> onConfirm;

  /// When true, an empty value is allowed (confirm stays enabled) — used by
  /// free-text fields like a description that can legitimately be cleared.
  final bool allowEmpty;

  /// When true, the field grows to multiple lines (notes / descriptions).
  final bool multiline;

  const NamePromptDialog({
    super.key,
    required this.title,
    required this.onConfirm,
    this.initialText,
    this.hintText,
    this.confirmLabel = 'SAVE',
    this.cancelLabel = 'CANCEL',
    this.allowEmpty = false,
    this.multiline = false,
  });

  /// Convenience wrapper around [showDialog] that builds a [NamePromptDialog].
  static Future<void> show(
    BuildContext context, {
    required String title,
    required ValueChanged<String> onConfirm,
    String? initialText,
    String? hintText,
    String confirmLabel = 'SAVE',
    String cancelLabel = 'CANCEL',
    bool allowEmpty = false,
    bool multiline = false,
  }) {
    return showResponsiveDialog<void>(
      context,
      builder: (_) => NamePromptDialog(
        title: title,
        initialText: initialText,
        hintText: hintText,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        allowEmpty: allowEmpty,
        multiline: multiline,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<NamePromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text;
    if (!widget.allowEmpty && value.trim().isEmpty) return; // matches the disabled-confirm guard
    Navigator.pop(context);
    widget.onConfirm(value);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: widget.multiline ? 3 : 1,
        maxLines: widget.multiline ? 6 : 1,
        keyboardType: widget.multiline ? TextInputType.multiline : null,
        decoration: widget.hintText == null
            ? null
            : InputDecoration(hintText: widget.hintText),
        // Multiline fields use Enter for newlines; submit via the button.
        onSubmitted: widget.multiline ? null : (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
        // Disable confirm while the field is empty so the no-op isn't silent
        // (unless empty is explicitly allowed, e.g. clearing a description).
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => TextButton(
            onPressed: (!widget.allowEmpty && value.text.trim().isEmpty) ? null : _submit,
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}
