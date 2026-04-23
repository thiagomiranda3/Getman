import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/tabs/presentation/widgets/code_find_panel.dart';

class JsonCodeEditor extends StatelessWidget {
  final CodeLineEditingController controller;
  final bool readOnly;

  const JsonCodeEditor({
    super.key,
    required this.controller,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: CodeEditor(
        controller: controller,
        readOnly: readOnly,
        wordWrap: true,
        findBuilder: (context, controller, readOnly) => CodeFindPanel(controller: controller, readOnly: readOnly),
        style: CodeEditorStyle(
          fontSize: context.appLayout.fontSizeCode,
          fontFamily: context.appTypography.codeFontFamily,
          backgroundColor: context.appPalette.codeBackground,
          cursorColor: theme.primaryColor,
          selectionColor: theme.primaryColor.withValues(alpha: 0.3),
          cursorLineColor: theme.primaryColor.withValues(alpha: readOnly ? 0.2 : 0.1),
          codeTheme: CodeHighlightTheme(
            languages: {
              'json': CodeHighlightThemeMode(mode: langJson),
            },
            theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
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
