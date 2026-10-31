// Routes find on oversized code lines to the existing windowed text search.
// re_editor disables its rendering budget during find; removing its viewport
// while searching avoids laying out a multi-megabyte line on the UI isolate.
// Controllers remain owned by their callers; closing search restores editing.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getman/features/tabs/presentation/widgets/response/large_body_find_view.dart';
import 'package:re_editor/re_editor.dart';

class LargeLineFindGuard extends StatefulWidget {
  LargeLineFindGuard({
    required this.controller,
    required this.lineLimit,
    required this.editorBuilder,
    this.findController,
    Key? key,
  }) : super(key: key ?? _FindGuardKey(controller));

  final CodeLineEditingController controller;
  final int lineLimit;
  final CodeFindController? findController;
  final Widget Function(CodeFindController) editorBuilder;

  @override
  State<LargeLineFindGuard> createState() => _LargeLineFindGuardState();
}

class _FindGuardKey extends GlobalObjectKey<_LargeLineFindGuardState> {
  const _FindGuardKey(super.value);
}

class _LargeLineFindGuardState extends State<LargeLineFindGuard> {
  late CodeFindController _finder;
  late CodeLines _observedLines;
  late bool _findOpen;
  CodeLines? _checkedLines;
  String? _largeText;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _finder = widget.findController ?? CodeFindController(widget.controller);
    _observedLines = widget.controller.codeLines;
    _findOpen = _finder.value != null;
    _finder.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  void _detach(LargeLineFindGuard owner) {
    owner.controller.removeListener(_changed);
    _finder.removeListener(_changed);
    if (owner.findController == null) _finder.dispose();
  }

  @override
  void didUpdateWidget(LargeLineFindGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.findController != widget.findController) {
      _detach(oldWidget);
      _checkedLines = null;
      _attach();
    }
    if (oldWidget.lineLimit != widget.lineLimit) _checkedLines = null;
  }

  void _changed() {
    // Ignore selection/repaint and match-result echoes, including notifications
    // from the editor mounting below us during build.
    final open = _finder.value != null;
    final lines = widget.controller.codeLines;
    final changed =
        open != _findOpen || (open && !identical(lines, _observedLines));
    _findOpen = open;
    _observedLines = lines;
    if (changed) setState(() {});
  }

  bool _hasLongLine() {
    // Iterative traversal includes folded chunks without recursive stack growth
    // or CodeLines[index]'s repeated segment scans.
    final pending = <Iterator<CodeLine>>[
      for (final segment in widget.controller.codeLines.segments)
        segment.iterator,
    ];
    while (pending.isNotEmpty) {
      final iterator = pending.last;
      if (!iterator.moveNext()) {
        pending.removeLast();
        continue;
      }
      final line = iterator.current;
      if (line.length > widget.lineLimit) return true;
      if (line.chunks.isNotEmpty) pending.add(line.chunks.iterator);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_finder.value == null) {
      _largeText = null;
      _checkedLines = null;
      return widget.editorBuilder(_finder);
    }
    if (!identical(_checkedLines, widget.controller.codeLines)) {
      _checkedLines = widget.controller.codeLines;
      _largeText = _hasLongLine() ? widget.controller.text : null;
    }
    final text = _largeText;
    if (text == null) return widget.editorBuilder(_finder);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _finder.close,
      },
      child: LargeBodyFindView(
        body: text,
        // Avoid putting an enormous selected body in a single-line TextField.
        initialQuery: _finder.findInputController.text.length <= 1024
            ? _finder.findInputController.text
            : '',
        fallback: const Center(
          child: Text('Search the full text. Close search to resume editing.'),
        ),
        onClose: _finder.close,
      ),
    );
  }

  @override
  void dispose() {
    _detach(widget);
    super.dispose();
  }
}
