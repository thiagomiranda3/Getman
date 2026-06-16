import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

/// The selectable preview: folder rows (tristate group checkbox) with their
/// indented request leaves, plus an environment summary and warnings.
class SpecImportPreview extends StatelessWidget {
  const SpecImportPreview({
    required this.result,
    required this.selected,
    required this.onToggleFolder,
    required this.onToggleLeaf,
    super.key,
  });

  final ImportResult result;
  final Set<String> selected;
  final void Function(CollectionNodeEntity folder, {required bool select})
  onToggleFolder;
  final void Function(String id, {required bool select}) onToggleLeaf;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final palette = context.appPalette;
    final typography = context.appTypography;
    final theme = Theme.of(context);

    final environments = result.environments;
    final envLabel = environments.isEmpty
        ? 'Creates no environments.'
        : 'Creates ${environments.length} environment(s): '
              '${environments.map((e) => e.name).join(', ')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in result.root.children) ...[
          if (child.isFolder)
            _FolderRow(
              folder: child,
              selected: selected,
              onToggleFolder: onToggleFolder,
              onToggleLeaf: onToggleLeaf,
            )
          else
            _LeafRow(
              leaf: child,
              selected: selected.contains(child.id),
              onChanged: (value) =>
                  onToggleLeaf(child.id, select: value ?? false),
            ),
        ],
        SizedBox(height: layout.sectionSpacing),
        Text(
          envLabel,
          style: TextStyle(
            fontSize: layout.fontSizeNormal,
            fontWeight: typography.bodyWeight,
            color: theme.colorScheme.onSurface,
          ),
        ),
        for (final warning in result.warnings) ...[
          SizedBox(height: layout.tabSpacing),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: layout.smallIconSize,
                color: palette.statusWarning,
              ),
              SizedBox(width: layout.tabSpacing),
              Expanded(
                child: Text(
                  warning,
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    fontWeight: typography.bodyWeight,
                    color: palette.statusWarning,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.selected,
    required this.onToggleFolder,
    required this.onToggleLeaf,
  });

  final CollectionNodeEntity folder;
  final Set<String> selected;
  final void Function(CollectionNodeEntity folder, {required bool select})
  onToggleFolder;
  final void Function(String id, {required bool select}) onToggleLeaf;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final theme = Theme.of(context);

    final leaves = folder.children.where((c) => !c.isFolder).toList();
    final selectedCount = leaves.where((l) => selected.contains(l.id)).length;
    final value = selectedCount == 0
        ? false
        : (selectedCount == leaves.length ? true : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Checkbox(
              tristate: true,
              value: value,
              onChanged: (_) => onToggleFolder(folder, select: value != true),
            ),
            Expanded(
              child: Text(
                folder.name,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: typography.titleWeight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        for (final leaf in leaves)
          Padding(
            padding: EdgeInsets.only(left: layout.depthPaddingMultiplier),
            child: _LeafRow(
              leaf: leaf,
              selected: selected.contains(leaf.id),
              onChanged: (v) => onToggleLeaf(leaf.id, select: v ?? false),
            ),
          ),
      ],
    );
  }
}

class _LeafRow extends StatelessWidget {
  const _LeafRow({
    required this.leaf,
    required this.selected,
    required this.onChanged,
  });

  final CollectionNodeEntity leaf;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final theme = Theme.of(context);
    final method = leaf.config?.method ?? 'GET';

    return Row(
      children: [
        Checkbox(value: selected, onChanged: onChanged),
        MethodBadge(method: method, small: true),
        SizedBox(width: layout.tabSpacing),
        Expanded(
          child: Text(
            leaf.name,
            style: TextStyle(
              fontSize: layout.fontSizeNormal,
              fontWeight: typography.bodyWeight,
              color: theme.colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Inline error text shown below the source input when parsing fails.
class SpecImportErrorText extends StatelessWidget {
  const SpecImportErrorText({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    return Text(
      message,
      style: TextStyle(
        fontSize: layout.fontSizeSmall,
        fontWeight: context.appTypography.bodyWeight,
        color: theme.colorScheme.error,
      ),
    );
  }
}
