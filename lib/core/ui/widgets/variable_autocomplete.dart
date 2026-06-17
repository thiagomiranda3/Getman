import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/variable_autocomplete_query.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
import 'package:getman/core/utils/variable_suggestions.dart';

typedef VariableSuggestionsProvider =
    List<VariableSuggestion> Function(String query);

class _NextSuggestionIntent extends Intent {
  const _NextSuggestionIntent();
}

class _PrevSuggestionIntent extends Intent {
  const _PrevSuggestionIntent();
}

class _AcceptSuggestionIntent extends Intent {
  const _AcceptSuggestionIntent();
}

class _DismissSuggestionIntent extends Intent {
  const _DismissSuggestionIntent();
}

class _OpenSuggestionIntent extends Intent {
  const _OpenSuggestionIntent();
}

/// An [Action] whose enablement is read live from [isEnabledCallback] at
/// key-event time. When disabled, the key event is not consumed and falls
/// through to the default text-editing shortcuts.
class _GatedAction extends Action<Intent> {
  _GatedAction({required this.isEnabledCallback, required this.onInvoke});
  final bool Function() isEnabledCallback;
  final VoidCallback onInvoke;

  @override
  bool isEnabled(Intent intent) => isEnabledCallback();

  @override
  Object? invoke(Intent intent) {
    onInvoke();
    return null;
  }
}

/// Wraps a [TextField] ([child]) with a `{{variable}}` autocomplete menu.
/// Typing `{{` (or Cmd/Ctrl+Space) opens a keyboard-navigable overlay built
/// from [suggestionsFor]; accepting inserts `name}}`.
///
/// [onAccepted] is called with the controller's full text after a suggestion
/// is accepted (keyboard or tap). Use it to notify listeners that would
/// otherwise only see programmatic controller mutations via
/// [TextField.onChanged].
class VariableAutocomplete extends StatefulWidget {
  const VariableAutocomplete({
    required this.controller,
    required this.focusNode,
    required this.suggestionsFor,
    required this.child,
    this.onAccepted,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VariableSuggestionsProvider suggestionsFor;
  final ValueChanged<String>? onAccepted;
  final Widget child;

  @override
  State<VariableAutocomplete> createState() => _VariableAutocompleteState();
}

class _VariableAutocompleteState extends State<VariableAutocomplete> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  List<VariableSuggestion> _suggestions = const [];
  int _selected = 0;
  ActiveVariableQuery? _activeQuery;
  bool _dismissed = false; // Esc latch; cleared on the next text change.
  String _lastText = '';

  bool get _isOpen => _entry != null;

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_onControllerChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) _close();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final text = widget.controller.text;
    if (text != _lastText) {
      _dismissed = false;
      _lastText = text;
    }
    _refresh();
  }

  void _refresh() {
    if (_dismissed || !widget.focusNode.hasFocus) return _close();
    final sel = widget.controller.selection;
    if (!sel.isCollapsed || sel.baseOffset < 0) return _close();
    final query = detectActiveVariableQuery(
      widget.controller.text,
      sel.baseOffset,
    );
    if (query == null) return _close();
    final suggestions = widget.suggestionsFor(query.query);
    if (suggestions.isEmpty) return _close();
    _activeQuery = query;
    _suggestions = suggestions;
    _selected = _selected.clamp(0, suggestions.length - 1);
    _open();
    _entry!.markNeedsBuild();
  }

  void _open() {
    if (_entry != null) return;
    _entry = OverlayEntry(builder: _buildMenu);
    Overlay.of(context).insert(_entry!);
  }

  void _close() => _removeOverlay();

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
    _activeQuery = null;
    _suggestions = const [];
    _selected = 0;
  }

  void _moveSelection(int delta) {
    if (!_isOpen || _suggestions.isEmpty) return;
    _selected = (_selected + delta) % _suggestions.length;
    if (_selected < 0) _selected += _suggestions.length;
    _entry!.markNeedsBuild();
  }

  void _acceptAt(int index) {
    final query = _activeQuery;
    if (query == null || index < 0 || index >= _suggestions.length) return;
    final name = _suggestions[index].name;
    final text = widget.controller.text;
    final before = text.substring(0, query.replaceStart);
    final after = text.substring(query.replaceEnd);
    final insert = query.hasClosingBraces ? name : '$name}}';
    final caret =
        before.length + insert.length + (query.hasClosingBraces ? 2 : 0);
    _close();
    widget.controller.value = TextEditingValue(
      text: '$before$insert$after',
      selection: TextSelection.collapsed(offset: caret),
    );
    widget.onAccepted?.call(widget.controller.text);
  }

  void _dismiss() {
    if (!_isOpen) return;
    _dismissed = true;
    _close();
  }

  void _openViaShortcut() {
    _dismissed = false;
    if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
    final sel = widget.controller.selection;
    final hasActive =
        sel.isCollapsed &&
        sel.baseOffset >= 0 &&
        detectActiveVariableQuery(widget.controller.text, sel.baseOffset) !=
            null;
    if (hasActive) {
      _refresh();
      return;
    }
    final text = widget.controller.text;
    final caret = (sel.isCollapsed && sel.baseOffset >= 0)
        ? sel.baseOffset
        : text.length;
    // Insert an empty token; the controller listener then opens the menu.
    widget.controller.value = TextEditingValue(
      text: '${text.substring(0, caret)}{{}}${text.substring(caret)}',
      selection: TextSelection.collapsed(offset: caret + 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowDown):
              _NextSuggestionIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp): _PrevSuggestionIntent(),
          SingleActivator(LogicalKeyboardKey.enter): _AcceptSuggestionIntent(),
          SingleActivator(LogicalKeyboardKey.tab): _AcceptSuggestionIntent(),
          SingleActivator(LogicalKeyboardKey.escape):
              _DismissSuggestionIntent(),
          SingleActivator(LogicalKeyboardKey.space, control: true):
              _OpenSuggestionIntent(),
          SingleActivator(LogicalKeyboardKey.space, meta: true):
              _OpenSuggestionIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _NextSuggestionIntent: _GatedAction(
              isEnabledCallback: () => _isOpen,
              onInvoke: () => _moveSelection(1),
            ),
            _PrevSuggestionIntent: _GatedAction(
              isEnabledCallback: () => _isOpen,
              onInvoke: () => _moveSelection(-1),
            ),
            _AcceptSuggestionIntent: _GatedAction(
              isEnabledCallback: () => _isOpen,
              onInvoke: () => _acceptAt(_selected),
            ),
            _DismissSuggestionIntent: _GatedAction(
              isEnabledCallback: () => _isOpen,
              onInvoke: _dismiss,
            ),
            _OpenSuggestionIntent: _GatedAction(
              isEnabledCallback: () => true,
              onInvoke: _openViaShortcut,
            ),
          },
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final width =
        _link.leaderSize?.width ??
        280.0; // fallback until the target's size is known
    // Group the dropdown with the field's tap region: without this, a
    // pointer-down anywhere on the overlay counts as a tap-outside and
    // unfocuses the field (desktop behavior), closing the menu before a row
    // tap can land.
    return TextFieldTapRegion(
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        offset: const Offset(0, 4),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                // ~6 rows; viewport cap, mirrors inline constraints elsewhere.
                constraints: const BoxConstraints(maxHeight: 240),
                decoration: context.appDecoration.panelBox(context),
                clipBehavior: Clip.antiAlias,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, i) =>
                      _row(context, _suggestions[i], i, i == _selected),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    VariableSuggestion s,
    int index,
    bool selected,
  ) {
    final theme = Theme.of(context);
    final palette = context.appPalette;
    final layout = context.appLayout;
    final c = s.classification;
    final isSecret = c.kind == VariableValueKind.secret;
    final isDynamic = c.kind == VariableValueKind.dynamicValue;
    final preview = isSecret ? '••••' : (c.value ?? '');
    final source = isDynamic ? 'dynamic' : (c.environmentName ?? '');
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return InkWell(
      // Don't pull focus off the text field when a row is tapped — that would
      // blur the field (closing the menu) and lose the caret after accepting.
      canRequestFocus: false,
      onTap: () => _acceptAt(index),
      child: Container(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : null,
        padding: EdgeInsets.symmetric(
          horizontal: layout.isCompact ? 8 : 12,
          vertical: layout.isCompact ? 6 : 8,
        ),
        child: Row(
          children: [
            Flexible(
              child: Text(
                s.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.titleWeight,
                  color: isDynamic
                      ? palette.variableResolved
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (source.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                source,
                style: TextStyle(fontSize: layout.fontSizeNormal, color: muted),
              ),
            ],
            if (preview.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  preview,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: layout.fontSizeNormal,
                    color: muted,
                    fontStyle: isDynamic ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
