// Request-only editor assistance: learned fields and caret-anchored variable
// suggestions. Option+Space on macOS / Ctrl+Space elsewhere opens completion;
// replacing a full token keeps
// suffixes/paired delimiters intact. Restored bodies seed the learning baseline.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getman/core/navigation/shortcut_catalog.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
import 'package:getman/core/utils/variable_suggestions.dart';
import 'package:getman/features/tabs/domain/logic/body_completion.dart';
import 'package:getman/features/tabs/domain/logic/json_field_extractor.dart';
import 'package:getman/features/tabs/presentation/bloc/body_field_dictionary_cubit.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:re_editor/re_editor.dart';

class BodyCodeEditor extends StatefulWidget {
  const BodyCodeEditor({
    required this.controller,
    required this.variableContext,
    this.dictionary,
    this.findController,
    this.fieldsEnabled = true,
    super.key,
  });
  final CodeLineEditingController controller;
  final LayeredVariableContext variableContext;
  final BodyFieldDictionaryCubit? dictionary;
  final CodeFindController? findController;
  final bool fieldsEnabled;
  @override
  State<BodyCodeEditor> createState() => _BodyCodeEditorState();
}

class _BodyCodeEditorState extends State<BodyCodeEditor> {
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _gutterKey = GlobalKey();
  final _scroll = ScrollController();
  late final FocusNode _focus;
  CodeIndicatorValueNotifier? _indicator;
  Timer? _learnTimer;
  late String _text;
  late CodeLines _lines;
  Map<String, int> _counts = {};
  int _revision = 0;
  int _learnedRevision = 0;
  BodyCompletionTarget? _target;
  List<({String name, String detail})> _suggestions = [];
  int _selected = 0;
  bool _explicit = false;
  bool _refreshScheduled = false;
  bool _showOnRefresh = true;
  Rect? _caret;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode(onKeyEvent: _onKey)..addListener(_onFocus);
    _attach();
  }

  void _attach() {
    _text = widget.controller.text;
    _lines = widget.controller.codeLines;
    _counts = _fieldCounts(_text);
    _learnedRevision = _revision;
    widget.controller.addListener(_onChanged);
  }

  Map<String, int> _fieldCounts(String text) =>
      widget.fieldsEnabled && text.length <= 1024 * 1024
      ? extractJsonFieldCounts(text)
      : {};

  @override
  void didUpdateWidget(BodyCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      _learnTimer?.cancel();
      _revision++;
      _target = null;
      _attach();
    } else if (oldWidget.fieldsEnabled != widget.fieldsEnabled) {
      _learnTimer?.cancel();
      _revision++;
      _counts = _fieldCounts(_text);
      _target = null;
    }
    if (oldWidget.variableContext != widget.variableContext) {
      _target = null;
      _scheduleRefresh();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _target = null;
      _explicit = false;
    }
  }

  void _onFocus() {
    if (!_focus.hasFocus) {
      _explicit = false;
      _scheduleRefresh(show: false);
    }
  }

  void _onChanged() {
    if (_lines == widget.controller.codeLines) {
      _target = null;
      _explicit = false;
      _scheduleRefresh(show: false);
      return;
    }
    _lines = widget.controller.codeLines;
    final text = widget.controller.text;
    if (text == _text) return;
    _target = null;
    _text = text;
    _revision++;
    _learnTimer?.cancel();
    _learnTimer = Timer(const Duration(milliseconds: 200), _learn);
    _scheduleRefresh();
  }

  Future<void> _learn() async {
    final dictionary = widget.dictionary;
    if (!widget.fieldsEnabled || dictionary == null) return;
    final text = _text;
    final revision = _revision;
    final next = text.length > 1024 * 1024
        ? <String, int>{}
        : text.length > 100000
        ? await compute(extractJsonFieldCounts, text)
        : extractJsonFieldCounts(text);
    if (!mounted || revision != _revision) return;
    final additions = _newOccurrences(next);
    _learnedRevision = revision;
    if (additions.isNotEmpty) await dictionary.recordUsage(additions);
  }

  Map<String, int> _newOccurrences(Map<String, int> next) {
    final additions = <String, int>{
      for (final entry in next.entries)
        if (entry.value > (_counts[entry.key] ?? 0))
          entry.key: entry.value - (_counts[entry.key] ?? 0),
    };
    // A temporary syntax error can hide later keys from the tolerant scanner.
    // Retain each session's high-water counts so fixing it (or undoing) does
    // not record those same occurrences again.
    for (final entry in next.entries) {
      _counts[entry.key] = math.max(_counts[entry.key] ?? 0, entry.value);
    }
    return additions;
  }

  void _scheduleRefresh({bool show = true}) {
    _showOnRefresh = show;
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted) return;
      if (_showOnRefresh) {
        _refresh();
      } else {
        _dismiss();
      }
    });
  }

  int get _absoluteCaret {
    final selection = widget.controller.unfoldLineSelection;
    final separator = widget.controller.options.lineBreak.value;
    final lines = _text.split(separator);
    var offset = 0;
    for (var i = 0; i < selection.extentIndex && i < lines.length; i++) {
      offset += lines[i].length + separator.length;
    }
    return offset + selection.extentOffset;
  }

  void _refresh() {
    if (!_focus.hasFocus ||
        !TickerMode.valuesOf(context).enabled ||
        widget.controller.isComposing ||
        !widget.controller.selection.isCollapsed) {
      _dismiss();
      return;
    }
    final target = detectBodyCompletion(
      _text,
      _absoluteCaret,
      explicit: _explicit,
      fieldsEnabled: widget.fieldsEnabled,
    );
    final rows = <({String name, String detail})>[];
    if (target?.kind == BodyCompletionKind.field) {
      final query = target!.query.toLowerCase();
      final entries =
          (widget.dictionary?.state.entries ?? [])
              .where((e) => e.name.toLowerCase().contains(query))
              .toList()
            ..sort((a, b) {
              final prefix = (a.name.toLowerCase().startsWith(query) ? 0 : 1)
                  .compareTo(b.name.toLowerCase().startsWith(query) ? 0 : 1);
              if (prefix != 0) return prefix;
              final frequency = b.usageCount.compareTo(a.usageCount);
              return frequency != 0 ? frequency : a.name.compareTo(b.name);
            });
      rows.addAll(
        entries
            .take(50)
            .map((e) => (name: e.name, detail: '${e.usageCount} uses')),
      );
    } else if (target != null) {
      for (final suggestion in buildVariableSuggestions(
        query: target.query,
        userVariableNames: widget.variableContext.allVariables.keys,
        classify: widget.variableContext.classify,
      ).take(50)) {
        final c = suggestion.classification;
        final preview = c.kind == VariableValueKind.secret
            ? '••••'
            : c.value ?? '';
        rows.add((
          name: suggestion.name,
          detail: '${c.environmentName ?? 'dynamic'} · $preview',
        ));
      }
    }
    setState(() {
      _target = rows.isEmpty ? null : target;
      _suggestions = rows;
      _selected = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _updateCaret();
  }

  void _dismiss() {
    setState(() {
      _target = null;
      _explicit = false;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final completionModifier = useMetaShortcuts
        ? keyboard.isAltPressed && !keyboard.isControlPressed
        : keyboard.isControlPressed && !keyboard.isAltPressed;
    if (event.logicalKey == LogicalKeyboardKey.space &&
        completionModifier &&
        !keyboard.isMetaPressed &&
        !keyboard.isShiftPressed) {
      _showOnRefresh = true;
      _explicit = true;
      _refresh();
      return KeyEventResult.handled;
    }
    if (_target == null ||
        keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _dismiss();
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selected =
            (_selected + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
            _suggestions.length,
      );
      if (_scroll.hasClients) {
        final row = context.appLayout.treeRowExtent;
        final top = _selected * row;
        final bottom = top + row;
        final position = _scroll.position;
        if (top < position.pixels) {
          _scroll.jumpTo(top);
        } else if (bottom > position.pixels + position.viewportDimension) {
          _scroll.jumpTo(
            (bottom - position.viewportDimension).clamp(
              0,
              position.maxScrollExtent,
            ),
          );
        }
      }
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      _accept(_selected);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _accept(int index) {
    final target = _target;
    if (target == null) return;
    final insertion = target.insertion(_suggestions[index].name);
    final start = _positionAt(target.replaceStart);
    final end = _positionAt(target.replaceEnd);
    _dismiss();
    widget.controller.replaceSelection(
      insertion,
      CodeLineSelection(
        baseIndex: start.index,
        baseOffset: start.offset,
        extentIndex: end.index,
        extentOffset: end.offset,
      ),
    );
    _focus.requestFocus();
    _scheduleRefresh(show: false);
  }

  CodeLinePosition _positionAt(int offset) {
    final separator = widget.controller.options.lineBreak.value;
    final before = _text.substring(0, offset).split(separator);
    var position = widget.controller.lineIndex2Index(before.length - 1);
    while (position.chunkIndex != -1) {
      widget.controller.expandChunk(position.index);
      position = widget.controller.lineIndex2Index(before.length - 1);
    }
    return CodeLinePosition(index: position.index, offset: before.last.length);
  }

  Widget _indicatorBuilder(
    BuildContext context,
    CodeLineEditingController controller,
    CodeChunkController chunks,
    CodeIndicatorValueNotifier notifier,
  ) {
    if (_indicator != notifier) {
      _indicator?.removeListener(_queueCaret);
      _indicator = notifier..addListener(_queueCaret);
    }
    return Row(
      key: _gutterKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        DefaultCodeLineNumber(controller: controller, notifier: notifier),
        DefaultCodeChunkIndicator(
          width: context.appLayout.foldGutterWidth,
          controller: chunks,
          notifier: notifier,
        ),
      ],
    );
  }

  void _queueCaret() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _updateCaret();
  });

  void _updateCaret() {
    final stack = _stackKey.currentContext?.findRenderObject();
    final gutter = _gutterKey.currentContext?.findRenderObject();
    if (stack is! RenderBox ||
        gutter is! RenderBox ||
        !stack.hasSize ||
        !gutter.hasSize) {
      return;
    }
    Rect? caret;
    for (final paragraph
        in _indicator?.value?.paragraphs ?? <CodeLineRenderParagraph>[]) {
      if (paragraph.index != widget.controller.selection.extentIndex) continue;
      final offset = paragraph.getOffset(
        TextPosition(offset: widget.controller.selection.extentOffset),
      );
      if (offset != null) {
        final origin = stack.globalToLocal(
          gutter.localToGlobal(Offset(gutter.size.width, 0)),
        );
        final point = origin + paragraph.offset + offset;
        caret = Rect.fromLTWH(
          point.dx,
          point.dy,
          0,
          paragraph.preferredLineHeight,
        );
      }
      break;
    }
    if (_caret != caret) setState(() => _caret = caret);
  }

  @override
  void dispose() {
    final dictionary = widget.dictionary;
    if (_learnedRevision != _revision &&
        dictionary != null &&
        !dictionary.isClosed) {
      unawaited(dictionary.recordUsage(_newOccurrences(_fieldCounts(_text))));
    }
    _learnTimer?.cancel();
    widget.controller.removeListener(_onChanged);
    _indicator?.removeListener(_queueCaret);
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = context.appLayout;
      final width = math.min(layout.sideMenuWidth, constraints.maxWidth);
      final height = math.min(
        layout.quickListMaxHeight,
        math.min(
          _suggestions.length * layout.treeRowExtent,
          constraints.maxHeight,
        ),
      );
      final caret =
          _caret ??
          Rect.fromLTWH(layout.foldGutterWidth, 0, 0, layout.fontSizeCode);
      final top =
          (caret.bottom + height <= constraints.maxHeight
                  ? caret.bottom
                  : caret.top - height)
              .clamp(0.0, math.max(0, constraints.maxHeight - height));
      return Stack(
        key: _stackKey,
        children: [
          Positioned.fill(
            child: JsonCodeEditor(
              controller: widget.controller,
              findController: widget.findController,
              focusNode: _focus,
              indicatorBuilder: _indicatorBuilder,
            ),
          ),
          if (_target != null)
            Positioned(
              top: top.toDouble(),
              left: caret.left.clamp(
                0.0,
                math.max(0, constraints.maxWidth - width),
              ),
              width: width,
              height: height,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: DecoratedBox(
                  decoration: context.appDecoration.panelBox(context),
                  child: ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.zero,
                    itemExtent: layout.treeRowExtent,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) => InkWell(
                      canRequestFocus: false,
                      onTap: () => _accept(index),
                      child: Container(
                        color: index == _selected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        padding: EdgeInsets.symmetric(
                          horizontal: layout.inputPadding,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _suggestions[index].name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: layout.fontSizeNormal,
                                  fontWeight: context.appTypography.titleWeight,
                                ),
                              ),
                            ),
                            SizedBox(width: layout.tabSpacing),
                            Flexible(
                              child: Text(
                                _suggestions[index].detail,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: layout.fontSizeSmall,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
