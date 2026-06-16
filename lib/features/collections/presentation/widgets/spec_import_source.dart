import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Where the spec text comes from: a picked file, a pasted string, or a remote
/// URL fetched via the network service.
enum SpecImportSource { file, paste, url }

/// The FILE / PASTE / URL segmented control.
class SpecImportSourceSelector extends StatelessWidget {
  const SpecImportSourceSelector({
    required this.source,
    required this.onChanged,
    super.key,
  });

  final SpecImportSource source;
  final ValueChanged<SpecImportSource> onChanged;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Row(
      children: [
        for (final entry in const {
          SpecImportSource.file: 'FILE',
          SpecImportSource.paste: 'PASTE',
          SpecImportSource.url: 'URL',
        }.entries) ...[
          if (entry.key != SpecImportSource.file)
            SizedBox(width: layout.tabSpacing),
          Expanded(
            child: _SourceButton(
              label: entry.value,
              selected: source == entry.key,
              onTap: () => onChanged(entry.key),
            ),
          ),
        ],
      ],
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return context.appDecoration.wrapInteractive(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: layout.buttonPaddingVertical),
        decoration: BoxDecoration(
          color: selected ? theme.primaryColor : theme.colorScheme.surface,
          border: Border.all(
            color: theme.dividerColor,
            width: layout.borderThick,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            fontWeight: context.appTypography.displayWeight,
            fontSize: layout.fontSizeNormal,
          ),
        ),
      ),
    );
  }
}
