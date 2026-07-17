import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/tab_drag_data.dart';

/// Delay before the hover tooltip appears, so a quick pass across the tab
/// strip doesn't flash it. Durations aren't part of the theme extensions; this
/// matches the other hardcoded Durations already in this file.
const Duration _tabTooltipDelay = Duration(milliseconds: 500);

/// Max width of the hover tooltip card (mirrors variable_hover_popover's 320 +
/// a little extra room for URLs). Long URLs wrap to 2 lines then ellipsis.
const double _tabTooltipMaxWidth = 360;

class RequestTabChip extends StatefulWidget {
  const RequestTabChip({
    required this.tabId,
    required this.index,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    super.key,
  });
  final String tabId;
  final int index;
  final bool isActive;
  final VoidCallback onTap;
  final Future<bool> Function() onClose;

  @override
  State<RequestTabChip> createState() => _RequestTabChipState();
}

class _RequestTabChipState extends State<RequestTabChip>
    with TickerProviderStateMixin {
  late AnimationController _sizeController;
  late Animation<double> _sizeAnimation;
  bool _isClosing = false;
  bool _isHovered = false;
  Timer? _tooltipTimer;
  OverlayEntry? _tooltipEntry;

  @override
  void initState() {
    super.initState();
    _sizeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _sizeAnimation = CurvedAnimation(
      parent: _sizeController,
      curve: Curves.easeOutCubic,
    );
    unawaited(_sizeController.forward());
  }

  @override
  void dispose() {
    _hideTooltip();
    _sizeController.dispose();
    super.dispose();
  }

  bool _closeRequestInFlight = false;

  Future<void> _handleClose() async {
    // Set synchronously: _isClosing only flips after the (possibly dialog-
    // showing) onClose await, so a double-click would otherwise pass the
    // guard twice and stack two confirm dialogs.
    if (_isClosing || _closeRequestInFlight) return;
    _closeRequestInFlight = true;
    try {
      final confirmed = await widget.onClose();
      if (!confirmed || !mounted) return;
      setState(() => _isClosing = true);
    } finally {
      _closeRequestInFlight = false;
    }
    await _sizeController.reverse();
    if (!mounted) return;
    context.read<TabsBloc>().add(RemoveTab(widget.tabId));
  }

  void _scheduleTooltip(HttpRequestTabEntity tab) {
    _tooltipTimer?.cancel();
    _tooltipTimer = Timer(_tabTooltipDelay, () => _showTooltip(tab));
  }

  void _hideTooltip() {
    _tooltipTimer?.cancel();
    _tooltipTimer = null;
    _tooltipEntry?.remove();
    _tooltipEntry?.dispose();
    _tooltipEntry = null;
  }

  void _showTooltip(HttpRequestTabEntity tab) {
    if (!mounted || _tooltipEntry != null) return;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final tabBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null || tabBox == null) return;

    const gap = 4.0;
    final tabTopLeft = tabBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final maxLeft = (overlayBox.size.width - _tabTooltipMaxWidth - gap).clamp(
      0.0,
      double.infinity,
    );
    final left = tabTopLeft.dx.clamp(0.0, maxLeft);
    final top = tabTopLeft.dy + tabBox.size.height + gap;

    _tooltipEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: left,
        top: top,
        child: _TabTooltipCard(tab: tab),
      ),
    );
    overlay.insert(_tooltipEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocBuilder<TabsBloc, TabsState>(
      // The chrome only shows the title (collectionName / config.url) and the
      // dirty marker (config vs saved). Rebuild on those, but NOT on response
      // arrival / isSending / extraction results — otherwise every body
      // keystroke or a multi-MB response would drag the whole entity (incl. the
      // response body) through `==` and rebuild the chrome of every open tab.
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(widget.tabId);
        final n = next.tabs.byId(widget.tabId);
        if (identical(p, n)) return false;
        if (p == null || n == null) return p != n;
        return p.config != n.config ||
            p.collectionName != n.collectionName ||
            p.collectionNodeId != n.collectionNodeId;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(widget.tabId);
        if (tab == null) return const SizedBox.shrink();

        final dirtyChecker = context.read<TabDirtyChecker>();
        return BlocSelector<CollectionsBloc, CollectionsState, bool>(
          selector: (collState) =>
              dirtyChecker(tab: tab, savedConfigs: collState.configById),
          builder: (context, isDirty) {
            final title = tab.displayTitle;
            final displayTitle = title.length > layout.tabTitleMaxLength
                ? '${title.substring(0, layout.tabTitleMaxLength)}...'
                : title;

            return SizeTransition(
              sizeFactor: _sizeAnimation,
              axis: Axis.horizontal,
              alignment: Alignment.topLeft,
              child: ReorderableDragStartListener(
                index: widget.index,
                // Typed to TabDragData (not a bare String) so a dragged
                // collection-tree NODE neither highlights nor gets accepted by
                // targets meant for tabs, e.g. the panel selector (D4).
                child: LongPressDraggable<TabDragData>(
                  data: TabDragData(widget.tabId),
                  feedback: _TabDragFeedback(title: displayTitle),
                  childWhenDragging: Opacity(
                    opacity: 0.4,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          _hideTooltip();
                          widget.onTap();
                        },
                        onTertiaryTapUp: (_) => _handleClose(),
                        onSecondaryTapDown: (details) => _showContextMenu(
                          context,
                          details.globalPosition,
                          tab,
                        ),
                        child: Semantics(
                          tooltip: tab.config.url.isEmpty
                              ? tab.displayTitle
                              : '${tab.displayTitle}\n${tab.config.url}',
                          child: AnimatedContainer(
                            key: ValueKey(context.appDecoration.tabShape),
                            duration: const Duration(milliseconds: 200),
                            height: layout.tabBarHeight,
                            constraints: BoxConstraints(
                              minWidth: layout.isCompact ? 80 : 120,
                              maxWidth: layout.isCompact ? 150 : 250,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: layout.tabPaddingHorizontal,
                            ),
                            decoration: context.appDecoration.tabShape(
                              context,
                              active: widget.isActive,
                              hovered: _isHovered,
                              isFirst: widget.index == 0,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: layout.tabFontSize,
                                      color: widget.isActive
                                          ? (theme.tabBarTheme.labelColor ??
                                                theme.colorScheme.onSurface)
                                          : (theme
                                                    .tabBarTheme
                                                    .unselectedLabelColor ??
                                                theme.colorScheme.onSurface),
                                      fontWeight: isDirty
                                          ? context.appTypography.displayWeight
                                          : (widget.isActive
                                                ? context
                                                      .appTypography
                                                      .displayWeight
                                                : context
                                                      .appTypography
                                                      .bodyWeight),
                                    ),
                                  ),
                                ),
                                if (isDirty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Text(
                                      '*',
                                      style: TextStyle(
                                        color: theme.colorScheme.secondary,
                                        fontSize: layout.dirtyStarSize,
                                        fontWeight:
                                            context.appTypography.displayWeight,
                                      ),
                                    ),
                                  ),
                                SizedBox(width: layout.tabSpacing),
                                IconButton(
                                  key: ValueKey('tab_close_${tab.tabId}'),
                                  icon: Icon(
                                    Icons.close,
                                    size: layout.tabCloseIconSize,
                                    color: theme.dividerColor,
                                  ),
                                  onPressed: _handleClose,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) {
                      setState(() => _isHovered = true);
                      _scheduleTooltip(tab);
                    },
                    onExit: (_) {
                      setState(() => _isHovered = false);
                      _hideTooltip();
                    },
                    child: GestureDetector(
                      onTap: () {
                        _hideTooltip();
                        widget.onTap();
                      },
                      onTertiaryTapUp: (_) => _handleClose(),
                      onSecondaryTapDown: (details) => _showContextMenu(
                        context,
                        details.globalPosition,
                        tab,
                      ),
                      child: Semantics(
                        tooltip: tab.config.url.isEmpty
                            ? tab.displayTitle
                            : '${tab.displayTitle}\n${tab.config.url}',
                        child: AnimatedContainer(
                          // Re-key per theme so a theme switch REPLACES this
                          // container instead of tweening into the new shape.
                          // Flat themes use an asymmetric border + no radius;
                          // glass uses a uniform border + radius. A mid-tween
                          // frame between the two families would carry a
                          // non-uniform border AND a borderRadius, which
                          // Border.paint rejects. The builder ref changes
                          // exactly when the shape family does, so
                          // hover/active/brightness changes within a theme
                          // still animate.
                          key: ValueKey(context.appDecoration.tabShape),
                          duration: const Duration(milliseconds: 200),
                          height: layout.tabBarHeight,
                          constraints: BoxConstraints(
                            minWidth: layout.isCompact ? 80 : 120,
                            maxWidth: layout.isCompact ? 150 : 250,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: layout.tabPaddingHorizontal,
                          ),
                          decoration: context.appDecoration.tabShape(
                            context,
                            active: widget.isActive,
                            hovered: _isHovered,
                            isFirst: widget.index == 0,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: layout.tabFontSize,
                                    color: widget.isActive
                                        ? (theme.tabBarTheme.labelColor ??
                                              theme.colorScheme.onSurface)
                                        : (theme
                                                  .tabBarTheme
                                                  .unselectedLabelColor ??
                                              theme.colorScheme.onSurface),
                                    fontWeight: isDirty
                                        ? context.appTypography.displayWeight
                                        : (widget.isActive
                                              ? context
                                                    .appTypography
                                                    .displayWeight
                                              : context
                                                    .appTypography
                                                    .bodyWeight),
                                  ),
                                ),
                              ),
                              if (isDirty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    '*',
                                    style: TextStyle(
                                      color: theme.colorScheme.secondary,
                                      fontSize: layout.dirtyStarSize,
                                      fontWeight:
                                          context.appTypography.displayWeight,
                                    ),
                                  ),
                                ),
                              SizedBox(width: layout.tabSpacing),
                              IconButton(
                                key: ValueKey('tab_close_${tab.tabId}'),
                                icon: Icon(
                                  Icons.close,
                                  size: layout.tabCloseIconSize,
                                  color: theme.dividerColor,
                                ),
                                onPressed: _handleClose,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// The tabs a bulk-close action would remove, mirroring the exact bloc
  /// semantics in `TabsBloc._onCloseOtherTabs` / `_onCloseTabsToTheRight` /
  /// `_onCloseTabsToTheLeft` — used only to decide whether to gate the
  /// dispatch behind an unsaved-changes confirm (D6).
  List<HttpRequestTabEntity> _bulkCloseTargets(
    List<HttpRequestTabEntity> tabs,
    String tabId,
    _BulkCloseKind kind,
  ) {
    final index = tabs.indexWhere((t) => t.tabId == tabId);
    if (index == -1) return const [];
    switch (kind) {
      case _BulkCloseKind.others:
        if (tabs.length <= 1) return const [];
        return [
          for (final t in tabs)
            if (t.tabId != tabId) t,
        ];
      case _BulkCloseKind.toTheRight:
        if (index >= tabs.length - 1) return const [];
        return tabs.sublist(index + 1);
      case _BulkCloseKind.toTheLeft:
        if (index <= 0) return const [];
        return tabs.sublist(0, index);
    }
  }

  /// Dispatches a bulk-close event, gated behind an unsaved-changes confirm
  /// when any affected tab is dirty — mirrors the single-tab close confirm in
  /// `MainScreen._requestCloseConfirmation` and the panel-close confirm in
  /// `closePanelWithSavePrompt` (D6): bulk closes must not silently destroy
  /// unsaved work just because they weren't the single-tab path.
  void _bulkClose(
    BuildContext context,
    String tabId,
    _BulkCloseKind kind,
    TabsEvent Function() buildEvent,
  ) {
    final tabsBloc = context.read<TabsBloc>();
    final collectionsBloc = context.read<CollectionsBloc>();
    final dirtyChecker = context.read<TabDirtyChecker>();
    final targets = _bulkCloseTargets(tabsBloc.state.tabs, tabId, kind);
    final savedConfigs = collectionsBloc.state.configById;
    final dirtyCount = targets
        .where((t) => dirtyChecker(tab: t, savedConfigs: savedConfigs))
        .length;
    if (dirtyCount == 0) {
      tabsBloc.add(buildEvent());
      return;
    }
    // showMenu closes this menu's route before onTap returns; defer to the
    // next frame so the dialog opens after the menu route is fully dismissed
    // (same pattern as the MOVE TO PANEL submenu below).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ConfirmDialog.show(
          context,
          title: 'UNSAVED CHANGES',
          message: dirtyCount == 1
              ? '1 TAB HAS UNSAVED CHANGES. ARE YOU SURE YOU WANT TO CLOSE IT?'
              : '$dirtyCount TABS HAVE UNSAVED CHANGES. ARE YOU SURE YOU '
                    'WANT TO CLOSE THEM?',
          confirmLabel: 'CLOSE ANYWAY',
          onConfirm: () => tabsBloc.add(buildEvent()),
        ),
      );
    });
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    HttpRequestTabEntity tab,
  ) {
    _hideTooltip();
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final tabsBloc = context.read<TabsBloc>();

    unawaited(
      showMenu<void>(
        context: context,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          position.dx + 1,
          position.dy + 1,
        ),
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          side: BorderSide(
            color: theme.dividerColor,
            width: layout.borderThick,
          ),
        ),
        elevation: 0,
        items: <PopupMenuEntry<void>>[
          PopupMenuItem(
            onTap: _handleClose,
            child: _buildMenuItem(context, Icons.close, 'CLOSE'),
          ),
          PopupMenuItem(
            onTap: () => _bulkClose(
              context,
              tab.tabId,
              _BulkCloseKind.others,
              () => CloseOtherTabs(tab.tabId),
            ),
            child: _buildMenuItem(
              context,
              Icons.tab_unselected,
              'CLOSE OTHERS',
            ),
          ),
          PopupMenuItem(
            onTap: () => _bulkClose(
              context,
              tab.tabId,
              _BulkCloseKind.toTheLeft,
              () => CloseTabsToTheLeft(tab.tabId),
            ),
            child: _buildMenuItem(
              context,
              Icons.keyboard_double_arrow_left,
              'CLOSE TO THE LEFT',
            ),
          ),
          PopupMenuItem(
            onTap: () => _bulkClose(
              context,
              tab.tabId,
              _BulkCloseKind.toTheRight,
              () => CloseTabsToTheRight(tab.tabId),
            ),
            child: _buildMenuItem(
              context,
              Icons.keyboard_double_arrow_right,
              'CLOSE TO THE RIGHT',
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            onTap: () {
              tabsBloc.add(DuplicateTab(tab.tabId));
              showAppSnackBar(context, 'Tab duplicated');
            },
            child: _buildMenuItem(context, Icons.copy, 'DUPLICATE'),
          ),
          PopupMenuItem(
            onTap: () {
              unawaited(Clipboard.setData(ClipboardData(text: tab.config.url)));
              showAppSnackBar(context, 'URL copied');
            },
            child: _buildMenuItem(context, Icons.link, 'COPY URL'),
          ),
          if (tabsBloc.state.panels.length > 1)
            PopupMenuItem(
              key: const ValueKey('tab_context_move_to_panel'),
              onTap: () {
                // showMenu closes the first menu before onTap returns; we need
                // to defer the second menu to the next frame so the first
                // menu's route is fully dismissed before a new route is pushed.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _showMoveToPanelMenu(context, position, tab, tabsBloc);
                });
              },
              child: _buildMenuItem(
                context,
                Icons.drive_file_move_outline,
                'MOVE TO PANEL',
              ),
            ),
        ],
      ),
    );
  }

  void _showMoveToPanelMenu(
    BuildContext context,
    Offset position,
    HttpRequestTabEntity tab,
    TabsBloc tabsBloc,
  ) {
    if (!mounted) return;
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final state = tabsBloc.state;

    // Find the panel that currently owns this tab.
    final ownerPanel = state.panels.firstWhereOrNull(
      (p) => p.tabs.any((t) => t.tabId == widget.tabId),
    );

    // Show only the panels this tab can be moved TO (i.e. not its current one).
    final otherPanels = state.panels
        .where((p) => p.id != ownerPanel?.id)
        .toList();

    unawaited(
      showMenu<void>(
        context: context,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          position.dx + 1,
          position.dy + 1,
        ),
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          side: BorderSide(
            color: theme.dividerColor,
            width: layout.borderThick,
          ),
        ),
        elevation: 0,
        items: <PopupMenuEntry<void>>[
          for (final panel in otherPanels)
            PopupMenuItem(
              key: ValueKey('tab_move_to_panel_${panel.id}'),
              onTap: () => tabsBloc.add(MoveTabToPanel(widget.tabId, panel.id)),
              child: _buildMenuItem(
                context,
                Icons.dashboard_customize_outlined,
                panel.name.toUpperCase(),
              ),
            ),
          PopupMenuItem(
            key: const ValueKey('tab_move_to_new_panel'),
            onTap: () => tabsBloc.add(MoveTabToNewPanel(widget.tabId)),
            child: _buildMenuItem(
              context,
              Icons.add,
              'NEW PANEL…',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurface),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            fontWeight: context.appTypography.displayWeight,
            fontSize: context.appLayout.fontSizeNormal,
          ),
        ),
      ],
    );
  }
}

/// Small chip rendered as the drag feedback when a tab is long-pressed and
/// dragged toward the panel selector. Uses theme colors so it reads correctly
/// over any background.
class _TabDragFeedback extends StatelessWidget {
  const _TabDragFeedback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(context.appShape.buttonRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          title,
          style: TextStyle(
            fontSize: layout.fontSizeNormal,
            fontWeight: context.appTypography.titleWeight,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// The hover tooltip card: the tab's display title with the URL beneath it in a
/// muted color. Themed via the active theme's `panelBox`; the URL line is
/// omitted when the request has no URL.
class _TabTooltipCard extends StatelessWidget {
  const _TabTooltipCard({required this.tab});

  final HttpRequestTabEntity tab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final typography = context.appTypography;
    final url = tab.config.url;

    return Material(
      type: MaterialType.transparency,
      child: context.appDecoration.frost(
        context,
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        child: Container(
          key: ValueKey('tab_tooltip_${tab.tabId}'),
          constraints: const BoxConstraints(maxWidth: _tabTooltipMaxWidth),
          padding: EdgeInsets.all(layout.isCompact ? 8 : 12),
          decoration: context.appDecoration.panelBox(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tab.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: typography.titleWeight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (url.isNotEmpty) ...[
                SizedBox(height: layout.tabSpacing),
                Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Which bulk tab-close context-menu action is being confirmed — drives how
/// [_RequestTabChipState._bulkCloseTargets] computes the affected tab set.
enum _BulkCloseKind { others, toTheLeft, toTheRight }
