import 'package:flutter/material.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/byte_format.dart';

/// Banner shown at the top of the large-response view (bodies over
/// [kLargeResponseViewerChars]).
///
/// Renders the size label, opt-in controls ("PRETTIFY ANYWAY" / "SHOW FULL"),
/// and the action-button cluster ([controls]).  The scrollable body content
/// below the banner is owned by the caller so the editor widget stays at a
/// consistent tree position across mode switches (preserving re_editor state).
class ResponseLargeBodyView extends StatelessWidget {
  const ResponseLargeBodyView({
    required this.body,
    required this.showFullPreview,
    required this.highlightingOptedIn,
    required this.onPrettifyAndOptIn,
    required this.onShowFull,
    required this.controls,
    super.key,
  });

  /// The full body string.
  final String body;

  /// Whether the full plain-text body is visible (vs the 256 KiB preview).
  final bool showFullPreview;

  /// Whether the user has opted into syntax-highlighting (editor mode).
  final bool highlightingOptedIn;

  /// Called when "PRETTIFY ANYWAY" is pressed.
  final VoidCallback onPrettifyAndOptIn;

  /// Called when "SHOW FULL" is pressed.
  final VoidCallback onShowFull;

  /// The action-button cluster (copy / save / compare / save-as-example).
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final theme = Theme.of(context);
    final sizeLabel = formatBytes(body.length);

    final isTruncated =
        !showFullPreview && body.length > kLargeResponsePreviewChars;

    return ColoredBox(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: layout.pagePadding,
          vertical: layout.pagePadding / 2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                highlightingOptedIn
                    ? 'LARGE RESPONSE ($sizeLabel) — HIGHLIGHTING ENABLED'
                    : 'LARGE RESPONSE ($sizeLabel) — HIGHLIGHTING DISABLED',
                style: TextStyle(
                  fontSize: layout.fontSizeSmall,
                  fontWeight: typography.titleWeight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (!highlightingOptedIn) ...[
              TextButton(
                onPressed: onPrettifyAndOptIn,
                child: Text(
                  'PRETTIFY ANYWAY',
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    fontWeight: typography.titleWeight,
                  ),
                ),
              ),
              if (isTruncated)
                TextButton(
                  onPressed: onShowFull,
                  child: Text(
                    'SHOW FULL',
                    style: TextStyle(
                      fontSize: layout.fontSizeSmall,
                      fontWeight: typography.titleWeight,
                    ),
                  ),
                ),
            ],
            controls,
          ],
        ),
      ),
    );
  }
}
