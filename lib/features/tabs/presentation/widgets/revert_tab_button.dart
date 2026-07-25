// Small revert-changes icon beside the URL bar's save button (A4). Visible
// ONLY when the tab is dirty AND linked to a collection node whose saved
// config still exists — that saved config is the TabDirtyChecker baseline and
// rides on the RevertTab event (the bloc holds no collections reference).
// Confirms via ConfirmDialog before dispatching; response + time-travel
// timeline survive the revert (bloc-side guarantee).
//
// Owns its rebuilds: UrlBar's builder deliberately does NOT rebuild on
// url/body edits (perf), so this widget carries its own narrow buildWhen +
// BlocSelector — the same selector shape as RequestTabChip's dirty star.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

class RevertTabButton extends StatelessWidget {
  const RevertTabButton({
    required this.tabId,
    required this.iconSize,
    required this.gap,
    super.key,
  });

  final String tabId;

  /// Sizing comes from the URL bar's layout-derived locals so the icon
  /// matches its neighbors exactly (theme adherence: values originate from
  /// AppLayout in url_bar.dart, never literals here).
  final double iconSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      // Visibility depends only on config + link — never rebuild on response
      // arrival / isSending (mirrors RequestTabChip's buildWhen).
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        if (identical(p, n)) return false;
        if (p == null || n == null) return p != n;
        return p.config != n.config || p.collectionNodeId != n.collectionNodeId;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        final nodeId = tab?.collectionNodeId;
        if (tab == null || nodeId == null) return const SizedBox.shrink();
        return BlocSelector<
          CollectionsBloc,
          CollectionsState,
          HttpRequestConfigEntity?
        >(
          selector: (collState) => collState.configById[nodeId],
          builder: (context, savedConfig) {
            // Same predicate as TabDirtyChecker for a linked tab with a
            // surviving node; a vanished node hides the icon (nothing to
            // revert TO).
            final isDirty = savedConfig != null && tab.config != savedConfig;
            if (!isDirty) return const SizedBox.shrink();
            final theme = Theme.of(context);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                context.appDecoration.wrapInteractive(
                  child: IconButton(
                    key: const ValueKey('revert_tab_button'),
                    icon: Icon(
                      Icons.settings_backup_restore,
                      color: theme.colorScheme.secondary,
                      size: iconSize,
                    ),
                    tooltip: 'Revert Changes',
                    onPressed: () {
                      final tabsBloc = context.read<TabsBloc>();
                      unawaited(
                        ConfirmDialog.show(
                          context,
                          title: 'REVERT CHANGES?',
                          message: 'Discard unsaved changes to this request?',
                          confirmLabel: 'REVERT',
                          onConfirm: () => tabsBloc.add(
                            RevertTab(tabId: tabId, savedConfig: savedConfig),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(width: gap),
              ],
            );
          },
        );
      },
    );
  }
}
