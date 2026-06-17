import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/variable_autocomplete.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';
import 'package:getman/core/ui/widgets/variable_hover_popover.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
import 'package:getman/core/utils/variable_suggestions.dart';

/// Generic editable key/value row list backing the params, headers, and
/// environment-variable editors. The canonical value type [T] (ordered list,
/// map, …) is supplied via a codec:
///
/// - [decode] turns [items] into ordered (key, value) rows;
/// - [encode] turns the current rows back into a [T] for [onChanged];
/// - [equals] compares two [T]s in canonical space.
///
/// Echo suppression: when the parent echoes back exactly what this editor
/// just emitted (the usual BLoC round-trip), the text controllers are NOT
/// rebuilt — that keeps focus and half-typed state alive. Only a genuinely
/// external change resets the rows. See CLAUDE.md §6.
class KeyValueListEditor<T extends Object> extends StatefulWidget {
  const KeyValueListEditor({
    required this.items,
    required this.onChanged,
    required this.decode,
    required this.encode,
    required this.equals,
    super.key,
    this.secretKeys,
    this.onSecretKeysChanged,
    this.variableContext,
    this.fieldPrefix,
  });
  final T items;
  final ValueChanged<T> onChanged;
  final List<(String, String)> Function(T items) decode;
  final T Function(List<(String, String)> rows) encode;
  final bool Function(T a, T b) equals;

  /// Names flagged secret. When non-null, each row shows a lock toggle and
  /// secret rows obscure their value (with a reveal toggle). Null (the default,
  /// used by params/headers) disables all secret affordances.
  final Set<String>? secretKeys;

  /// Called with the new secret-key set when a row's lock is toggled.
  final ValueChanged<Set<String>>? onSecretKeysChanged;

  /// When non-null, value fields highlight `{{var}}` tokens and show a hover
  /// popover resolving them against the active environment. Params and headers
  /// pass a context (highlighting enabled); the env editor and other consumers
  /// pass null, leaving value fields as plain text. Note: this is unrelated to
  /// [secretKeys], which toggles per-row secret obscuring in the env editor.
  final VariableHoverContext? variableContext;

  /// When set, each row's key/value [TextField] gets a stable
  /// `ValueKey('<prefix>_key_<index>')` / `ValueKey('<prefix>_val_<index>')` so
  /// E2E tests can target a specific row in a specific editor (params/headers/
  /// env vars all use this widget). Null (the default) leaves fields unkeyed.
  final String? fieldPrefix;

  @override
  State<KeyValueListEditor<T>> createState() => _KeyValueListEditorState<T>();
}

class _KeyValueListEditorState<T extends Object>
    extends State<KeyValueListEditor<T>> {
  late List<TextEditingController> _keyControllers;
  late List<TextEditingController> _valControllers;
  T? _lastEmitted;

  final VariableHoverController _hoverController = VariableHoverController();

  @override
  void initState() {
    super.initState();
    _initControllers(widget.decode(widget.items));
  }

  TextEditingController _newValueController(String value) {
    return widget.variableContext != null
        ? VariableHighlightController(text: value)
        : TextEditingController(text: value);
  }

  void _initControllers(List<(String, String)> rows) {
    _keyControllers = [
      for (final (key, _) in rows) TextEditingController(text: key),
    ];
    _valControllers = [
      for (final (_, value) in rows) _newValueController(value),
    ];
    _addEmptyRow();
  }

  void _addEmptyRow() {
    _keyControllers.add(TextEditingController());
    _valControllers.add(_newValueController(''));
  }

  void _showVariablePopover(BuildContext context, String name, Offset pos) {
    if (!mounted) return;
    final varContext = widget.variableContext;
    if (varContext == null) return;
    final data = VariableResolutionHelper.classify(
      name: name,
      variables: varContext.variables,
      secretKeys: varContext.secretKeys,
      environmentName: varContext.environmentName,
    );
    _hoverController.showFor(context, data, pos);
  }

  @override
  void didUpdateWidget(KeyValueListEditor<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lastEmitted = _lastEmitted;
    if (lastEmitted != null && widget.equals(widget.items, lastEmitted)) {
      return;
    }
    if (widget.equals(widget.items, oldWidget.items)) {
      return;
    }
    _disposeControllers();
    _initControllers(widget.decode(widget.items));
    _lastEmitted = null;
  }

  void _disposeControllers() {
    for (final c in _keyControllers) {
      c.dispose();
    }
    for (final c in _valControllers) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _disposeControllers();
    super.dispose();
  }

  void _emit() {
    final rows = [
      for (int i = 0; i < _keyControllers.length; i++)
        (_keyControllers[i].text, _valControllers[i].text),
    ];
    final value = widget.encode(rows);
    _lastEmitted = value;
    widget.onChanged(value);
  }

  void _toggleSecret(int index) {
    final secrets = widget.secretKeys;
    if (secrets == null) return;
    final key = _keyControllers[index].text.trim();
    if (key.isEmpty) return;
    final next = Set<String>.of(secrets);
    next.contains(key) ? next.remove(key) : next.add(key);
    widget.onSecretKeysChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return ListView.builder(
      itemCount: _keyControllers.length,
      itemBuilder: (context, index) {
        final secrets = widget.secretKeys;
        // Compare trimmed — secretKeys is stored trimmed (matches _toggleSecret
        // and the env editor's trimming encode), so an untrimmed compare would
        // mis-flag a key with surrounding whitespace.
        final keyText = _keyControllers[index].text.trim();

        final varContext = widget.variableContext;
        final valController = _valControllers[index];
        VariableSuggestionsProvider? valueSuggestionsFor;
        if (varContext != null &&
            valController is VariableHighlightController) {
          final palette = context.appPalette;
          // Block syntax for onVariableEnter prevents the arrow-function body
          // from greedily capturing the following cascade item as part of its
          // return expression, which would trigger use_of_void_result.
          valController
            ..onVariableEnter = (name, pos) {
              _showVariablePopover(context, name, pos);
            }
            ..onVariableExit = _hoverController.scheduleHide
            ..updateColors(
              resolved: palette.variableResolved,
              unresolved: palette.variableUnresolved,
            )
            ..updateVariables(varContext.variables);
          valueSuggestionsFor = (query) => buildVariableSuggestions(
            query: query,
            userVariableNames: varContext.variables.keys,
            classify: (name) => VariableResolutionHelper.classify(
              name: name,
              variables: varContext.variables,
              secretKeys: varContext.secretKeys,
              environmentName: varContext.environmentName,
            ),
          );
        }

        return _KeyValueRow(
          key: ValueKey(_keyControllers[index]),
          rowIndex: index,
          fieldPrefix: widget.fieldPrefix,
          keyController: _keyControllers[index],
          valController: _valControllers[index],
          layout: layout,
          showSecretToggle: secrets != null,
          isSecret:
              secrets != null &&
              keyText.isNotEmpty &&
              secrets.contains(keyText),
          onToggleSecret: secrets == null ? null : () => _toggleSecret(index),
          valueSuggestionsFor: valueSuggestionsFor,
          onKeyChanged: (val) {
            if (index == _keyControllers.length - 1 && val.isNotEmpty) {
              setState(_addEmptyRow);
            }
            _emit();
          },
          onValChanged: (_) => _emit(),
          onDelete: () {
            setState(() {
              _keyControllers.removeAt(index).dispose();
              _valControllers.removeAt(index).dispose();
              if (_keyControllers.isEmpty) {
                _addEmptyRow();
              }
              _emit();
            });
          },
        );
      },
    );
  }
}

class _KeyValueRow extends StatefulWidget {
  const _KeyValueRow({
    required this.keyController,
    required this.valController,
    required this.layout,
    required this.onKeyChanged,
    required this.onValChanged,
    required this.onDelete,
    super.key,
    this.rowIndex = 0,
    this.fieldPrefix,
    this.showSecretToggle = false,
    this.isSecret = false,
    this.onToggleSecret,
    this.valueSuggestionsFor,
  });
  final int rowIndex;
  final String? fieldPrefix;
  final TextEditingController keyController;
  final TextEditingController valController;
  final AppLayout layout;
  final ValueChanged<String> onKeyChanged;
  final ValueChanged<String> onValChanged;
  final VoidCallback onDelete;
  final bool showSecretToggle;
  final bool isSecret;
  final VoidCallback? onToggleSecret;
  final VariableSuggestionsProvider? valueSuggestionsFor;

  @override
  State<_KeyValueRow> createState() => _KeyValueRowState();
}

class _KeyValueRowState extends State<_KeyValueRow> {
  bool _isHovered = false;
  bool _revealed = false;
  final FocusNode _valueFocusNode = FocusNode();

  @override
  void dispose() {
    _valueFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_KeyValueRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset reveal whenever secret status flips so a row re-marked secret
    // always starts obscured instead of inheriting a stale "revealed".
    if (oldWidget.isSecret != widget.isSecret) _revealed = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPhone = context.isPhone;
    final fieldPadding = EdgeInsets.all(widget.layout.isCompact ? 8 : 12);
    final textStyle = TextStyle(
      fontSize: widget.layout.fontSizeNormal,
      fontWeight: context.appTypography.titleWeight,
    );

    final keyField = TextField(
      key: widget.fieldPrefix == null
          ? null
          : ValueKey('${widget.fieldPrefix}_key_${widget.rowIndex}'),
      style: textStyle,
      decoration: InputDecoration(
        hintText: 'KEY',
        isDense: true,
        contentPadding: fieldPadding,
      ),
      controller: widget.keyController,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: widget.onKeyChanged,
    );
    final valueField = TextField(
      key: widget.fieldPrefix == null
          ? null
          : ValueKey('${widget.fieldPrefix}_val_${widget.rowIndex}'),
      style: textStyle,
      focusNode: _valueFocusNode,
      obscureText: widget.isSecret && !_revealed,
      decoration: InputDecoration(
        hintText: 'VALUE',
        isDense: true,
        contentPadding: fieldPadding,
        // Reveal toggle lives in the field so the row layout is unchanged.
        suffixIcon: widget.isSecret
            ? IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _revealed ? Icons.visibility_off : Icons.visibility,
                  size: widget.layout.isCompact ? 18 : 20,
                ),
                tooltip: _revealed ? 'Hide value' : 'Reveal value',
                onPressed: () => setState(() => _revealed = !_revealed),
              )
            : null,
      ),
      controller: widget.valController,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: widget.onValChanged,
    );
    final valueFieldWithAutocomplete = widget.valueSuggestionsFor == null
        ? valueField
        : VariableAutocomplete(
            controller: widget.valController,
            focusNode: _valueFocusNode,
            suggestionsFor: widget.valueSuggestionsFor!,
            onAccepted: widget.onValChanged,
            child: valueField,
          );
    final secretButton = widget.showSecretToggle
        ? context.appDecoration.wrapInteractive(
            child: IconButton(
              icon: Icon(
                widget.isSecret ? Icons.lock_outline : Icons.lock_open_outlined,
                size: widget.layout.isCompact ? 20 : 24,
                color: widget.isSecret
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              tooltip: widget.isSecret ? 'Unmark secret' : 'Mark secret',
              onPressed: widget.onToggleSecret,
            ),
          )
        : null;
    final deleteButton = context.appDecoration.wrapInteractive(
      child: IconButton(
        icon: Icon(
          Icons.delete_outline,
          size: widget.layout.isCompact ? 20 : 24,
          color: theme.colorScheme.error,
        ),
        onPressed: widget.onDelete,
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: widget.layout.isCompact ? 8.0 : 12.0),
        padding: EdgeInsets.symmetric(
          horizontal: isPhone ? 8 : 4,
          vertical: isPhone ? 8 : 2,
        ),
        decoration: BoxDecoration(
          color: _isHovered
              ? theme.hoverColor
              : (isPhone ? theme.colorScheme.surface : Colors.transparent),
          borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          border: Border.all(
            color: isPhone
                ? theme.dividerColor.withValues(alpha: 0.6)
                : (_isHovered
                      ? theme.dividerColor.withValues(alpha: 0.5)
                      : Colors.transparent),
            width: widget.layout.borderThin,
          ),
        ),
        child: isPhone
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: keyField),
                      ?secretButton,
                      deleteButton,
                    ],
                  ),
                  SizedBox(height: widget.layout.tabSpacing),
                  valueFieldWithAutocomplete,
                ],
              )
            : Row(
                children: [
                  Expanded(child: keyField),
                  SizedBox(width: widget.layout.isCompact ? 8 : 12),
                  Expanded(child: valueFieldWithAutocomplete),
                  SizedBox(width: widget.layout.isCompact ? 4 : 8),
                  ?secretButton,
                  deleteButton,
                ],
              ),
      ),
    );
  }
}
