// JSON-highlighting code editor: wraps re_editor's CodeEditor with the
// synchronous per-line jsonHighlightSpanBuilder highlighter, app-shortcut
// pass-through, and a find panel. createJsonCodeController() is the required
// way to build controllers fed to this widget so highlighting (and optional
// {{var}} recoloring via variableAwareJsonSpan) is wired up.
//
// Gotchas: colors come ONLY from jsonHighlightSpanBuilder via the
// controller's spanBuilder — never set CodeEditorStyle.codeTheme, re_editor's
// isolate highlighter never delivers colored results here and it silently
// reverts to single-colour. AppCodeShortcutsActivatorsBuilder strips the
// `save` activator (so the app's own Cmd/Ctrl+S fires) and the Cmd/Ctrl+Enter
// chord from `newLine` (so SendRequestIntent fires) while this editor has
// focus. The editor is keyed by GlobalObjectKey(controller) so a theme
// switch toggling the glass frost wrapper reparents the element instead of
// disposing/remounting it (remounting while the old element is still
// subscribed crashes re_editor).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/tabs/presentation/widgets/code_find_panel.dart';
import 'package:getman/features/tabs/presentation/widgets/variable_json_span_builder.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

/// Adapts re_editor's default shortcut map so two chords the editor would
/// otherwise *consume* bubble up to the app's global shortcuts instead:
///
/// * **Cmd/Ctrl+S** — re_editor binds it to a no-op `save` action and swallows
///   the key, so the app's own `SaveRequestIntent` never fired (on macOS Cmd+S
///   did nothing; only the leaked Ctrl+S saved). We drop the `save` activator
///   entirely.
/// * **Cmd/Ctrl+Enter** — re_editor lists it under `newLine`, so while the body
///   editor held focus the app's `SendRequestIntent` never fired (the chord
///   just inserted a newline). We strip that one activator from `newLine` while
///   keeping plain Enter / Shift+Enter / numpad-Enter for normal newlines.
@visibleForTesting
class AppCodeShortcutsActivatorsBuilder extends CodeShortcutsActivatorsBuilder {
  const AppCodeShortcutsActivatorsBuilder();

  static const _defaults = DefaultCodeShortcutsActivatorsBuilder();

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    if (type == CodeShortcutType.save) return null;
    final activators = _defaults.build(type);
    if (type == CodeShortcutType.newLine && activators != null) {
      return activators.where((a) => !_isSendRequestChord(a)).toList();
    }
    return activators;
  }

  /// The app binds Cmd+Enter (macOS) / Ctrl+Enter (elsewhere) to sending the
  /// request. Matches exactly that chord so it is removed from `newLine`;
  /// Shift/Alt or numpad-Enter variants are left alone.
  static bool _isSendRequestChord(ShortcutActivator activator) {
    if (activator is! SingleActivator) return false;
    if (activator.trigger != LogicalKeyboardKey.enter) return false;
    if (activator.shift || activator.alt) return false;
    return activator.meta || activator.control;
  }
}

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
///
/// When [variablesProvider], [resolvedColor], and [unresolvedColor] are all
/// supplied, the span builder additionally recolors `{{var}}` tokens on top of
/// the JSON highlighting (resolved vs. unresolved). The providers are read at
/// span-build time — call [CodeLineEditingController.forceRepaint] after an
/// env/theme change to recolor without a text edit. When any provider is
/// omitted (e.g. the response viewer), the behavior is plain JSON highlighting.
CodeLineEditingController createJsonCodeController({
  Map<String, String> Function()? variablesProvider,
  Color Function()? resolvedColor,
  Color Function()? unresolvedColor,
}) {
  if (variablesProvider == null ||
      resolvedColor == null ||
      unresolvedColor == null) {
    return CodeLineEditingController(spanBuilder: jsonHighlightSpanBuilder);
  }
  return CodeLineEditingController(
    spanBuilder:
        ({
          required context,
          required index,
          required codeLine,
          required textSpan,
          required style,
        }) => variableAwareJsonSpan(
          context: context,
          index: index,
          codeLine: codeLine,
          textSpan: textSpan,
          style: style,
          variables: variablesProvider(),
          resolvedColor: resolvedColor(),
          unresolvedColor: unresolvedColor(),
        ),
  );
}

class JsonCodeEditor extends StatelessWidget {
  const JsonCodeEditor({
    required this.controller,
    super.key,
    this.readOnly = false,
    this.wordWrap = true,
    this.autofocus = true,
    this.findController,
  });
  final CodeLineEditingController controller;
  final bool readOnly;
  final bool wordWrap;
  final bool autofocus;

  /// Externally-owned find controller. Pass one when the host widget needs to
  /// observe find-mode state (e.g. the body editor's Beautify overlay moves
  /// below the open find panel). Null lets [CodeEditor] create and own its
  /// internal one — behavior is unchanged. The caller keeps ownership: it must
  /// dispose the controller itself (re_editor only disposes internal ones).
  final CodeFindController? findController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: CodeEditor(
        // A stable global key tied to the (retained) controller. When a theme
        // switch toggles the glass `frost` wrapper around this editor, the
        // element type at the panel slot changes, which would otherwise tear
        // down and remount this CodeEditor. Because the controller outlives the
        // rebuild, the remounted editor's initState notifies it while the
        // just-deactivated old editor is still subscribed, and re_editor then
        // touches a deactivated element (unsafe ancestor / renderObject lookup)
        // -> crash. Keying by the controller makes Flutter REPARENT the single
        // editor element instead, preserving its state across the toggle.
        key: GlobalObjectKey(controller),
        controller: controller,
        findController: findController,
        readOnly: readOnly,
        wordWrap: wordWrap,
        autofocus: autofocus,
        // Let the app's global Cmd/Ctrl+S (save) and Cmd/Ctrl+Enter (send)
        // shortcuts fire even while this editor has focus
        // (see [AppCodeShortcutsActivatorsBuilder]).
        shortcutsActivatorsBuilder: const AppCodeShortcutsActivatorsBuilder(),
        findBuilder: (context, controller, readOnly) =>
            CodeFindPanel(controller: controller, readOnly: readOnly),
        // Token colours come from [jsonHighlightSpanBuilder] on the controller,
        // not from a `codeTheme` here — re_editor's isolate highlighter does
        // not deliver coloured results in this app.
        style: CodeEditorStyle(
          fontSize: context.appLayout.fontSizeCode,
          fontFamily: context.appTypography.codeFontFamily,
          backgroundColor: context.appPalette.codeBackground,
          // Use the colorScheme accent, not the legacy `primaryColor`: in a
          // dark theme that never sets `primaryColor` explicitly (the AURIS
          // kit) it defaults to a dark surface, so the cursor vanishes against
          // the dark code background. `colorScheme.primary` is the real brand
          // accent and equals `primaryColor` in every other theme.
          cursorColor: theme.colorScheme.primary,
          selectionColor: theme.colorScheme.primary.withValues(alpha: 0.3),
          cursorLineColor: theme.colorScheme.primary.withValues(
            alpha: readOnly ? 0.2 : 0.1,
          ),
        ),
        indicatorBuilder: (context, controller, chunkController, notifier) {
          // Line numbers + JSON fold markers. re_editor's
          // DefaultCodeChunkAnalyzer (on by default) detects {}/[] regions; the
          // chunk indicator paints the collapse/expand chevrons in the gutter
          // and toggles them on tap.
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DefaultCodeLineNumber(
                controller: controller,
                notifier: notifier,
              ),
              DefaultCodeChunkIndicator(
                width: context.appLayout.foldGutterWidth,
                controller: chunkController,
                notifier: notifier,
              ),
            ],
          );
        },
      ),
    );
  }
}
