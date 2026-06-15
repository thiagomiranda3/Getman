import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/tab_switcher_sheet.dart';

/// Compact tab indicator for narrow layouts: shows "active/total" + the active
/// tab title, and opens the [TabSwitcherSheet] on tap.
class TabChip extends StatelessWidget {
  const TabChip({required this.onRequestClose, super.key});
  final Future<bool> Function(BuildContext, String) onRequestClose;

  static HttpRequestTabEntity? _activeTab(TabsState state) =>
      (state.activeIndex >= 0 && state.activeIndex < state.tabs.length)
      ? state.tabs[state.activeIndex]
      : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocBuilder<TabsBloc, TabsState>(
      // Subscribes on its own (the shell gates out per-tab changes) so the
      // chip title tracks the URL while the user types.
      buildWhen: (prev, next) =>
          prev.activeIndex != next.activeIndex ||
          prev.tabs.length != next.tabs.length ||
          _activeTab(prev)?.displayTitle != _activeTab(next)?.displayTitle,
      builder: (context, state) {
        final tabs = state.tabs;
        final activeIndex = state.activeIndex;
        final title = _activeTab(state)?.displayTitle ?? 'NO TABS';

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    border: Border.all(
                      color: theme.dividerColor,
                      width: layout.borderThin,
                    ),
                    borderRadius: BorderRadius.circular(
                      context.appShape.panelRadius,
                    ),
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
      },
    );
  }
}
