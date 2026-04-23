import 'package:flutter/material.dart';

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

  const NamePromptDialog({
    super.key,
    required this.title,
    required this.onConfirm,
    this.initialText,
    this.hintText,
    this.confirmLabel = 'SAVE',
    this.cancelLabel = 'CANCEL',
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
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => NamePromptDialog(
        title: title,
        initialText: initialText,
        hintText: hintText,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
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
    if (value.isEmpty) return;
    Navigator.pop(context);
    widget.onConfirm(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: widget.hintText == null
            ? null
            : InputDecoration(hintText: widget.hintText),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
        TextButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
