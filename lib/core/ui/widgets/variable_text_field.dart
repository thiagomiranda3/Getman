// TextField that combines variable highlighting
// (VariableHighlightController), `{{`-triggered autocomplete
// (VariableAutocomplete), and a hover-resolution popover
// (VariableHoverPopover) behind one widget — the controller is caller-owned
// so its echo-suppression survives the BLoC round-trip.
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/variable_autocomplete.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';
import 'package:getman/core/ui/widgets/variable_hover_popover.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/core/utils/variable_suggestions.dart';

/// A [TextField] that highlights `{{var}}` tokens, offers a `{{`-triggered
/// autocomplete overlay, and shows a hover popover resolving each token —
/// given a [variables] context and a caller-owned [VariableHighlightController]
/// (kept by the owner so its echo-suppression survives the bloc round-trip).
/// When [variables] is empty it degrades to a plain styled field.
class VariableTextField extends StatefulWidget {
  const VariableTextField({
    required this.variables,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.decoration,
    this.style,
    this.obscureText = false,
    this.fieldKey,
    super.key,
  });

  final LayeredVariableContext variables;
  final VariableHighlightController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final InputDecoration? decoration;
  final TextStyle? style;
  final bool obscureText;
  final Key? fieldKey;

  @override
  State<VariableTextField> createState() => _VariableTextFieldState();
}

class _VariableTextFieldState extends State<VariableTextField> {
  final VariableHoverController _hover = VariableHoverController();

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  void _showPopover(String name, Offset globalPosition) {
    if (!mounted) return;
    _hover.showFor(context, widget.variables.classify(name), globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final ctx = widget.variables;

    // Wire highlight colors + variable map + hover sinks onto the controller.
    widget.controller
      ..updateColors(
        resolved: palette.variableResolved,
        unresolved: palette.variableUnresolved,
      )
      ..updateVariables(ctx.allVariables)
      ..onVariableEnter = _showPopover
      ..onVariableExit = _hover.scheduleHide;

    final field = TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      decoration: widget.decoration,
      style: widget.style,
      obscureText: widget.obscureText,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: widget.onChanged,
    );

    // Always offer autocomplete: dynamic built-ins ({{$guid}}, {{$timestamp}}…)
    // are suggestable even with no active environment, matching the URL bar.
    // The overlay self-closes when a query matches nothing.
    return VariableAutocomplete(
      controller: widget.controller,
      focusNode: widget.focusNode,
      suggestionsFor: (query) => buildVariableSuggestions(
        query: query,
        userVariableNames: ctx.allVariables.keys,
        classify: ctx.classify,
      ),
      onAccepted: widget.onChanged,
      child: field,
    );
  }
}
