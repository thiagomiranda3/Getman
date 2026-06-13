import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/core/utils/postman/postman_environment_mapper.dart';
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
    return showResponsiveDialog<void>(
      context,
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
    return BlocBuilder<EnvironmentsBloc, EnvironmentsState>(
      buildWhen: (p, n) => p.environments != n.environments,
      builder: (context, state) {
        final environments = state.environments;
        // Reconcile selection with the live list.
        if (_selectedId != null && environments.every((e) => e.id != _selectedId)) {
          _selectedId = null;
        }
        final isFullscreen = context.isDialogFullscreen;
        // Wide: auto-select first so the editor pane shows something.
        // Narrow: start at the list page; don't auto-push to detail.
        if (!isFullscreen) {
          _selectedId ??= environments.isNotEmpty ? environments.first.id : null;
        }
        final selected = environments.firstWhereOrNull((e) => e.id == _selectedId);

        if (isFullscreen) {
          return _buildNarrow(context, environments, selected);
        }
        return _buildWide(context, environments, selected);
      },
    );
  }

  Widget _buildWide(
    BuildContext context,
    List<EnvironmentEntity> environments,
    EnvironmentEntity? selected,
  ) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
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
              child: _listPane(context, environments, onItemTap: (env) => setState(() => _selectedId = env.id)),
            ),
            SizedBox(width: layout.sectionSpacing),
            Expanded(
              child: selected == null
                  ? Center(
                      child: Text(
                        'Select or create an environment',
                        style: TextStyle(
                          fontSize: layout.fontSizeNormal,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : _EnvironmentEditor(key: ValueKey(selected.id), environment: selected),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
      ],
    );
  }

  Widget _buildNarrow(
    BuildContext context,
    List<EnvironmentEntity> environments,
    EnvironmentEntity? selected,
  ) {
    final showDetail = selected != null;
    final theme = Theme.of(context);

    // Intercept system back when a detail page is open so it pops to the list
    // rather than dismissing the whole dialog.
    return PopScope(
      canPop: !showDetail,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (showDetail) setState(() => _selectedId = null);
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(showDetail ? Icons.arrow_back : Icons.close),
            onPressed: () {
              if (showDetail) {
                setState(() => _selectedId = null);
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
          title: Text(showDetail ? selected.name.toUpperCase() : 'ENVIRONMENTS'),
        ),
        body: SafeArea(
          child: showDetail
              ? Padding(
                  padding: EdgeInsets.all(context.appLayout.pagePadding),
                  child: _EnvironmentEditor(key: ValueKey(selected.id), environment: selected),
                )
              : Padding(
                  padding: EdgeInsets.all(context.appLayout.pagePadding),
                  child: _listPane(context, environments, onItemTap: (env) => setState(() => _selectedId = env.id)),
                ),
        ),
      ),
    );
  }

  Widget _listPane(
    BuildContext context,
    List<EnvironmentEntity> environments, {
    required ValueChanged<EnvironmentEntity> onItemTap,
  }) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Column(
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
                icon: Icon(Icons.file_upload, size: layout.iconSize),
                tooltip: 'IMPORT FROM POSTMAN',
                onPressed: () => _importEnvironments(context),
              ),
            ),
            context.appDecoration.wrapInteractive(
              child: IconButton(
                icon: Icon(Icons.file_download, size: layout.iconSize),
                tooltip: 'EXPORT ALL ENVIRONMENTS',
                onPressed: environments.isEmpty
                    ? null
                    : () => _exportAllEnvironments(context, environments),
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
                        onTap: () => onItemTap(env),
                        onDelete: () => _deleteEnvironment(context, env),
                        onExport: () => _exportEnvironment(context, env),
                      );
                    },
                  ),
          ),
        ),
      ],
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
        // Build the entity here so its id is known before the bloc processes
        // the event — reading bloc.state right after add() would race.
        final environment = EnvironmentEntity(name: name);
        bloc.add(AddEnvironment(environment));
        setState(() => _selectedId = environment.id);
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

  Future<void> _importEnvironments(BuildContext context) {
    final bloc = context.read<EnvironmentsBloc>();
    return importJsonFilesWithFeedback<EnvironmentEntity>(
      context,
      parse: PostmanEnvironmentMapper.fromJson,
      onImported: (imported) {
        bloc.add(ImportEnvironments(imported));
        if (mounted) setState(() => _selectedId = imported.first.id);
      },
      noun: 'environment',
    );
  }

  Future<void> _exportEnvironment(BuildContext context, EnvironmentEntity env) {
    return saveJsonFileWithFeedback(
      context,
      jsonString: PostmanEnvironmentMapper.toJson(env),
      fileName: '${slugFilename(env.name)}.postman_environment.json',
      dialogTitle: 'EXPORT ENVIRONMENT',
    );
  }

  Future<void> _exportAllEnvironments(BuildContext context, List<EnvironmentEntity> envs) {
    return saveJsonFileWithFeedback(
      context,
      jsonString: PostmanEnvironmentMapper.toJsonAll(envs),
      fileName: 'environments.postman_environments.json',
      dialogTitle: 'EXPORT ALL ENVIRONMENTS',
    );
  }
}

class _EnvironmentListTile extends StatelessWidget {
  final EnvironmentEntity environment;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  const _EnvironmentListTile({
    required this.environment,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onExport,
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
                  icon: Icon(Icons.file_download, color: theme.colorScheme.onSurface),
                  tooltip: 'Export environment',
                  onPressed: onExport,
                ),
                SizedBox(width: layout.tabSpacing),
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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.environment.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _emit({Map<String, String>? variables}) {
    context.read<EnvironmentsBloc>().add(UpdateEnvironment(
      widget.environment.copyWith(
        name: _nameController.text,
        variables: variables ?? widget.environment.variables,
      ),
    ));
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
        Text(
          'VARIABLES',
          style: TextStyle(
            fontSize: layout.fontSizeNormal,
            fontWeight: context.appTypography.titleWeight,
            color: theme.colorScheme.onSurface,
          ),
        ),
        SizedBox(height: layout.tabSpacing),
        Expanded(
          child: KeyValueListEditor<Map<String, String>>(
            items: widget.environment.variables,
            decode: (variables) => [for (final e in variables.entries) (e.key, e.value)],
            encode: (rows) => {
              for (final (key, value) in rows)
                if (key.trim().isNotEmpty) key.trim(): value,
            },
            equals: stringMapEquality.equals,
            onChanged: (variables) => _emit(variables: variables),
          ),
        ),
      ],
    );
  }
}
