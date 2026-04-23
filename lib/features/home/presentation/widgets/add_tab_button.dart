import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

class AddTabButton extends StatefulWidget {
  final AppLayout layout;

  const AddTabButton({super.key, required this.layout});

  @override
  State<AddTabButton> createState() => _AddTabButtonState();
}

class _AddTabButtonState extends State<AddTabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isHovered ? theme.primaryColor : theme.scaffoldBackgroundColor,
          border: Border(left: BorderSide(color: theme.dividerColor, width: widget.layout.borderThick)),
        ),
        child: context.appDecoration.wrapInteractive(
          child: IconButton(
            icon: Icon(Icons.add, size: widget.layout.addIconSize, color: theme.colorScheme.onSurface),
            onPressed: () => context.read<TabsBloc>().add(const AddTab()),
          ),
        ),
      ),
    );
  }
}
