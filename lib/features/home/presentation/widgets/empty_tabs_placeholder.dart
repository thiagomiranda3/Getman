import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

/// Empty-state shown in the content area when no tabs are open: a hint + a
/// "NEW REQUEST" button.
class EmptyTabsPlaceholder extends StatelessWidget {
  const EmptyTabsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bolt,
            size: 64,
            color: theme.dividerColor.withValues(alpha: 0.3),
          ),
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
                padding: EdgeInsets.symmetric(
                  horizontal: context.appLayout.buttonPaddingHorizontal,
                  vertical: context.appLayout.buttonPaddingVertical,
                ),
              ),
              child: const Text('NEW REQUEST'),
            ),
          ),
        ],
      ),
    );
  }
}
