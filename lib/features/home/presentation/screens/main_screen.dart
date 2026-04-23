import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/ui/widgets/splitter.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/environments/domain/logic/active_environment_helper.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/widgets/environment_selector.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/home/presentation/widgets/add_tab_button.dart';
import 'package:getman/features/home/presentation/widgets/side_menu.dart';
import 'package:getman/features/home/presentation/widgets/tab_widget.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/screens/request_view.dart';
import 'package:getman/features/tabs/presentation/widgets/tab_switcher_sheet.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  double? _localSideMenuWidth;
  final FocusNode _mainFocusNode = FocusNode();
  final ScrollController _tabScrollController = ScrollController();
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _mainFocusNode.dispose();
    _tabScrollController.dispose();
    super.dispose();
  }

  void _ensureActiveTabVisible(int activeIndex, int tabsLength, AppLayout layout) {
    if (activeIndex < 0 || activeIndex >= tabsLength) return;
    if (activeIndex == _lastActiveIndex) return;
    _lastActiveIndex = activeIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_tabScrollController.hasClients) return;
      final position = _tabScrollController.position;
      // Tab widths are variable (min 80/120, max 150/250). An average lets us
      // animate approximately into view without per-tab measurement.
      final avgTabWidth = layout.isCompact ? 115.0 : 185.0;
      final targetStart = activeIndex * avgTabWidth;
      final targetEnd = targetStart + avgTabWidth;
      final viewStart = position.pixels;
      final viewEnd = viewStart + position.viewportDimension;

      double? dest;
      if (targetStart < viewStart) {
        dest = targetStart;
      } else if (targetEnd > viewEnd) {
        dest = targetEnd - position.viewportDimension;
      }
      if (dest == null) return;
      _tabScrollController.animateTo(
        dest.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleTabBarPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_tabScrollController.hasClients) return;
    // Mouse-wheel delta is usually purely vertical on desktop; trackpads
    // already emit horizontal components. Combine both so a plain wheel
    // also scrolls the horizontal tab strip.
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    final position = _tabScrollController.position;
    final target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent);
    _tabScrollController.jumpTo(target);
  }

  bool _isTabDirty(BuildContext context, String tabId) {
    final tab = context.read<TabsBloc>().state.tabs.byId(tabId);
    if (tab == null) return false;
    return context.read<TabDirtyChecker>()(
      tab: tab,
      collections: context.read<CollectionsBloc>().state.collections,
    );
  }

  Future<bool> _requestCloseConfirmation(BuildContext context, String tabId) async {
    final tab = context.read<TabsBloc>().state.tabs.byId(tabId);
    if (tab == null) return false;
    if (!_isTabDirty(context, tabId)) return true;

    final result = await showResponsiveDialog<bool>(
      context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return ResponsiveDialogScaffold(
          title: const Text('UNSAVED CHANGES'),
          content: const Text('YOU HAVE UNSAVED CHANGES. ARE YOU SURE YOU WANT TO CLOSE THIS TAB?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCEL')),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('CLOSE ANYWAY',
                  style: TextStyle(color: theme.colorScheme.error, fontWeight: dialogContext.appTypography.titleWeight)),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _confirmAndClose(BuildContext context, String tabId) async {
    final tabsBloc = context.read<TabsBloc>();
    final confirmed = await _requestCloseConfirmation(context, tabId);
    if (!confirmed || !mounted) return;
    tabsBloc.add(RemoveTab(tabId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final settings = settingsState.settings;
        final currentSideMenuWidth = _localSideMenuWidth ?? settings.sideMenuWidth;

        return BlocBuilder<TabsBloc, TabsState>(
          builder: (context, tabsState) {
            final activeIndex = tabsState.activeIndex;
            final tabs = tabsState.tabs;

            return Actions(
              actions: <Type, Action<Intent>>{
                CloseTabIntent: CallbackAction<CloseTabIntent>(
                  onInvoke: (_) {
                    if (activeIndex < 0 || activeIndex >= tabs.length) return null;
                    _confirmAndClose(context, tabs[activeIndex].tabId);
                    return null;
                  },
                ),
                SendRequestIntent: CallbackAction<SendRequestIntent>(
                  onInvoke: (_) {
                    if (activeIndex >= 0 && activeIndex < tabs.length && !tabs[activeIndex].isSending) {
                      final envVars = ActiveEnvironmentHelper.variablesFor(
                        context.read<EnvironmentsBloc>().state.environments,
                        context.read<SettingsBloc>().state.settings.activeEnvironmentId,
                      );
                      context.read<TabsBloc>().add(SendRequest(envVars: envVars));
                    }
                    return null;
                  },
                ),
              },
              child: Focus(
                focusNode: _mainFocusNode,
                child: Scaffold(
                  drawer: context.useDrawerNav ? const Drawer(child: SideMenu()) : null,
                  body: context.useDrawerNav
                      ? _buildDrawerShell(context, theme, tabsState, activeIndex, tabs)
                      : _buildSplitShell(context, theme, tabsState, activeIndex, tabs, currentSideMenuWidth),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDrawerShell(BuildContext context, ThemeData theme, TabsState tabsState, int activeIndex, List<HttpRequestTabEntity> tabs) {
    return Column(
      children: [
        _buildTabBar(context, activeIndex, tabs, includeMenuButton: true),
        Expanded(child: _buildContent(context, theme, tabsState, activeIndex, tabs)),
      ],
    );
  }

  Widget _buildSplitShell(BuildContext context, ThemeData theme, TabsState tabsState, int activeIndex, List<HttpRequestTabEntity> tabs, double currentSideMenuWidth) {
    return Row(
      children: [
        SizedBox(width: currentSideMenuWidth, child: const SideMenu()),
        Splitter(
          isVertical: false,
          onUpdate: (delta) {
            setState(() {
              _localSideMenuWidth = (currentSideMenuWidth + delta).clamp(200.0, 600.0);
            });
          },
          onEnd: () {
            final committed = _localSideMenuWidth;
            if (committed == null) return;
            context.read<SettingsBloc>().add(UpdateSideMenuWidth(committed));
            setState(() => _localSideMenuWidth = null);
          },
        ),
        Expanded(
          child: Column(
            children: [
              _buildTabBar(context, activeIndex, tabs, includeMenuButton: false),
              Expanded(child: _buildContent(context, theme, tabsState, activeIndex, tabs)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme, TabsState tabsState, int activeIndex, List<HttpRequestTabEntity> tabs) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: tabsState.isLoading
          ? const Center(key: ValueKey('loading'), child: CircularProgressIndicator())
          : tabs.isEmpty
              ? Center(
                  key: const ValueKey('empty'),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bolt, size: 64, color: theme.dividerColor.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(
                        'NO OPEN TABS',
                        style: TextStyle(
                          fontSize: context.appLayout.fontSizeSubtitle,
                          fontWeight: context.appTypography.displayWeight,
                          color: theme.dividerColor.withValues(alpha: 0.3),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'PRESS CTRL+N TO CREATE A NEW REQUEST',
                        style: TextStyle(
                          fontSize: context.appLayout.fontSizeNormal,
                          fontWeight: context.appTypography.titleWeight,
                          color: theme.dividerColor.withValues(alpha: 0.2),
                        ),
                      ),
                      const SizedBox(height: 24),
                      context.appDecoration.wrapInteractive(
                        child: ElevatedButton(
                          onPressed: () => context.read<TabsBloc>().add(const AddTab()),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: context.appLayout.buttonPaddingHorizontal, vertical: context.appLayout.buttonPaddingVertical),
                          ),
                          child: const Text('NEW REQUEST'),
                        ),
                      ),
                    ],
                  ),
                )
              : RequestView(
                  key: ValueKey('view_${tabs[activeIndex].tabId}'),
                  tabId: tabs[activeIndex].tabId,
                ),
    );
  }

  Widget _buildTabBar(BuildContext context, int activeIndex, List<HttpRequestTabEntity> tabs, {required bool includeMenuButton}) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    _ensureActiveTabVisible(activeIndex, tabs.length, layout);

    return Container(
      height: layout.tabBarHeight,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: layout.borderThick)),
      ),
      child: Row(
        children: [
          if (includeMenuButton)
            Builder(
              builder: (scaffoldContext) => context.appDecoration.wrapInteractive(
                child: IconButton(
                  icon: Icon(Icons.menu, size: layout.iconSize),
                  tooltip: 'OPEN MENU',
                  onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
                ),
              ),
            ),
          Expanded(
            child: context.useTabSwitcher
                ? _TabChip(activeIndex: activeIndex, tabs: tabs, onRequestClose: _requestCloseConfirmation)
                : Listener(
                    onPointerSignal: _handleTabBarPointerSignal,
                    child: Scrollbar(
                      controller: _tabScrollController,
                      thumbVisibility: true,
                      thickness: 4,
                      radius: const Radius.circular(2),
                      child: ReorderableListView.builder(
                        scrollController: _tabScrollController,
                        scrollDirection: Axis.horizontal,
                        itemCount: tabs.length,
                        buildDefaultDragHandles: false,
                        onReorder: (oldIndex, newIndex) => context.read<TabsBloc>().add(ReorderTabs(oldIndex, newIndex)),
                        proxyDecorator: (child, index, animation) => Material(
                          color: theme.scaffoldBackgroundColor,
                          elevation: 4,
                          child: child,
                        ),
                        itemBuilder: (context, index) {
                          final tab = tabs[index];
                          return TabWidget(
                            key: ValueKey('tab_${tab.tabId}'),
                            tabId: tab.tabId,
                            index: index,
                            isActive: activeIndex == index,
                            onTap: () => context.read<TabsBloc>().add(SetActiveIndex(index)),
                            onClose: () => _requestCloseConfirmation(context, tab.tabId),
                          );
                        },
                      ),
                    ),
                  ),
          ),
          AddTabButton(layout: layout),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: layout.tabSpacing),
            child: const EnvironmentSelector(),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final int activeIndex;
  final List<HttpRequestTabEntity> tabs;
  final Future<bool> Function(BuildContext, String) onRequestClose;

  const _TabChip({required this.activeIndex, required this.tabs, required this.onRequestClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final active = (activeIndex >= 0 && activeIndex < tabs.length) ? tabs[activeIndex] : null;
    final title = active == null
        ? 'NO TABS'
        : (active.collectionName ?? (active.config.url.isEmpty ? 'NEW REQUEST' : active.config.url));

    return InkWell(
      onTap: tabs.isEmpty
          ? null
          : () => TabSwitcherSheet.show(
                context,
                onRequestClose: (tabId) => onRequestClose(context, tabId),
              ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                border: Border.all(color: theme.dividerColor, width: layout.borderThin),
                borderRadius: BorderRadius.circular(context.appShape.panelRadius),
              ),
              child: Text(
                tabs.isEmpty ? '0' : '${activeIndex + 1}/${tabs.length} ▾',
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.displayWeight,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.titleWeight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
