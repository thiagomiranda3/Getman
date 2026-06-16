import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/variable_resolution_helper.dart';

/// Active-environment data passed into a value field (or the URL bar) to enable
/// `{{var}}` highlighting + hover resolution. Null disables the feature.
class VariableHoverContext extends Equatable {
  const VariableHoverContext({
    this.variables = const {},
    this.secretKeys = const {},
    this.environmentName,
  });

  final Map<String, String> variables;

  /// Names flagged secret in the active environment — masked in the popover.
  final Set<String> secretKeys;

  /// Active environment display name; null when no environment is active.
  final String? environmentName;

  @override
  List<Object?> get props => [variables, secretKeys, environmentName];
}

/// The hover card. Not a stock Tooltip — secrets need an interactive reveal
/// toggle and the card must stay open while the pointer is over it.
class VariableHoverPopover extends StatefulWidget {
  const VariableHoverPopover({required this.data, super.key});

  final ResolvedVariable data;

  @override
  State<VariableHoverPopover> createState() => _VariableHoverPopoverState();
}

class _VariableHoverPopoverState extends State<VariableHoverPopover> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appPalette;
    final layout = context.appLayout;
    final typography = context.appTypography;
    final data = widget.data;

    final nameStyle = TextStyle(
      fontFamily: typography.codeFontFamily,
      fontSize: layout.fontSizeNormal,
      fontWeight: typography.titleWeight,
      color: theme.colorScheme.onSurface,
    );
    final valueStyle = TextStyle(
      fontFamily: typography.codeFontFamily,
      fontSize: layout.fontSizeNormal,
      color: palette.variableResolved,
    );
    final sourceStyle = TextStyle(
      fontSize: layout.fontSizeSmall,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );

    return Material(
      type: MaterialType.transparency,
      child: context.appDecoration.frost(
        context,
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: EdgeInsets.all(layout.isCompact ? 8 : 12),
          decoration: context.appDecoration.panelBox(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('{{${data.name}}}', style: nameStyle),
              SizedBox(height: layout.tabSpacing),
              ..._body(
                context,
                valueStyle: valueStyle,
                sourceStyle: sourceStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context, {
    required TextStyle valueStyle,
    required TextStyle sourceStyle,
  }) {
    final data = widget.data;
    switch (data.kind) {
      case VariableValueKind.resolved:
        return [
          SelectableText(data.value ?? '', style: valueStyle),
          if (data.environmentName != null) ...[
            SizedBox(height: context.appLayout.tabSpacing),
            Text('from ${data.environmentName}', style: sourceStyle),
          ],
        ];
      case VariableValueKind.secret:
        return [
          Row(
            children: [
              Flexible(
                child: _revealed
                    ? SelectableText(data.value ?? '', style: valueStyle)
                    : Text('•••••• (secret)', style: valueStyle),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _revealed ? Icons.visibility_off : Icons.visibility,
                  size: context.appLayout.isCompact ? 18 : 20,
                ),
                tooltip: _revealed ? 'Hide value' : 'Reveal value',
                onPressed: () => setState(() => _revealed = !_revealed),
              ),
            ],
          ),
          if (data.environmentName != null) ...[
            SizedBox(height: context.appLayout.tabSpacing),
            Text('from ${data.environmentName}', style: sourceStyle),
          ],
        ];
      case VariableValueKind.dynamicValue:
        return [
          Text('Generated per request', style: sourceStyle),
          SizedBox(height: context.appLayout.tabSpacing),
          SelectableText(data.value ?? '', style: valueStyle),
        ];
      case VariableValueKind.unresolved:
        return [
          Text(
            data.environmentName == null
                ? 'No active environment'
                : 'Not defined in ${data.environmentName}',
            style: TextStyle(
              fontSize: context.appLayout.fontSizeSmall,
              color: context.appPalette.variableUnresolved,
            ),
          ),
        ];
    }
  }
}

/// Owns a single OverlayEntry for the hover popover. The owning State creates
/// one, drives it from the highlight controller's hover sink, and disposes it.
/// A short hide delay lets the pointer travel from the token into the card.
class VariableHoverController {
  OverlayEntry? _entry;
  Timer? _hideTimer;

  /// Shows (or re-anchors) the popover near [globalAnchor] (the pointer).
  void showFor(
    BuildContext context,
    ResolvedVariable data,
    Offset globalAnchor,
  ) {
    _hideTimer?.cancel();
    final overlay = Overlay.of(context);
    final box = overlay.context.findRenderObject() as RenderBox?;
    final overlaySize = box?.size ?? MediaQuery.sizeOf(context);
    final local = box?.globalToLocal(globalAnchor) ?? globalAnchor;
    // Keep the 320-wide card + 4px gutter on-screen at the right edge.
    final maxLeft = (overlaySize.width - 324).clamp(0.0, double.infinity);
    final left = local.dx.clamp(0.0, maxLeft);
    final top = local.dy + 18;

    _entry?.remove();
    _entry?.dispose();
    _entry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: left,
        top: top,
        child: MouseRegion(
          onEnter: (_) => cancelHide(),
          onExit: (_) => scheduleHide(),
          child: VariableHoverPopover(data: data),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  /// Cancels any pending hide timer (e.g. when pointer re-enters the card).
  void cancelHide() => _hideTimer?.cancel();

  /// Schedules a hide after a short delay so the pointer can travel into the
  /// card without it disappearing.
  void scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 120), hideNow);
  }

  /// Immediately removes the popover from the overlay.
  void hideNow() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  /// Disposes the controller and removes any visible popover.
  void dispose() => hideNow();
}
