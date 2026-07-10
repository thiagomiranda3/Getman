import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/collections/presentation/widgets/review_changes_dialog.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

/// Header action that opens the Review Changes dialog. Hidden when no
/// workspace path is configured.
class ReviewChangesButton extends StatelessWidget {
  const ReviewChangesButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, n) => p.settings.workspacePath != n.settings.workspacePath,
      builder: (context, state) {
        final root = state.settings.workspacePath;
        if (root == null) return const SizedBox.shrink();
        return context.appDecoration.wrapInteractive(
          child: IconButton(
            key: const ValueKey('review_changes_button'),
            tooltip: 'Review changes',
            icon: Icon(Icons.rule, size: context.appLayout.iconSize),
            onPressed: () => ReviewChangesDialog.show(context, root: root),
          ),
        );
      },
    );
  }
}
