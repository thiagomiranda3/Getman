import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/features/tabs/domain/entities/panel_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/panel_close_coordinator.dart';
import 'package:getman/features/tabs/presentation/widgets/tab_drag_data.dart';

/// Max width of the active-panel label in the tab strip before it ellipsizes.
/// Mirrors the environment selector's 120 cap so the two selectors line up; the
/// compact (phone) variant shrinks it further.
const double _labelMaxWidth = 120;
const double _labelMaxWidthCompact = 64;

/// Width of the drop-down overlay panel list. Wide enough for a panel name +
/// tab-count chip + the rename/close affordances.
const double _menuWidth = 260;

/// Gap between the selector button and the overlay it spawns.
const double _menuGap = 4;

/// The tab-strip dropdown that switches between virtual-desktop panels. Shows
/// the active panel's name (compact icon + short name on phone) and opens a
/// reorderable list of every panel with per-row rename / close affordances plus
/// an "add panel" footer. Double-tapping the button renames the active panel.
///
/// The overlay hosts a [ReorderableListView] for drag-reorder, which a
/// [PopupMenuButton]/`showMenu` can't host — so the list is rendered in a
/// manually-managed [OverlayEntry] (same pattern as the tab hover tooltip).
class PanelSelector extends StatefulWidget {
  const PanelSelector({super.key});

  @override
  State<PanelSelector> createState() => _PanelSelectorState();
}

class _PanelSelectorState extends State<PanelSelector> {
  OverlayEntry? _menuEntry;

  /// Timestamp of the last tap, used to detect a double-tap manually. We can't
  /// use `GestureDetector.onDoubleTap` alongside `onTap` because that defers
  /// the single-tap (the menu wouldn't open until the double-tap timeout), and
  /// the deferred tap never resolves under widget-test `pumpAndSettle`.
  DateTime? _lastTapAt;

  /// The button's global-coordinate rect, captured when the menu opens. Once
  /// the menu is open its full-screen dismiss barrier physically covers the
  /// button, so a genuine second tap of a double-tap lands on the barrier, not
  /// the button's own `GestureDetector` — this rect lets the barrier's tap
  /// handler recognize that case (D1).
  Rect? _buttonRect;

  @override
  void dispose() {
    _removeMenu();
    super.dispose();
  }

  /// Single tap toggles the menu; a second tap within [kDoubleTapTimeout]
  /// reinterprets the gesture as a double-tap and renames the active panel.
  ///
  /// This only fires when BOTH taps land on the button itself (e.g. no
  /// overlay barrier has been laid out yet to intercept the second one) — the
  /// common case, where the menu's barrier already covers the button, is
  /// handled by [_handleBarrierTapUp] instead.
  void _handleTap(BuildContext context, PanelEntity active) {
    final now = DateTime.now();
    final last = _lastTapAt;
    if (last != null && now.difference(last) < kDoubleTapTimeout) {
      _lastTapAt = null;
      // The first tap already opened the menu — close it before renaming.
      _removeMenu();
      _renameActivePanel(context, active);
      return;
    }
    _lastTapAt = now;
    _toggleMenu(context);
  }

  /// The menu's full-screen dismiss barrier receives every tap once the menu
  /// is open — including the second tap of a real double-tap on the button,
  /// which the barrier now physically covers. Reinterpret it as a double-tap
  /// (dismiss + rename) when it lands inside [_buttonRect] within
  /// [kDoubleTapTimeout] of the tap that opened the menu; otherwise this is a
  /// plain dismiss. Either way [_lastTapAt] is cleared so a later single tap
  /// on the button is never mistaken for the second half of this gesture (a
  /// fast triple-tap must not open rename).
  void _handleBarrierTapUp(Offset globalPosition) {
    if (!mounted) return;
    final last = _lastTapAt;
    final rect = _buttonRect;
    final isDoubleTapOnButton =
        last != null &&
        rect != null &&
        DateTime.now().difference(last) < kDoubleTapTimeout &&
        rect.contains(globalPosition);
    final bloc = context.read<TabsBloc>();
    final active = bloc.state.activePanel;
    _removeMenu();
    _lastTapAt = null;
    if (isDoubleTapOnButton && active != null) {
      _renameActivePanel(context, active);
    }
  }

  void _removeMenu() {
    _menuEntry?.remove();
    _menuEntry?.dispose();
    _menuEntry = null;
    _buttonRect = null;
  }

  void _toggleMenu(BuildContext context) {
    if (_menuEntry != null) {
      _removeMenu();
      return;
    }
    _openMenu(context);
  }

  void _openMenu(BuildContext context, {String? droppedTabId}) {
    // Guard against an already-open menu: overwriting `_menuEntry` without
    // removing the old one would orphan its opaque barrier — a permanent
    // input soft-lock (D2).
    _removeMenu();
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final buttonBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null || buttonBox == null) return;

    // Anchor the menu under the button, right-aligned to its right edge, and
    // clamped inside the overlay so it never spills off-screen.
    final buttonTopLeft = buttonBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final desiredLeft = buttonTopLeft.dx + buttonBox.size.width - _menuWidth;
    final maxLeft = (overlayBox.size.width - _menuWidth).clamp(
      0.0,
      double.infinity,
    );
    final left = desiredLeft.clamp(0.0, maxLeft);
    final top = buttonTopLeft.dy + buttonBox.size.height + _menuGap;

    // True (device) global coordinates — compared against the barrier tap's
    // own `globalPosition` in `_handleBarrierTapUp`.
    _buttonRect = buttonBox.localToGlobal(Offset.zero) & buttonBox.size;

    // The button's BuildContext owns the TabsBloc; expose it to the overlay,
    // which lives under the root Navigator (outside this subtree).
    final tabsBloc = context.read<TabsBloc>();

    _menuEntry = OverlayEntry(
      builder: (_) => _PanelMenu(
        left: left,
        top: top,
        width: _menuWidth,
        tabsBloc: tabsBloc,
        appTheme: Theme.of(context),
        onDismiss: _removeMenu,
        onBarrierTapUp: _handleBarrierTapUp,
        droppedTabId: droppedTabId,
      ),
    );
    overlay.insert(_menuEntry!);
  }

  void _renameActivePanel(BuildContext context, PanelEntity panel) {
    final bloc = context.read<TabsBloc>();
    unawaited(
      NamePromptDialog.show(
        context,
        title: 'RENAME PANEL',
        initialText: panel.name,
        allowEmpty: true,
        onConfirm: (value) => bloc.add(RenamePanel(panel.id, value)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (p, n) =>
          p.panels != n.panels || p.activePanelId != n.activePanelId,
      builder: (context, state) {
        final active = state.activePanel;
        if (active == null) return const SizedBox.shrink();
        return _SelectorButton(
          activeName: active.name,
          onTap: () => _handleTap(context, active),
          // When a tab is dropped onto the selector, open the panel menu in
          // "move" mode so the user can pick a target panel.
          onTabDropped: (tabId) => _openMenu(context, droppedTabId: tabId),
        );
      },
    );
  }
}

/// The clickable chip in the tab strip showing the active panel name. Renders
/// compact (icon + short ellipsized name) on phone, full ellipsized name
/// otherwise. Wrapped in a [DragTarget] so a dragged tab (Task 9) can land on
/// it.
class _SelectorButton extends StatelessWidget {
  const _SelectorButton({
    required this.activeName,
    required this.onTap,
    required this.onTabDropped,
  });

  final String activeName;
  final VoidCallback onTap;
  final ValueChanged<String> onTabDropped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final compact = context.layoutMode == LayoutMode.phone;

    // Typed to TabDragData (not a bare String) so a collection-node drag
    // (NodeDragData) neither highlights this target nor gets accepted (D4).
    return DragTarget<TabDragData>(
      onAcceptWithDetails: (details) => onTabDropped(details.data.tabId),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return GestureDetector(
          key: const ValueKey('panel_selector_button'),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? layout.tabSpacing : layout.inputPadding,
              vertical: layout.inputPaddingVertical,
            ),
            decoration: BoxDecoration(
              color: hovering ? theme.primaryColor : null,
              border: Border.all(
                color: theme.dividerColor,
                width: layout.borderThin,
              ),
              borderRadius: BorderRadius.circular(
                context.appShape.buttonRadius,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.dashboard_customize_outlined,
                  size: layout.iconSize,
                  color: hovering
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
                SizedBox(width: layout.tabSpacing),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: compact ? _labelMaxWidthCompact : _labelMaxWidth,
                  ),
                  child: Text(
                    activeName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: layout.fontSizeSmall,
                      fontWeight: context.appTypography.titleWeight,
                      color: hovering
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: layout.smallIconSize,
                  color: hovering
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The overlay drop-down: a dismiss barrier + an anchored card hosting the
/// reorderable panel list and the add-panel footer. Rebuilds itself off the
/// supplied [tabsBloc] so reorder / rename / close reflect immediately while
/// the overlay stays open.
class _PanelMenu extends StatelessWidget {
  const _PanelMenu({
    required this.left,
    required this.top,
    required this.width,
    required this.tabsBloc,
    required this.appTheme,
    required this.onDismiss,
    required this.onBarrierTapUp,
    this.droppedTabId,
  });

  final double left;
  final double top;
  final double width;
  final TabsBloc tabsBloc;
  final ThemeData appTheme;
  final VoidCallback onDismiss;

  /// Called with the tap's global position when the full-screen dismiss
  /// barrier is tapped — lets the selector tell a genuine double-tap-on-button
  /// (barrier now covers it) apart from a plain tap-outside-to-dismiss (D1).
  final ValueChanged<Offset> onBarrierTapUp;

  /// When non-null, every panel row tapping dispatches [MoveTabToPanel] instead
  /// of [SetActivePanel], and the add-footer dispatches [MoveTabToNewPanel].
  final String? droppedTabId;

  @override
  Widget build(BuildContext context) {
    // The overlay is mounted above MaterialApp's Theme; re-inject the captured
    // app theme so the menu reads the same extensions as the tab strip.
    return Theme(
      data: appTheme,
      child: BlocProvider<TabsBloc>.value(
        value: tabsBloc,
        child: Stack(
          children: [
            // Full-screen tap barrier so a click outside closes the menu. Also
            // the landing spot for the second tap of a real double-tap on the
            // button (the barrier now covers it) — routed through
            // `onBarrierTapUp` so the selector can recognize that case (D1).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => onBarrierTapUp(details.globalPosition),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: width,
              child: _PanelMenuCard(
                onDismiss: onDismiss,
                droppedTabId: droppedTabId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelMenuCard extends StatelessWidget {
  const _PanelMenuCard({required this.onDismiss, this.droppedTabId});

  final VoidCallback onDismiss;
  final String? droppedTabId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: context.appDecoration.panelBox(context),
        constraints: BoxConstraints(maxHeight: layout.quickListMaxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: BlocBuilder<TabsBloc, TabsState>(
                buildWhen: (p, n) =>
                    p.panels != n.panels || p.activePanelId != n.activePanelId,
                builder: (context, state) {
                  final panels = state.panels;
                  final canClose = panels.length > 1;
                  return ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    itemCount: panels.length,
                    onReorderItem: (oldIndex, newIndex) => context
                        .read<TabsBloc>()
                        .add(ReorderPanels(oldIndex, newIndex)),
                    proxyDecorator: (child, index, animation) => Material(
                      color: theme.scaffoldBackgroundColor,
                      elevation: 4,
                      child: child,
                    ),
                    itemBuilder: (context, index) {
                      final panel = panels[index];
                      return _PanelRow(
                        key: ValueKey('panel_row_${panel.id}'),
                        index: index,
                        panel: panel,
                        isActive: panel.id == state.activePanelId,
                        canClose: canClose,
                        onDismiss: onDismiss,
                        droppedTabId: droppedTabId,
                      );
                    },
                  );
                },
              ),
            ),
            Divider(height: layout.borderThin, color: theme.dividerColor),
            _AddPanelFooter(
              onDismiss: onDismiss,
              droppedTabId: droppedTabId,
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the panel menu: drag handle + name + tab-count + active check,
/// with rename (pencil) and close (✕) affordances. The ✕ is omitted when only
/// one panel remains (you can't close the last panel).
class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.index,
    required this.panel,
    required this.isActive,
    required this.canClose,
    required this.onDismiss,
    this.droppedTabId,
    super.key,
  });

  final int index;
  final PanelEntity panel;
  final bool isActive;
  final bool canClose;
  final VoidCallback onDismiss;

  /// When non-null, tapping this row dispatches [MoveTabToPanel] instead of
  /// [SetActivePanel].
  final String? droppedTabId;

  void _rename(BuildContext context) {
    final bloc = context.read<TabsBloc>();
    // Dismiss AFTER show so the overlay context is still mounted when
    // Navigator.of(context, rootNavigator: true) is called inside show.
    unawaited(
      NamePromptDialog.show(
        context,
        title: 'RENAME PANEL',
        initialText: panel.name,
        allowEmpty: true,
        onConfirm: (value) => bloc.add(RenamePanel(panel.id, value)),
      ),
    );
    onDismiss();
  }

  void _close(BuildContext context) {
    // The overlay row's context is about to be unmounted by [onDismiss]; the
    // close coordinator awaits across several dialogs and guards each step with
    // `context.mounted`, so it must run against a context that OUTLIVES the
    // overlay (otherwise the dirty-tab paths abort after the first await and
    // the panel is never removed). Capture the root navigator's context — it
    // sits below every bloc/`TabDirtyChecker` provider and stays mounted while
    // the dialogs (pushed on that same root navigator) are open.
    final stableContext = Navigator.of(context, rootNavigator: true).context;
    final panelId = panel.id;
    // Dismiss the overlay first so its barrier doesn't sit over the dialogs.
    onDismiss();
    unawaited(closePanelWithSavePrompt(stableContext, panelId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return InkWell(
      onTap: () {
        final bloc = context.read<TabsBloc>();
        final tabId = droppedTabId;
        if (tabId != null) {
          bloc.add(MoveTabToPanel(tabId, panel.id));
        } else {
          bloc.add(SetActivePanel(panel.id));
        }
        onDismiss();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: layout.inputPadding,
          vertical: layout.inputPaddingVertical,
        ),
        child: Row(
          children: [
            if (isActive)
              Icon(
                Icons.check,
                size: layout.smallIconSize,
                color: theme.colorScheme.secondary,
              )
            else
              SizedBox(width: layout.smallIconSize),
            SizedBox(width: layout.tabSpacing),
            Expanded(
              child: Text(
                panel.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: isActive
                      ? context.appTypography.titleWeight
                      : context.appTypography.bodyWeight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            SizedBox(width: layout.tabSpacing),
            Text(
              '${panel.tabs.length}',
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.titleWeight,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            SizedBox(width: layout.tabSpacing),
            IconButton(
              key: ValueKey('panel_rename_${panel.id}'),
              icon: Icon(Icons.edit, size: layout.smallIconSize),
              tooltip: 'Rename',
              color: theme.colorScheme.onSurface,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              padding: EdgeInsets.all(layout.badgePaddingVertical),
              onPressed: () => _rename(context),
            ),
            if (canClose)
              IconButton(
                key: ValueKey('panel_close_${panel.id}'),
                icon: Icon(Icons.close, size: layout.smallIconSize),
                tooltip: 'Close panel',
                color: theme.colorScheme.error,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.all(layout.badgePaddingVertical),
                onPressed: () => _close(context),
              ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: EdgeInsets.only(left: layout.tabSpacing),
                child: Icon(
                  Icons.drag_handle,
                  size: layout.smallIconSize,
                  color: theme.dividerColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPanelFooter extends StatelessWidget {
  const _AddPanelFooter({required this.onDismiss, this.droppedTabId});

  final VoidCallback onDismiss;

  /// When non-null, tapping dispatches [MoveTabToNewPanel] instead of
  /// [AddPanel].
  final String? droppedTabId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return InkWell(
      key: const ValueKey('panel_add_button'),
      onTap: () {
        final bloc = context.read<TabsBloc>();
        final tabId = droppedTabId;
        if (tabId != null) {
          bloc.add(MoveTabToNewPanel(tabId));
        } else {
          bloc.add(const AddPanel());
        }
        onDismiss();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: layout.inputPadding,
          vertical: layout.inputPaddingVertical,
        ),
        child: Row(
          children: [
            Icon(
              Icons.add,
              size: layout.smallIconSize,
              color: theme.colorScheme.onSurface,
            ),
            SizedBox(width: layout.tabSpacing),
            Text(
              'New panel',
              style: TextStyle(
                fontSize: layout.fontSizeNormal,
                fontWeight: context.appTypography.titleWeight,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
