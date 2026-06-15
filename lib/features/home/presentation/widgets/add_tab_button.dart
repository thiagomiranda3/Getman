import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/hover_highlight.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

class AddTabButton extends StatelessWidget {
  const AddTabButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return HoverHighlight(
      decoration: (hovered) => BoxDecoration(
        color: hovered ? theme.primaryColor : theme.scaffoldBackgroundColor,
        border: Border(
          left: BorderSide(
            color: theme.dividerColor,
            width: layout.borderThick,
          ),
        ),
      ),
      child: context.appDecoration.wrapInteractive(
        child: IconButton(
          icon: Icon(
            Icons.add,
            size: layout.addIconSize,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () => context.read<TabsBloc>().add(const AddTab()),
        ),
      ),
    );
  }
}
