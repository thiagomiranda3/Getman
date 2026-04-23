import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

class EnvironmentsDialog extends StatefulWidget {
  const EnvironmentsDialog({super.key});

  static Future<void> show(BuildContext context) {
    final envsBloc = context.read<EnvironmentsBloc>();
    final settingsBloc = context.read<SettingsBloc>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: envsBloc),
          BlocProvider.value(value: settingsBloc),
        ],
        child: const EnvironmentsDialog(),
      ),
    );
  }

  @override
  State<EnvironmentsDialog> createState() => _EnvironmentsDialogState();
}

class _EnvironmentsDialogState extends State<EnvironmentsDialog> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return BlocBuilder<EnvironmentsBloc, EnvironmentsState>(
      buildWhen: (p, n) => p.environments != n.environments,
      builder: (context, state) {
        final environments = state.environments;
        if (_selectedId != null && environments.every((e) => e.id != _selectedId)) {
          _selectedId = null;
        }
        _selectedId ??= environments.isNotEmpty ? environments.first.id : null;
        final selected = environments.firstWhere(
          (e) => e.id == _selectedId,
          orElse: () => EnvironmentEntity(id: '__none__', name: ''),
        );

        return AlertDialog(
          title: const Text('ENVIRONMENTS'),
          content: SizedBox(
            width: layout.dialogWidth * 2.2,
            height: 420,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 220,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'LIST',
                              style: TextStyle(
                                fontSize: layout.fontSizeNormal,
                                fontWeight: context.appTypography.titleWeight,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          context.appDecoration.wrapInteractive(
                            child: IconButton(
                              icon: Icon(Icons.add, size: layout.iconSize),
                              tooltip: 'NEW ENVIRONMENT',
                              onPressed: () => _createEnvironment(context),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: layout.tabSpacing),
                      Expanded(
                        child: Container(
                          decoration: context.appDecoration.panelBox(context, offset: 0),
                          child: environments.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(layout.pagePadding),
                                    child: Text(
                                      'No environments yet.\nClick + to create one.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: layout.fontSizeNormal,
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: environments.length,
                                  itemBuilder: (context, index) {
                                    final env = environments[index];
                                    final isSelected = env.id == _selectedId;
                                    return _EnvironmentListTile(
                                      environment: env,
                                      isSelected: isSelected,
                                      onTap: () => setState(() => _selectedId = env.id),
                                      onDelete: () => _deleteEnvironment(context, env),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: layout.sectionSpacing),
                Expanded(
                  child: environments.isEmpty || selected.id == '__none__'
                      ? Center(
                          child: Text(
                            'Select or create an environment',
                            style: TextStyle(
                              fontSize: layout.fontSizeNormal,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        )
                      : _EnvironmentEditor(
                          key: ValueKey(selected.id),
                          environment: selected,
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
          ],
        );
      },
    );
  }

  void _createEnvironment(BuildContext context) {
    final bloc = context.read<EnvironmentsBloc>();
    NamePromptDialog.show(
      context,
      title: 'NEW ENVIRONMENT',
      hintText: 'ENVIRONMENT NAME',
      confirmLabel: 'CREATE',
      onConfirm: (name) {
        bloc.add(AddEnvironment(name));
        final envsAfter = bloc.state.environments;
        if (envsAfter.isNotEmpty) {
          setState(() => _selectedId = envsAfter.last.id);
        }
      },
    );
  }

  void _deleteEnvironment(BuildContext context, EnvironmentEntity env) {
    final envsBloc = context.read<EnvironmentsBloc>();
    final settingsBloc = context.read<SettingsBloc>();
    envsBloc.add(DeleteEnvironment(env.id));
    if (settingsBloc.state.settings.activeEnvironmentId == env.id) {
      settingsBloc.add(const UpdateActiveEnvironmentId(null));
    }
    if (_selectedId == env.id) {
      setState(() => _selectedId = null);
    }
  }
}

class _EnvironmentListTile extends StatelessWidget {
  final EnvironmentEntity environment;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _EnvironmentListTile({
    required this.environment,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, n) => p.settings.activeEnvironmentId != n.settings.activeEnvironmentId,
      builder: (context, settingsState) {
        final isActive = settingsState.settings.activeEnvironmentId == environment.id;
        return InkWell(
          onTap: onTap,
          child: Container(
            color: isSelected ? theme.primaryColor.withValues(alpha: 0.3) : null,
            padding: EdgeInsets.symmetric(
              horizontal: layout.inputPadding,
              vertical: layout.inputPaddingVertical,
            ),
            child: Row(
              children: [
                if (isActive)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.check_circle, size: layout.smallIconSize, color: theme.colorScheme.secondary),
                  ),
                Expanded(
                  child: Text(
                    environment.name,
                    style: TextStyle(
                      fontSize: layout.fontSizeNormal,
                      fontWeight: isActive
                          ? context.appTypography.titleWeight
                          : context.appTypography.bodyWeight,
                      color: theme.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  iconSize: layout.smallIconSize,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                  tooltip: 'Delete environment',
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EnvironmentEditor extends StatefulWidget {
  final EnvironmentEntity environment;
  const _EnvironmentEditor({super.key, required this.environment});

  @override
  State<_EnvironmentEditor> createState() => _EnvironmentEditorState();
}

class _EnvironmentEditorState extends State<_EnvironmentEditor> {
  late final TextEditingController _nameController;
  late final List<TextEditingController> _keyControllers;
  late final List<TextEditingController> _valueControllers;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.environment.name);
    final entries = widget.environment.variables.entries.toList();
    _keyControllers = entries.map((e) => TextEditingController(text: e.key)).toList();
    _valueControllers = entries.map((e) => TextEditingController(text: e.value)).toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _keyControllers) {
      c.dispose();
    }
    for (final c in _valueControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final variables = <String, String>{};
    for (int i = 0; i < _keyControllers.length; i++) {
      final key = _keyControllers[i].text.trim();
      if (key.isEmpty) continue;
      variables[key] = _valueControllers[i].text;
    }
    context.read<EnvironmentsBloc>().add(UpdateEnvironment(
      widget.environment.copyWith(
        name: _nameController.text,
        variables: variables,
      ),
    ));
  }

  void _addRow() {
    setState(() {
      _keyControllers.add(TextEditingController());
      _valueControllers.add(TextEditingController());
    });
  }

  void _removeRow(int index) {
    setState(() {
      _keyControllers.removeAt(index).dispose();
      _valueControllers.removeAt(index).dispose();
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'NAME'),
          style: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: context.appTypography.titleWeight),
          onChanged: (_) => _emit(),
        ),
        SizedBox(height: layout.sectionSpacing),
        Row(
          children: [
            Expanded(
              child: Text(
                'VARIABLES',
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.titleWeight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            context.appDecoration.wrapInteractive(
              child: IconButton(
                icon: Icon(Icons.add, size: layout.iconSize),
                tooltip: 'ADD VARIABLE',
                onPressed: _addRow,
              ),
            ),
          ],
        ),
        SizedBox(height: layout.tabSpacing),
        Expanded(
          child: _keyControllers.isEmpty
              ? Center(
                  child: Text(
                    'No variables. Click + to add one.',
                    style: TextStyle(
                      fontSize: layout.fontSizeNormal,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _keyControllers.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: layout.tabSpacing),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _keyControllers[index],
                              decoration: const InputDecoration(hintText: 'key'),
                              onChanged: (_) => _emit(),
                            ),
                          ),
                          SizedBox(width: layout.tabSpacing),
                          Expanded(
                            child: TextField(
                              controller: _valueControllers[index],
                              decoration: const InputDecoration(hintText: 'value'),
                              onChanged: (_) => _emit(),
                            ),
                          ),
                          SizedBox(width: layout.tabSpacing),
                          IconButton(
                            iconSize: layout.smallIconSize,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                            tooltip: 'Remove',
                            onPressed: () => _removeRow(index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
