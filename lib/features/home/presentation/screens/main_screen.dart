import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/splitter.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
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

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  double? _localSideMenuWidth;
  final FocusNode _mainFocusNode = FocusNode();

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
    super.dispose();
  }

  bool _isTabDirty(BuildContext context, String tabId) {
    final tab = context.read<TabsBloc>().state.tabs.firstWhereOrNull((t) => t.tabId == tabId);
    if (tab == null) return false;
    return context.read<TabDirtyChecker>()(
      tab: tab,
      collections: context.read<CollectionsBloc>().state.collections,
    );
  }

  void _confirmClose(BuildContext context, String tabId) {
    final tabsBloc = context.read<TabsBloc>();
    final tab = tabsBloc.state.tabs.firstWhereOrNull((t) => t.tabId == tabId);
    if (tab == null) return;

    final isDirty = _isTabDirty(context, tabId);

    void performRemove() {
      tabsBloc.add(RemoveTab(tabId));
    }

    if (isDirty) {
      showDialog(
        context: context,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          return AlertDialog(
            title: const Text('UNSAVED CHANGES'),
            content: const Text('YOU HAVE UNSAVED CHANGES. ARE YOU SURE YOU WANT TO CLOSE THIS TAB?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  performRemove();
                },
                child: Text('CLOSE ANYWAY',
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: context.appTypography.titleWeight)),
              ),
            ],
          );
        },
      );
    } else {
      performRemove();
    }
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
                    _confirmClose(context, tabs[activeIndex].tabId);
                    return null;
                  },
                ),
                SendRequestIntent: CallbackAction<SendRequestIntent>(
                  onInvoke: (_) {
                    if (activeIndex >= 0 && activeIndex < tabs.length && !tabs[activeIndex].isSending) {
                      context.read<TabsBloc>().add(const SendRequest());
                    }
                    return null;
                  },
                ),
              },
              child: Focus(
                focusNode: _mainFocusNode,
                child: Scaffold(
                  body: Row(
                    children: [
                      SizedBox(
                        width: currentSideMenuWidth,
                        child: const SideMenu(),
                      ),
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
                            _buildTabBar(context, activeIndex, tabs),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  );
                                },
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
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTabBar(BuildContext context, int activeIndex, List<HttpRequestTabEntity> tabs) {
    final theme = Theme.of(context);
    final layout = Theme.of(context).extension<AppLayout>()!;

    return Container(
      height: layout.tabBarHeight,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: layout.borderThick)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
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
                  onClose: () => _confirmClose(context, tab.tabId),
                );
              },
            ),
          ),
          AddTabButton(layout: layout),
        ],
      ),
    );
  }
}
