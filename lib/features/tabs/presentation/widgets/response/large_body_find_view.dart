// Windowed find for large plain-text response bodies (C1 "find everywhere"):
// match offsets are scanned OFF the UI isolate (compute over the verbatim
// large-body cache) and only a kPlainTextFindWindowChars slice around the
// current match is rendered with highlight spans, so highlight cost is
// independent of body size — no extra size cap needed. While the query is
// empty or has no matches the caller-supplied [fallback] (the normal
// preview/SHOW FULL SelectableText) renders instead. Enter/Shift+Enter step
// matches via a raw KeyEvent handler (TextField.onSubmitted unfocuses on
// desktop after the first Enter — same gotcha as code_find_panel.dart).
// Highlight colors come from AppPalette.findMatchHighlight/-ActiveHighlight.
// Every padding/spacing literal routes through AppLayout rather than a
// hardcoded EdgeInsets, per the theme-adherence mandate (matching the
// f4419a2/0b86cf9 fixes to json_tree_view.dart / response_row_filter_bar.dart):
// the bar's own padding uses pagePadding/tabSpacing, the TextField's
// contentPadding uses inputPadding/inputPaddingVertical, the field↔buttons
// gap uses tabSpacing, and the inline spinner's padding uses the
// isCompact ? 8 : 12 idiom seen throughout (e.g. auth_tab_view.dart).
import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/plain_text_find.dart';
import 'package:getman/features/tabs/presentation/widgets/code_find_panel.dart'
    show kFindDebounce;

/// Find bar + windowed snippet view over a large plain-text [body].
///
/// The scan runs via `compute` ([findMatchOffsets]); the snippet is a
/// [kPlainTextFindWindowChars] window centered on the current match
/// ([buildPlainTextFindWindow] / [buildPlainTextFindSpans]).
class LargeBodyFindView extends StatefulWidget {
  const LargeBodyFindView({
    required this.body,
    required this.fallback,
    required this.onClose,
    super.key,
  });

  /// The verbatim large-body cache (the same text Copy uses).
  final String body;

  /// Shown below the bar while the query is empty or matchless — the caller
  /// passes its normal plain-text view so behavior is unchanged until a
  /// match exists.
  final Widget fallback;

  /// Called when the user closes the find bar; the caller restores the
  /// normal (bar-less) view.
  final VoidCallback onClose;

  @override
  State<LargeBodyFindView> createState() => _LargeBodyFindViewState();
}

class _LargeBodyFindViewState extends State<LargeBodyFindView> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;

  // Scan results. _matchLength is captured when the scan lands (the query
  // may have changed since); _scanGen discards stale isolate results.
  List<int> _offsets = const [];
  int _current = 0;
  int _matchLength = 0;
  int _scanGen = 0;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LargeBodyFindView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) {
      // New response body: rescan the current query against it.
      _debounce?.cancel();
      unawaited(_scan());
    }
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(kFindDebounce, () => unawaited(_scan()));
    setState(() {}); // reflect the pending state immediately
  }

  Future<void> _scan() async {
    final gen = ++_scanGen;
    final q = _query.text;
    if (q.isEmpty) {
      setState(() {
        _offsets = const [];
        _current = 0;
        _matchLength = 0;
        _scanning = false;
      });
      return;
    }
    setState(() => _scanning = true);
    // Off the UI isolate: the body here is >512 KiB by definition.
    final offsets = await compute(
      findMatchOffsets,
      PlainTextFindArgs(haystack: widget.body, query: q),
    );
    if (!mounted || gen != _scanGen) return;
    setState(() {
      _offsets = offsets;
      _current = 0;
      _matchLength = q.length;
      _scanning = false;
    });
  }

  void _step(int delta) {
    final n = _offsets.length;
    if (n == 0) return;
    setState(() => _current = (_current + delta + n) % n);
  }

  /// Enter → next, Shift+Enter → previous (raw key handler; see header).
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    _step(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBar(context),
        Expanded(
          child: _offsets.isEmpty ? widget.fallback : _buildWindow(context),
        ),
      ],
    );
  }

  Widget _buildBar(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final n = _offsets.length;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.pagePadding,
        vertical: layout.tabSpacing,
      ),
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
                key: const ValueKey('large_find_field'),
                controller: _query,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'FIND...',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: layout.iconSize),
                  suffixIcon: _scanning
                      ? Padding(
                          key: const ValueKey('large_find_searching'),
                          padding: EdgeInsets.all(layout.isCompact ? 8 : 12),
                          child: SizedBox(
                            width: layout.iconSize,
                            height: layout.iconSize,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : null,
                  suffixText: _scanning
                      ? null
                      : (n > 0 ? '${_current + 1}/$n' : '0/0'),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: layout.inputPadding,
                    vertical: layout.inputPaddingVertical,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: layout.tabSpacing),
          IconButton(
            key: const ValueKey('large_find_prev'),
            icon: Icon(Icons.keyboard_arrow_up, size: layout.iconSize),
            onPressed: () => _step(-1),
          ),
          IconButton(
            key: const ValueKey('large_find_next'),
            icon: Icon(Icons.keyboard_arrow_down, size: layout.iconSize),
            onPressed: () => _step(1),
          ),
          IconButton(
            key: const ValueKey('large_find_close'),
            icon: Icon(Icons.close, size: layout.iconSize),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildWindow(BuildContext context) {
    final palette = context.appPalette;
    final layout = context.appLayout;
    final typography = context.appTypography;
    final theme = Theme.of(context);

    final window = buildPlainTextFindWindow(
      haystack: widget.body,
      offsets: _offsets,
      currentMatch: _current,
      matchLength: _matchLength,
    );
    final baseStyle = TextStyle(
      fontFamily: typography.codeFontFamily,
      fontSize: layout.fontSizeCode,
      color: theme.colorScheme.onSurface,
    );
    final spans = buildPlainTextFindSpans(
      window,
      baseStyle: baseStyle,
      matchColor: palette.findMatchHighlight,
      activeMatchColor: palette.findMatchActiveHighlight,
    );

    return ColoredBox(
      color: palette.codeBackground,
      child: SingleChildScrollView(
        // Keyed by window position: stepping to a match in a different
        // window region remounts the scroll view, resetting its offset —
        // that is the "re-center" behavior, for the cost of a 4 KiB rebuild.
        key: ValueKey('large_find_scroll_${window.windowStart}'),
        padding: EdgeInsets.all(layout.pagePadding),
        child: SelectableText.rich(
          TextSpan(
            children: [
              if (window.clippedStart) TextSpan(text: '…\n', style: baseStyle),
              ...spans,
              if (window.clippedEnd) TextSpan(text: '\n…', style: baseStyle),
            ],
          ),
          key: const ValueKey('large_find_window_text'),
        ),
      ),
    );
  }
}
