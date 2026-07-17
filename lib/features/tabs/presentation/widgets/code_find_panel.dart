// Find panel for the JSON body/response code editors: a debounced
// (kFindDebounce) search box over re_editor's CodeFindController, decoupled
// from the finder's own controller so typing stays responsive on large docs.
//
// Gotchas: _query is separate from controller.findInputController — only
// _flush() (after the debounce fires or Enter is pressed) pushes text into
// the finder, which is what actually triggers a scan. Enter/Shift+Enter
// navigate matches via a raw KeyEvent handler, not TextField.onSubmitted
// (which fires once then unfocuses on desktop, dropping the second Enter).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:re_editor/re_editor.dart';

/// How long the find box waits after the last keystroke before actually running
/// a search. re_editor's finder is O(matches × lines): an early prefix like the
/// single character `r` can match tens of thousands of times in a large
/// response, and without this gate every keystroke (`r`, `ra`, `rai`, …) kicks
/// off one of those expensive scans — and they queue on the finder's single
/// isolate. Debouncing means only the query the user actually paused on runs,
/// which is what makes the search feel instant (the final `raio` is a handful
/// of matches). 180 ms is below the threshold of "feels laggy" while still
/// collapsing a burst of typing into one search.
const Duration kFindDebounce = Duration(milliseconds: 180);

/// Height of the open find panel. re_editor overlays the panel on the
/// editor's top edge (padding the content down by this amount), so any
/// control floated over that corner (e.g. the body editor's Beautify button)
/// must offset itself by this height while find mode is active.
const double kFindPanelHeight = 54;

class CodeFindPanel extends StatefulWidget implements PreferredSizeWidget {
  const CodeFindPanel({
    required this.controller,
    required this.readOnly,
    super.key,
  });
  final CodeFindController controller;
  final bool readOnly;

  @override
  State<CodeFindPanel> createState() => _CodeFindPanelState();

  @override
  Size get preferredSize => controller.value == null
      ? Size.zero
      : const Size.fromHeight(kFindPanelHeight);
}

class _CodeFindPanelState extends State<CodeFindPanel> {
  // The visible text field is decoupled from the finder's own
  // `findInputController` so typing stays snappy while the actual search is
  // debounced. `_query` drives the field; we copy it into the finder (which is
  // what triggers a search) only after [kFindDebounce] of quiet.
  late final TextEditingController _query;
  Timer? _debounce;

  // The last value we synced *to* the finder. Lets both listeners tell our own
  // echo apart from an external change (e.g. the finder auto-filling the
  // selected text when find mode opens) and avoid a feedback loop.
  String _lastSynced = '';

  @override
  void initState() {
    super.initState();
    _lastSynced = widget.controller.findInputController.text;
    _query = TextEditingController(text: _lastSynced);
    _query.addListener(_onQueryChanged);
    widget.controller.addListener(_update);
    widget.controller.findInputController.addListener(_onFinderTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.findInputController.removeListener(_onFinderTextChanged);
    widget.controller.removeListener(_update);
    _query
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  /// The user typed in the visible field → (re)arm the debounce. We do NOT
  /// touch the finder yet; that is what keeps intermediate, high-match prefixes
  /// from running.
  void _onQueryChanged() {
    if (_query.text == _lastSynced) return; // our own echo, nothing to do
    _debounce?.cancel();
    _debounce = Timer(kFindDebounce, _flush);
    setState(() {}); // reflect the "searching" (pending) state immediately
  }

  /// Debounce fired (or Enter pressed): push the current query into the finder,
  /// which runs the actual search.
  void _flush() {
    _debounce?.cancel();
    _debounce = null;
    if (_query.text == _lastSynced) {
      if (mounted) setState(() {});
      return;
    }
    _lastSynced = _query.text;
    widget.controller.findInputController.text = _query.text;
    if (mounted) setState(() {});
  }

  /// The finder's own controller changed from the outside (e.g. find mode
  /// auto-filled the selected text). Mirror it into the visible field without
  /// re-arming the debounce.
  void _onFinderTextChanged() {
    final finderText = widget.controller.findInputController.text;
    if (finderText == _lastSynced) return; // echo of our own [_flush] write
    _lastSynced = finderText;
    _query.value = TextEditingValue(
      text: finderText,
      selection: TextSelection.collapsed(offset: finderText.length),
    );
  }

  /// Enter → next match, Shift+Enter → previous match — handled on the raw key
  /// event rather than via `TextField.onSubmitted`, which (on desktop) fires
  /// once and then unfocuses the field, so the second Enter was silently
  /// dropped. Intercepting here keeps focus, so the keys repeat.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    // A still-pending query has to run before navigation means anything.
    if (_debounce?.isActive ?? false) {
      _flush();
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      widget.controller.previousMatch();
    } else {
      widget.controller.nextMatch();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.value == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final layout = context.appLayout;
    final matchCount = widget.controller.value?.result?.matches.length ?? 0;
    final busy =
        (_debounce?.isActive ?? false) ||
        (widget.controller.value?.searching ?? false);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: layout.borderThick,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              // Observe Enter/Shift+Enter without joining tab traversal or
              // stealing focus from the field.
              skipTraversal: true,
              canRequestFocus: false,
              onKeyEvent: _handleKeyEvent,
              child: TextField(
                controller: _query,
                focusNode: widget.controller.findInputFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'FIND...',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: layout.iconSize),
                  // While a search is pending/running show a spinner instead of a
                  // stale "0/0" — previously the panel sat on "0/0" during the
                  // (multi-second, on a big response) scan, reading as "no
                  // results" until they suddenly appeared.
                  suffixIcon: busy
                      ? Padding(
                          key: const ValueKey('find_searching'),
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: layout.iconSize,
                            height: layout.iconSize,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : null,
                  suffixText: busy
                      ? null
                      : (matchCount > 0
                            ? '${(widget.controller.value?.result?.index ?? 0) + 1}/$matchCount'
                            : '0/0'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_up, size: layout.iconSize),
            onPressed: () => widget.controller.previousMatch(),
          ),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, size: layout.iconSize),
            onPressed: () => widget.controller.nextMatch(),
          ),
          IconButton(
            icon: Icon(Icons.close, size: layout.iconSize),
            onPressed: () => widget.controller.close(),
          ),
        ],
      ),
    );
  }
}
