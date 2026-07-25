// Desktop/tablet open-tabs list (D1): a list icon button at the right end of
// the tab strip opens an anchored, searchable dropdown of ALL open tabs
// grouped by panel — method badge + tab title + dirty star per row. Clicking
// a row activates its panel + tab (SetActivePanel, then SetActiveIndex with
// the index computed inside that panel's tab list); Esc or a barrier tap
// closes. Compact-phone keeps TabSwitcherSheet — main_screen only mounts
// this when !context.useTabSwitcher.
//
// Follows panel_selector.dart's manually-managed OverlayEntry pattern (an
// anchored dropdown hosting a focused TextField can't ride PopupMenuButton).
// Gotchas: the overlay mounts above MaterialApp, so TabsBloc /
// CollectionsBloc / TabDirtyChecker / ThemeData are captured from the
// button's context and re-injected into the overlay subtree. Always
// _removeMenu() before assigning a new _menuEntry, or the orphaned barrier
// soft-locks input (see panel_selector.dart's D2 note).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/open_tab_groups.dart';

/// Width of the dropdown card: room for badge + ellipsized title + star.
const double _menuWidth = 320;

/// Gap between the strip button and the overlay it spawns.
const double _menuGap = 4;

/// The list icon button in the desktop/tablet tab strip that opens the
/// searchable, panel-grouped list of every open tab.
class OpenTabsDropdown extends StatefulWidget {
  const OpenTabsDropdown({super.key});

  @override
  State<OpenTabsDropdown> createState() => _OpenTabsDropdownState();
}

class _OpenTabsDropdownState extends State<OpenTabsDropdown> {
  OverlayEntry? _menuEntry;

  @override
  void dispose() {
    _removeMenu();
    super.dispose();
  }

  void _removeMenu() {
    _menuEntry?.remove();
    _menuEntry?.dispose();
    _menuEntry = null;
  }

  void _toggleMenu() {
    if (_menuEntry != null) {
      _removeMenu();
      return;
    }
    _openMenu();
  }

  void _openMenu() {
    // Guard against an already-open menu: overwriting _menuEntry without
    // removing the old one would orphan its barrier (input soft-lock).
    _removeMenu();
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final buttonBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null || buttonBox == null) return;

    // Anchor under the button, right-aligned to its right edge, clamped
    // inside the overlay (mirrors panel_selector.dart).
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

    // The overlay lives above MaterialApp: capture and re-inject everything
    // the rows need from the button's context.
    final tabsBloc = context.read<TabsBloc>();
    final collectionsBloc = context.read<CollectionsBloc>();
    final dirtyChecker = context.read<TabDirtyChecker>();

    _menuEntry = OverlayEntry(
      builder: (_) => _OpenTabsMenu(
        left: left,
        top: top,
        width: _menuWidth,
        tabsBloc: tabsBloc,
        collectionsBloc: collectionsBloc,
        dirtyChecker: dirtyChecker,
        appTheme: Theme.of(context),
        onDismiss: _removeMenu,
      ),
    );
    overlay.insert(_menuEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return context.appDecoration.wrapInteractive(
      child: IconButton(
        key: const ValueKey('open_tabs_button'),
        icon: Icon(
          Icons.list,
          size: layout.iconSize,
          color: theme.colorScheme.onSurface,
        ),
        tooltip: 'OPEN TABS',
        onPressed: _toggleMenu,
      ),
    );
  }
}

/// The overlay: full-screen dismiss barrier + anchored card. Re-injects the
/// captured theme, blocs, and dirty checker (the overlay is mounted above
/// MaterialApp, outside the app's provider tree).
class _OpenTabsMenu extends StatelessWidget {
  const _OpenTabsMenu({
    required this.left,
    required this.top,
    required this.width,
    required this.tabsBloc,
    required this.collectionsBloc,
    required this.dirtyChecker,
    required this.appTheme,
    required this.onDismiss,
  });

  final double left;
  final double top;
  final double width;
  final TabsBloc tabsBloc;
  final CollectionsBloc collectionsBloc;
  final TabDirtyChecker dirtyChecker;
  final ThemeData appTheme;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: appTheme,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<CollectionsBloc>.value(value: collectionsBloc),
        ],
        child: RepositoryProvider<TabDirtyChecker>.value(
          value: dirtyChecker,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDismiss,
                ),
              ),
              Positioned(
                left: left,
                top: top,
                width: width,
                // A dedicated FocusScope: without one, the search field's
                // autofocus is a silent no-op. This OverlayEntry mounts as a
                // sibling of the route's own _ModalScope (not nested inside
                // it), so the field's nearest ancestor FocusScopeNode would
                // otherwise be the app's ROOT scope — which the ModalScope
                // already claimed as its focusedChild the moment the route
                // was installed. Autofocus only applies when its nearest
                // scope's focusedChild is still null (see
                // FocusManager._Autofocus.applyIfValid), so it was being
                // discarded and Esc had nothing to bubble up from.
                child: FocusScope(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape):
                          onDismiss,
                    },
                    child: _OpenTabsMenuCard(onDismiss: onDismiss),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card: search field on top, panel-grouped tab rows below.
class _OpenTabsMenuCard extends StatefulWidget {
  const _OpenTabsMenuCard({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  State<_OpenTabsMenuCard> createState() => _OpenTabsMenuCardState();
}

class _OpenTabsMenuCardState extends State<_OpenTabsMenuCard> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // No Debouncer: the open-tab count is small (tens, not thousands), so a
    // per-keystroke filter is cheap and keeps the dropdown snappy.
    _searchController.addListener(
      () => setState(() => _query = _searchController.text),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _activate(BuildContext context, OpenTabGroup group, String tabId) {
    final bloc = context.read<TabsBloc>();
    final index = group.panel.tabs.indexWhere((t) => t.tabId == tabId);
    // Panel first, then position within THAT panel's strip. SetActiveIndex is
    // one of the two documented positional events (position is the operation
    // once the panel is active); TabsBloc processes events in dispatch order.
    bloc.add(SetActivePanel(group.panel.id));
    if (index >= 0) bloc.add(SetActiveIndex(index));
    widget.onDismiss();
  }

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
            Padding(
              padding: EdgeInsets.all(layout.tabSpacing),
              child: TextField(
                key: const ValueKey('open_tabs_search_field'),
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'SEARCH TABS...',
                  hintStyle: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    fontWeight: context.appTypography.displayWeight,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: layout.iconSize,
                    color: theme.colorScheme.onSurface,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      context.appShape.panelRadius,
                    ),
                    borderSide: BorderSide(
                      color: theme.dividerColor,
                      width: layout.borderThin,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.titleWeight,
                ),
              ),
            ),
            Divider(height: layout.borderThin, color: theme.dividerColor),
            Flexible(
              child: BlocBuilder<TabsBloc, TabsState>(
                buildWhen: (p, n) =>
                    p.panels != n.panels ||
                    p.activePanelId != n.activePanelId ||
                    p.activeIndex != n.activeIndex,
                builder: (context, state) {
                  final groups = filterOpenTabGroups(state.panels, _query);
                  if (groups.isEmpty) {
                    return Padding(
                      padding: EdgeInsets.all(layout.inputPadding),
                      child: Text(
                        'NO MATCHING TABS',
                        style: TextStyle(
                          fontSize: layout.fontSizeSmall,
                          fontWeight: context.appTypography.displayWeight,
                          color: theme.dividerColor.withValues(alpha: 0.5),
                        ),
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.symmetric(
                      vertical: layout.tabSpacing / 2,
                    ),
                    children: [
                      for (final group in groups) ...[
                        _GroupHeader(
                          panelId: group.panel.id,
                          name: group.panel.name,
                          count: group.tabs.length,
                        ),
                        for (final tab in group.tabs)
                          _OpenTabRow(
                            key: ValueKey('open_tabs_row_${tab.tabId}'),
                            tab: tab,
                            onTap: () => _activate(context, group, tab.tabId),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A panel section header: uppercased panel name + tab count.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.panelId,
    required this.name,
    required this.count,
  });
  final String panelId;
  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Padding(
      key: ValueKey('open_tabs_group_$panelId'),
      padding: EdgeInsets.symmetric(
        horizontal: layout.inputPadding,
        vertical: layout.tabSpacing / 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.displayWeight,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.titleWeight,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tab row: method badge + ellipsized title + dirty star. The star
/// mirrors request_tab_chip.dart: TabDirtyChecker against
/// CollectionsState.configById via a narrow BlocSelector.
class _OpenTabRow extends StatelessWidget {
  const _OpenTabRow({required this.tab, required this.onTap, super.key});
  final HttpRequestTabEntity tab;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final dirtyChecker = context.read<TabDirtyChecker>();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: layout.inputPadding,
          vertical: layout.inputPaddingVertical,
        ),
        child: Row(
          children: [
            MethodBadge(method: tab.config.method, small: true),
            SizedBox(width: layout.tabSpacing),
            Expanded(
              child: Text(
                tab.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.titleWeight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            BlocSelector<CollectionsBloc, CollectionsState, bool>(
              selector: (collState) => dirtyChecker(
                tab: tab,
                savedConfigs: collState.configById,
              ),
              builder: (context, isDirty) => isDirty
                  ? Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        '*',
                        style: TextStyle(
                          color: theme.colorScheme.secondary,
                          fontSize: layout.dirtyStarSize,
                          fontWeight: context.appTypography.displayWeight,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
