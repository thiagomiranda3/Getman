import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// A single multiline `key: value` text view backing the bulk-edit mode of the
/// params and headers tabs. Format-agnostic: it reports the **raw text** up via
/// [onChanged]; the owning tab view parses it with `BulkKvCodec` and runs its
/// existing `encode` closure, so bulk and row modes produce identical canonical
/// values.
///
/// Echo suppression mirrors `KeyValueListEditor`: the controller is re-seeded
/// only when [initialText] genuinely changes AND differs from the controller's
/// current text, so the BLoC round-trip echo never resets the cursor mid-type.
class BulkKvEditor extends StatefulWidget {
  const BulkKvEditor({
    required this.initialText,
    required this.onChanged,
    super.key,
    this.canonicalize,
    this.fieldPrefix,
  });

  /// The serialized canonical value at open time (and on every external
  /// change).
  final String initialText;

  /// Reports the raw text upward on every keystroke.
  final ValueChanged<String> onChanged;

  /// How the owner canonicalizes raw text before echoing it back as
  /// [initialText] (e.g. `BulkKvCodec.serialize(parse(raw))`). Needed for
  /// echo suppression: the echo of an in-progress edit rarely equals the raw
  /// keystrokes (`X` comes back as `X: `), so an exact-text check alone
  /// re-seeds the field mid-type. Null keeps the exact-text check only.
  final String Function(String raw)? canonicalize;

  /// When set, the field gets a stable `ValueKey('<prefix>_bulk')` so E2E tests
  /// can target it (mirrors `KeyValueListEditor.fieldPrefix`).
  final String? fieldPrefix;

  @override
  State<BulkKvEditor> createState() => _BulkKvEditorState();
}

class _BulkKvEditorState extends State<BulkKvEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void didUpdateWidget(BulkKvEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-seed on a genuine external change — and never clobber what the
    // user is currently typing (the echo of our own emission, matched either
    // exactly or through the owner's canonicalization).
    final echoOfOwnEdit =
        widget.initialText == _controller.text ||
        widget.canonicalize?.call(_controller.text) == widget.initialText;
    if (widget.initialText != oldWidget.initialText && !echoOfOwnEdit) {
      _controller.text = widget.initialText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final theme = Theme.of(context);

    final textStyle = TextStyle(
      fontFamily: typography.codeFontFamily,
      fontSize: layout.fontSizeCode,
      fontWeight: typography.bodyWeight,
      color: theme.colorScheme.onSurface,
    );

    return TextField(
      key: widget.fieldPrefix == null
          ? null
          : ValueKey('${widget.fieldPrefix}_bulk'),
      controller: _controller,
      onChanged: widget.onChanged,
      maxLines: null,
      expands: true,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      autocorrect: false,
      enableSuggestions: false,
      style: textStyle,
      decoration: InputDecoration(
        hintText: 'Key: Value\nKey: Value',
        hintMaxLines: 2,
        alignLabelWithHint: true,
        contentPadding: EdgeInsets.all(layout.inputPadding),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.appShape.inputRadius),
        ),
      ),
    );
  }
}
