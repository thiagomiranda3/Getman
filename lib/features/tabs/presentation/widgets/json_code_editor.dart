import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/tabs/presentation/widgets/code_find_panel.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

/// Shared highlighter — `langJson` is registered once and reused for every
/// line. The engine is pure (no mutable per-call state) so a single instance
/// is safe to share across editors.
final Highlight _jsonHighlight = Highlight()
  ..registerLanguage('json', langJson);

/// Synchronous, per-line JSON syntax highlighter used as a controller's
/// [CodeLineSpanBuilder].
///
/// re_editor's built-in highlighting runs in a background isolate
/// (`isolate_manager`) whose results never reach the paint path in this app —
/// every token fell back to the base text colour ("single colour"). We colour
/// each visible line on the UI thread instead: it is viewport-bound (re_editor
/// only builds spans for on-screen lines) and cheap. Pretty-printed JSON keeps
/// every token on a single line (JSON strings cannot contain raw newlines), so
/// per-line parsing is accurate; non-JSON or partial lines degrade gracefully
/// to the base colour.
TextSpan jsonHighlightSpanBuilder({
  required BuildContext context,
  required int index,
  required CodeLine codeLine,
  required TextSpan textSpan,
  required TextStyle style,
}) {
  final text = codeLine.text;
  if (text.isEmpty) return textSpan;

  final tokenTheme = Theme.of(context).brightness == Brightness.dark
      ? atomOneDarkTheme
      : atomOneLightTheme;
  final renderer = TextSpanRenderer(style, tokenTheme);
  try {
    _jsonHighlight.highlight(code: text, language: 'json').render(renderer);
  } on Object catch (_) {
    // `langJson` declares `illegal: \S`, so a non-JSON line throws — fall back
    // to the editor's base (unhighlighted) span rather than dropping the text.
    return textSpan;
  }
  return renderer.span ?? textSpan;
}

/// Creates a [CodeLineEditingController] pre-wired with JSON syntax
/// highlighting. Use this (not the bare constructor) for any controller fed to
/// a [JsonCodeEditor] so highlighting works without an extra setup step.
CodeLineEditingController createJsonCodeController() =>
    CodeLineEditingController(spanBuilder: jsonHighlightSpanBuilder);

class JsonCodeEditor extends StatelessWidget {
  const JsonCodeEditor({
    required this.controller,
    super.key,
    this.readOnly = false,
    this.wordWrap = true,
    this.autofocus = true,
  });
  final CodeLineEditingController controller;
  final bool readOnly;
  final bool wordWrap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: CodeEditor(
        controller: controller,
        readOnly: readOnly,
        wordWrap: wordWrap,
        autofocus: autofocus,
        findBuilder: (context, controller, readOnly) =>
            CodeFindPanel(controller: controller, readOnly: readOnly),
        // Token colours come from [jsonHighlightSpanBuilder] on the controller,
        // not from a `codeTheme` here — re_editor's isolate highlighter does
        // not deliver coloured results in this app.
        style: CodeEditorStyle(
          fontSize: context.appLayout.fontSizeCode,
          fontFamily: context.appTypography.codeFontFamily,
          backgroundColor: context.appPalette.codeBackground,
          cursorColor: theme.primaryColor,
          selectionColor: theme.primaryColor.withValues(alpha: 0.3),
          cursorLineColor: theme.primaryColor.withValues(
            alpha: readOnly ? 0.2 : 0.1,
          ),
        ),
        indicatorBuilder: (context, controller, chunkController, notifier) {
          return DefaultCodeLineNumber(
            controller: controller,
            notifier: notifier,
          );
        },
      ),
    );
  }
}
