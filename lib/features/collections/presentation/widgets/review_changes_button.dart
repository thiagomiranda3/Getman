// Header action that opens the Review Changes dialog, badged with the
// count of uncommitted workspace changes. Refreshes on
// WorkspaceSyncService.mirrored (the debounced Hive -> disk write) and on
// workspace-path changes. With no workspace connected, routes to the
// WORKSPACE settings pane instead of a dead disabled button. Absent on web.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/review_event.dart';
import 'package:getman/features/collections/presentation/bloc/review_state.dart';
import 'package:getman/features/collections/presentation/widgets/review_changes_dialog.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/settings/presentation/widgets/settings_dialog.dart';

/// Header action that opens the Review Changes dialog, badged with the number
/// of uncommitted workspace changes.
///
/// With no workspace folder connected the review has nothing to diff, so the
/// button routes to the WORKSPACE settings pane instead of dead-ending as a
/// disabled control. Absent on web, where there is no workspace folder and no
/// git.
class ReviewChangesButton extends StatefulWidget {
  const ReviewChangesButton({super.key});

  @override
  State<ReviewChangesButton> createState() => _ReviewChangesButtonState();
}

class _ReviewChangesButtonState extends State<ReviewChangesButton> {
  StreamSubscription<String>? _mirrorSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    // The badge count reads the mirrored files, so it can only be refreshed
    // once the debounced Hive → disk write has actually landed.
    _mirrorSub = context.read<WorkspaceSyncService>().mirrored.listen(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final root = context.read<SettingsBloc>().state.settings.workspacePath;
      if (root != null && root.isNotEmpty) _refresh(root);
    });
  }

  @override
  void dispose() {
    unawaited(_mirrorSub?.cancel());
    super.dispose();
  }

  void _refresh(String root) {
    if (!mounted) return;
    context.read<ReviewBloc>().add(LoadReview(root));
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

    return BlocListener<SettingsBloc, SettingsState>(
      listenWhen: (p, n) =>
          p.settings.workspacePath != n.settings.workspacePath,
      listener: (context, state) {
        final root = state.settings.workspacePath;
        if (root != null && root.isNotEmpty) _refresh(root);
      },
      child: BlocBuilder<SettingsBloc, SettingsState>(
        buildWhen: (p, n) =>
            p.settings.workspacePath != n.settings.workspacePath,
        builder: (context, settingsState) {
          final root = settingsState.settings.workspacePath;
          final connected = root != null && root.isNotEmpty;
          return BlocBuilder<ReviewBloc, ReviewState>(
            buildWhen: (p, n) => p.entries.length != n.entries.length,
            builder: (context, review) {
              final count = connected ? review.entries.length : 0;
              return context.appDecoration.wrapInteractive(
                child: Badge.count(
                  count: count,
                  isLabelVisible: count > 0,
                  child: IconButton(
                    key: const ValueKey('review_changes_button'),
                    tooltip: connected
                        ? 'Review changes'
                        : 'Connect a workspace folder to review changes',
                    icon: Icon(
                      Icons.rule,
                      size: context.appLayout.iconSize,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: () => connected
                        ? ReviewChangesDialog.show(context, root: root)
                        : SettingsDialog.show(
                            context,
                            initialTab: SettingsTab.workspace,
                          ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
