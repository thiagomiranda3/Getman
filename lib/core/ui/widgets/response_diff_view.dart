// Read-only unified response diff view: status/header summary above a
// per-line-colored body diff, driven by a precomputed ResponseDiffModel.
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/line_diff.dart';
import 'package:getman/core/utils/response_diff_builder.dart';

/// Read-only unified diff of the current response (left) vs a chosen target
/// (right). Renders a status/header summary above a per-line-colored body diff.
class ResponseDiffView extends StatelessWidget {
  const ResponseDiffView({
    required this.model,
    required this.leftLabel,
    required this.rightLabel,
    super.key,
  });

  final ResponseDiffModel model;
  final String leftLabel;
  final String rightLabel;

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: const Text('COMPARE RESPONSE'),
      content: SizedBox(
        width: context.appLayout.dialogWidth * 1.6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summary(context),
            SizedBox(height: context.appLayout.sectionSpacing / 2),
            Flexible(child: _body(context)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }

  Widget _summary(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final theme = Theme.of(context);

    final headerCount = model.headerDeltas.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          leftLabel,
          style: TextStyle(
            fontSize: layout.fontSizeNormal,
            fontWeight: typography.titleWeight,
            color: theme.colorScheme.onSurface,
          ),
        ),
        Text(
          rightLabel,
          style: TextStyle(
            fontSize: layout.fontSizeNormal,
            fontWeight: typography.titleWeight,
            color: theme.colorScheme.onSurface,
          ),
        ),
        SizedBox(height: layout.tabSpacing),
        Row(
          children: [
            _statusBadge(context, model.leftStatus),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.tabSpacing),
              child: Icon(Icons.arrow_forward, size: layout.iconSize),
            ),
            _statusBadge(context, model.rightStatus),
          ],
        ),
        SizedBox(height: layout.tabSpacing),
        Text(
          headerCount == 0
              ? 'Headers match'
              : '$headerCount header${headerCount == 1 ? '' : 's'} changed',
          style: TextStyle(
            fontSize: layout.fontSizeSmall,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        if (headerCount > 0)
          Padding(
            padding: EdgeInsets.only(top: layout.tabSpacing / 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in model.headerDeltas) _headerRow(context, d),
              ],
            ),
          ),
      ],
    );
  }

  Widget _statusBadge(BuildContext context, int code) {
    final palette = context.appPalette;
    final layout = context.appLayout;
    final bg = palette.statusAccent(code);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.badgePaddingHorizontal,
        vertical: layout.badgePaddingVertical,
      ),
      color: bg,
      child: Text(
        '$code',
        style: TextStyle(
          fontSize: layout.fontSizeSmall,
          fontWeight: context.appTypography.displayWeight,
          color: palette.onColor(bg),
        ),
      ),
    );
  }

  Widget _headerRow(BuildContext context, HeaderDelta d) {
    final palette = context.appPalette;
    final layout = context.appLayout;
    final color = d.isAdded
        ? palette.diffAddedForeground
        : d.isRemoved
        ? palette.diffRemovedForeground
        : Theme.of(context).colorScheme.onSurface;
    final glyph = d.isAdded
        ? '+'
        : d.isRemoved
        ? '-'
        : '~';
    return Text(
      '$glyph ${d.key}: ${d.right ?? d.left ?? ''}',
      style: TextStyle(
        fontFamily: context.appTypography.codeFontFamily,
        fontSize: layout.fontSizeSmall,
        color: color,
      ),
    );
  }

  Widget _body(BuildContext context) {
    final layout = context.appLayout;
    final palette = context.appPalette;

    if (model.tooLarge) {
      return _note(
        context,
        'Responses too large to diff inline (over 512 KB). '
        'The status and header summary above still apply.',
      );
    }
    if (model.bodiesIdentical) {
      return _note(
        context,
        model.headerDeltas.isEmpty && model.leftStatus == model.rightStatus
            ? 'These responses are identical.'
            : 'Bodies are identical.',
      );
    }

    // Diff bodies can run to thousands of lines (capped at 512 KB by
    // `tooLarge`). Build lazily so only the visible window is constructed —
    // Flutter best practice "be lazy" for lists where most children are
    // offscreen. ListView stretches children cross-axis by default, matching
    // the previous Column's CrossAxisAlignment.stretch.
    return ColoredBox(
      color: palette.codeBackground,
      child: ListView.builder(
        padding: EdgeInsets.all(layout.pagePadding / 2),
        itemCount: model.bodyLines.length,
        itemBuilder: (context, index) => _line(context, model.bodyLines[index]),
      ),
    );
  }

  Widget _line(BuildContext context, DiffLine line) {
    final layout = context.appLayout;
    final palette = context.appPalette;
    final theme = Theme.of(context);

    late final Color fg;
    late final Color bg;
    late final String glyph;
    Key? glyphKey;
    switch (line.kind) {
      case DiffLineKind.added:
        fg = palette.diffAddedForeground;
        bg = palette.diffAddedBackground;
        glyph = '+';
        glyphKey = const ValueKey('diff_gutter_added');
      case DiffLineKind.removed:
        fg = palette.diffRemovedForeground;
        bg = palette.diffRemovedBackground;
        glyph = '-';
        glyphKey = const ValueKey('diff_gutter_removed');
      case DiffLineKind.equal:
        fg = theme.colorScheme.onSurface;
        bg = Colors.transparent;
        glyph = ' ';
    }

    final codeStyle = TextStyle(
      fontFamily: context.appTypography.codeFontFamily,
      fontSize: layout.fontSizeCode,
      color: fg,
    );

    return ColoredBox(
      color: bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(glyph, key: glyphKey, style: codeStyle),
          SizedBox(width: layout.tabSpacing),
          Expanded(child: Text(line.text, style: codeStyle)),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text) {
    return Padding(
      padding: EdgeInsets.all(context.appLayout.pagePadding),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: context.appLayout.fontSizeNormal,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
