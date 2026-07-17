// Read-only render of a SemanticDiff: one block per changed field, with
// multi-line scalar values (e.g. body) shown as a per-line add/remove diff.
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/line_diff.dart';
import 'package:getman/features/collections/domain/logic/semantic_diff.dart';

/// Read-only render of a [SemanticDiff]: one block per changed field.
/// Multi-line scalar values (e.g. body) render as a per-line add/remove diff.
class SemanticDiffView extends StatelessWidget {
  const SemanticDiffView({required this.diff, super.key});
  final SemanticDiff diff;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typo = context.appTypography;
    if (diff.isEmpty) {
      return Center(
        child: Text(
          'No field-level changes',
          style: TextStyle(fontWeight: typo.bodyWeight),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.all(layout.inputPadding),
      itemCount: diff.changes.length,
      separatorBuilder: (_, _) => SizedBox(height: layout.inputPadding),
      itemBuilder: (context, i) => _FieldBlock(change: diff.changes[i]),
    );
  }
}

class _FieldBlock extends StatelessWidget {
  const _FieldBlock({required this.change});
  final FieldChange change;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final typo = context.appTypography;
    final theme = Theme.of(context);
    final addColor = palette.variableResolved;
    final removeColor = palette.variableUnresolved;

    final label = switch (change.kind) {
      ChangeKind.added => '+ ${change.field}',
      ChangeKind.removed => '- ${change.field}',
      ChangeKind.changed => '~ ${change.field}',
    };
    final labelColor = switch (change.kind) {
      ChangeKind.added => addColor,
      ChangeKind.removed => removeColor,
      ChangeKind.changed => theme.colorScheme.onSurface,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(fontWeight: typo.titleWeight, color: labelColor),
        ),
        if (change.before != null || change.after != null) ...[
          const SizedBox(height: 4),
          ..._lineDiff(context, change.before ?? '', change.after ?? ''),
        ],
      ],
    );
  }

  List<Widget> _lineDiff(BuildContext context, String before, String after) {
    final palette = context.appPalette;
    final typo = context.appTypography;
    final theme = Theme.of(context);
    return LineDiff.diffText(before, after).map((line) {
      final (prefix, color) = switch (line.kind) {
        DiffLineKind.added => ('+ ', palette.variableResolved),
        DiffLineKind.removed => ('- ', palette.variableUnresolved),
        DiffLineKind.equal => ('  ', theme.colorScheme.onSurface),
      };
      return Text(
        '$prefix${line.text}',
        style: TextStyle(fontFamily: typo.codeFontFamily, color: color),
      );
    }).toList();
  }
}
