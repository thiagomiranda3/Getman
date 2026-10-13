// Virtualized, selectable large-response text. Only visible bounded chunks
// enter Flutter text layout, even for a one-line multi-MB JSON string. Chunk
// indexing runs off the UI isolate and stale results are discarded on re-send.
// Select-all copies the entire displayed document, including unmounted chunks.
// Toolbar Copy/save includes the full body even while showing a short preview.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/large_response_text.dart';

class LargeResponseTextView extends StatefulWidget {
  const LargeResponseTextView({required this.text, super.key});

  final String text;

  @override
  State<LargeResponseTextView> createState() => _LargeResponseTextViewState();
}

class _LargeResponseTextViewState extends State<LargeResponseTextView> {
  List<int>? _ends;
  int _generation = 0;
  bool _allSelected = false;
  late final FocusNode _selectionFocus = FocusNode(
    onKeyEvent: (node, event) {
      if (const [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
      ].contains(event.logicalKey)) {
        _allSelected = false;
      }
      return KeyEventResult.ignored;
    },
  );

  @override
  void initState() {
    super.initState();
    _selectionFocus.addListener(_onFocusChanged);
    unawaited(_index());
  }

  @override
  void didUpdateWidget(covariant LargeResponseTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _ends = null;
      _allSelected = false;
      unawaited(_index());
    }
  }

  void _onFocusChanged() {
    if (!_selectionFocus.hasFocus) _allSelected = false;
  }

  @override
  void dispose() {
    _selectionFocus.dispose();
    super.dispose();
  }

  void _onTextPointerDown(PointerDownEvent event) {
    if (event.buttons == kPrimaryMouseButton) {
      _allSelected = false;
    }
  }

  Future<void> _index() async {
    final generation = ++_generation;
    final ends = await compute(responseTextChunkEnds, widget.text);
    if (!mounted || generation != _generation) return;
    setState(() => _ends = ends);
  }

  @override
  Widget build(BuildContext context) {
    final ends = _ends;
    final layout = context.appLayout;
    final style = TextStyle(
      fontFamily: context.appTypography.codeFontFamily,
      fontSize: layout.fontSizeCode,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return ColoredBox(
      color: context.appPalette.codeBackground,
      child: ends == null
          ? const Center(child: CircularProgressIndicator())
          : Actions(
              actions: {
                SelectAllTextIntent: _ResponseSelectAllAction(
                  () => _allSelected = true,
                ),
                CopySelectionTextIntent: _ResponseCopyAction(
                  () => _allSelected,
                  () => unawaited(
                    Clipboard.setData(ClipboardData(text: widget.text)),
                  ),
                ),
              },
              child: SelectionArea(
                focusNode: _selectionFocus,
                contextMenuBuilder: (context, region) =>
                    AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: region.contextMenuAnchors,
                      buttonItems: region.contextMenuButtonItems.map((
                        item,
                      ) {
                        return ContextMenuButtonItem(
                          type: item.type,
                          label: item.label,
                          onPressed: () {
                            if (item.type == ContextMenuButtonType.copy &&
                                _allSelected) {
                              unawaited(
                                Clipboard.setData(
                                  ClipboardData(text: widget.text),
                                ),
                              );
                              region.hideToolbar();
                            } else {
                              item.onPressed?.call();
                              if (item.type ==
                                  ContextMenuButtonType.selectAll) {
                                _allSelected = true;
                              }
                            }
                          },
                        );
                      }).toList(),
                    ),
                child: ListView.builder(
                  // New documents start at the beginning, even when
                  // arriving offstage with muted tickers.
                  key: ValueKey(_generation),
                  padding: EdgeInsets.all(layout.pagePadding),
                  itemCount: ends.length,
                  itemBuilder: (context, index) {
                    final start = index == 0 ? 0 : ends[index - 1];
                    final end = ends[index];
                    // SelectionArea concatenates chunks verbatim;
                    // preserve boundary newlines too.
                    // Scrollbar interactions must retain select-all.
                    return Listener(
                      onPointerDown: _onTextPointerDown,
                      child: Text(
                        widget.text.substring(start, end),
                        key: ValueKey('large_response_chunk_$index'),
                        style: style,
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

// SelectionArea only knows mounted chunks. Preserve its visual selection and
// ordinary partial-copy behavior, but make select-all copy the source text.
class _ResponseSelectAllAction extends Action<SelectAllTextIntent> {
  _ResponseSelectAllAction(this.onSelected);
  final VoidCallback onSelected;

  @override
  Object? invoke(SelectAllTextIntent intent) {
    final result = callingAction?.invoke(intent);
    onSelected();
    return result;
  }
}

class _ResponseCopyAction extends Action<CopySelectionTextIntent> {
  _ResponseCopyAction(this.isAllSelected, this.copyAll);
  final bool Function() isAllSelected;
  final VoidCallback copyAll;

  @override
  Object? invoke(CopySelectionTextIntent intent) {
    if (isAllSelected()) {
      copyAll();
      return null;
    }
    return callingAction?.invoke(intent);
  }
}
