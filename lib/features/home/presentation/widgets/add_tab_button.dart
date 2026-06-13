import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

class AddTabButton extends StatefulWidget {
  const AddTabButton({super.key});

  @override
  State<AddTabButton> createState() => _AddTabButtonState();
}

class _AddTabButtonState extends State<AddTabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isHovered ? theme.primaryColor : theme.scaffoldBackgroundColor,
          border: Border(left: BorderSide(color: theme.dividerColor, width: layout.borderThick)),
        ),
        child: context.appDecoration.wrapInteractive(
          child: IconButton(
            icon: Icon(Icons.add, size: layout.addIconSize, color: theme.colorScheme.onSurface),
            onPressed: () => context.read<TabsBloc>().add(const AddTab()),
          ),
        ),
      ),
    );
  }
}
