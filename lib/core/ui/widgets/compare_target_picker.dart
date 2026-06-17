import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';

/// Where a compare target came from.
enum CompareTargetSource { example, history, timeline }

/// A selectable response to diff the current tab against. Carries the
/// reconstructed [response] so the caller does no rebuild work after a pick.
class CompareTarget extends Equatable {
  const CompareTarget({
    required this.id,
    required this.source,
    required this.label,
    required this.subtitle,
    required this.response,
  });

  final String id;
  final CompareTargetSource source;
  final String label;
  final String subtitle;
  final HttpResponseEntity response;

  @override
  List<Object?> get props => [id, source, label, subtitle, response];
}

/// Lists saved-example and matching-history targets in two labeled sections.
/// A pure presentational atom — passed its data, never reads blocs. Pops the
/// chosen [CompareTarget] (or null on cancel) via the dialog Navigator.
class CompareTargetPicker extends StatelessWidget {
  const CompareTargetPicker({
    required this.examples,
    required this.history,
    this.timeline = const [],
    super.key,
  });

  final List<CompareTarget> examples;
  final List<CompareTarget> history;

  /// Earlier responses from this tab's time-travel history.
  final List<CompareTarget> timeline;

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: const Text('COMPARE WITH'),
      content: SizedBox(
        width: context.appLayout.dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (timeline.isNotEmpty) ...[
              _section(context, 'PREVIOUS RESPONSES (this tab)', timeline),
              SizedBox(height: context.appLayout.sectionSpacing / 2),
            ],
            _section(context, 'SAVED EXAMPLES', examples),
            SizedBox(height: context.appLayout.sectionSpacing / 2),
            _section(context, 'RECENT (this request)', history),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('CANCEL'),
        ),
      ],
    );
  }

  Widget _section(
    BuildContext context,
    String heading,
    List<CompareTarget> targets,
  ) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          heading,
          style: TextStyle(
            fontSize: layout.fontSizeSmall,
            fontWeight: context.appTypography.displayWeight,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        SizedBox(height: layout.tabSpacing),
        if (targets.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: layout.tabSpacing),
            child: Text(
              'None',
              style: TextStyle(
                fontSize: layout.fontSizeNormal,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          )
        else
          for (final t in targets) _row(context, t),
      ],
    );
  }

  Widget _row(BuildContext context, CompareTarget target) {
    final layout = context.appLayout;
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final bg = palette.statusAccent(target.response.statusCode);

    return context.appDecoration.wrapInteractive(
      onTap: () => Navigator.of(context).pop(target),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: layout.tabSpacing / 2),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: layout.badgePaddingHorizontal,
                vertical: layout.badgePaddingVertical,
              ),
              color: bg,
              child: Text(
                '${target.response.statusCode}',
                style: TextStyle(
                  fontSize: layout.fontSizeSmall,
                  fontWeight: context.appTypography.displayWeight,
                  color: palette.onColor(bg),
                ),
              ),
            ),
            SizedBox(width: layout.tabSpacing),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.label,
                    style: TextStyle(
                      fontSize: layout.fontSizeNormal,
                      fontWeight: context.appTypography.titleWeight,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    target.subtitle,
                    style: TextStyle(
                      fontSize: layout.fontSizeSmall,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
