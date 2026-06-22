import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/core/utils/variable_autocomplete_query.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';
import 'package:getman/core/utils/variable_suggestions.dart';
import 'package:re_editor/re_editor.dart';

/// Pure detection: the active `{{` query at [caret] in [line] and its ranked
/// suggestions, or null when the caret is not inside an open `{{name` token.
({String input, bool hasClosingBraces, List<VariableSuggestion> suggestions})?
variablePromptsFor(LayeredVariableContext ctx, String line, int caret) {
  final query = detectActiveVariableQuery(line, caret);
  if (query == null) return null;
  final suggestions = buildVariableSuggestions(
    query: query.query,
    userVariableNames: ctx.allVariables.keys,
    classify: ctx.classify,
  );
  if (suggestions.isEmpty) return null;
  return (
    input: query.query,
    hasClosingBraces: query.hasClosingBraces,
    suggestions: suggestions,
  );
}

/// The text to insert for an accepted [name]: the bare name when a closing
/// `}}` already follows the caret, otherwise the name plus `}}`.
String variableInsertionWord(String name, {required bool hasClosingBraces}) =>
    hasClosingBraces ? name : '$name}}';

/// A single variable suggestion as a re_editor [CodePrompt]. Carries the
/// resolved closing-brace decision so `.autocomplete` inserts `name` or
/// `name}}` correctly.
class _VariableCodePrompt extends CodePrompt {
  const _VariableCodePrompt({
    required super.word, // the variable name (display + match key)
    required this.hasClosingBraces,
    required this.classification,
  });

  final bool hasClosingBraces;
  final ResolvedVariable classification;

  @override
  bool match(String input) => word.toLowerCase().contains(input.toLowerCase());

  @override
  CodeAutocompleteResult get autocomplete {
    final insert = variableInsertionWord(
      word,
      hasClosingBraces: hasClosingBraces,
    );
    // The editing value carries the typed query as its `input`; the editor
    // deletes `[caret - input.length, caret]` (the typed query, after `{{`)
    // and inserts `word`, leaving the `{{` and landing the caret after the
    // insert. So this prompt's own `input` is empty.
    return CodeAutocompleteResult(
      input: '',
      word: insert,
      selection: TextSelection.collapsed(offset: insert.length),
    );
  }
}

/// re_editor prompts builder backed by the live [LayeredVariableContext].
class VariablePromptsBuilder implements CodeAutocompletePromptsBuilder {
  VariablePromptsBuilder(this.contextProvider);

  final LayeredVariableContext Function() contextProvider;

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    if (!selection.isCollapsed) return null;
    final found = variablePromptsFor(
      contextProvider(),
      codeLine.text,
      selection.extentOffset,
    );
    if (found == null) return null;
    return CodeAutocompleteEditingValue(
      input: found.input,
      prompts: [
        for (final s in found.suggestions)
          _VariableCodePrompt(
            word: s.name,
            hasClosingBraces: found.hasClosingBraces,
            classification: s.classification,
          ),
      ],
      index: 0,
    );
  }
}

/// Themed suggestion list for the body editor — mirrors the rows used by the
/// TextField overlay (name + source + resolved preview).
CodeAutocompleteWidgetBuilder get variableAutocompleteViewBuilder => _buildView;

PreferredSizeWidget _buildView(
  BuildContext context,
  ValueNotifier<CodeAutocompleteEditingValue> notifier,
  ValueChanged<CodeAutocompleteResult> onSelected,
) => _VariableCodeAutocompleteList(notifier: notifier, onSelected: onSelected);

const double _kRowHeight = 32;
const double _kMenuWidth = 280;
const double _kMaxMenuHeight = 240;

class _VariableCodeAutocompleteList extends StatelessWidget
    implements PreferredSizeWidget {
  const _VariableCodeAutocompleteList({
    required this.notifier,
    required this.onSelected,
  });

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  @override
  Size get preferredSize => Size(
    _kMenuWidth,
    math.min(_kRowHeight * notifier.value.prompts.length, _kMaxMenuHeight),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CodeAutocompleteEditingValue>(
      valueListenable: notifier,
      builder: (context, value, _) {
        final palette = context.appPalette;
        final layout = context.appLayout;
        final theme = Theme.of(context);
        return Container(
          width: _kMenuWidth,
          constraints: const BoxConstraints(maxHeight: _kMaxMenuHeight),
          decoration: context.appDecoration.panelBox(context),
          clipBehavior: Clip.antiAlias,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: value.prompts.length,
            itemBuilder: (context, i) {
              final prompt = value.prompts[i] as _VariableCodePrompt;
              final c = prompt.classification;
              final isSecret = c.kind == VariableValueKind.secret;
              final isDynamic = c.kind == VariableValueKind.dynamicValue;
              final preview = isSecret ? '••••' : (c.value ?? '');
              final source = isDynamic ? 'dynamic' : (c.environmentName ?? '');
              final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
              return InkWell(
                onTap: () => onSelected(value.copyWith(index: i).autocomplete),
                child: Container(
                  height: _kRowHeight,
                  color: i == value.index
                      ? theme.colorScheme.primary.withValues(alpha: 0.12)
                      : null,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          prompt.word,
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
                          style: TextStyle(
                            fontSize: layout.fontSizeNormal,
                            color: muted,
                          ),
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
                              fontStyle: isDynamic
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Wraps a body [child] (a `CodeEditor`) with variable autocomplete. Always
/// wraps: dynamic built-ins ({{$guid}}, {{$timestamp}}…) are suggestable even
/// with no active environment, matching the URL bar. The `promptsBuilder`
/// returns null (no overlay) when the caret isn't inside a `{{` token, so an
/// empty context simply yields the dynamics for a matching query.
Widget wrapBodyWithVariableAutocomplete({
  required LayeredVariableContext Function() contextProvider,
  required Widget child,
}) {
  return CodeAutocomplete(
    viewBuilder: variableAutocompleteViewBuilder,
    promptsBuilder: VariablePromptsBuilder(contextProvider),
    child: child,
  );
}
