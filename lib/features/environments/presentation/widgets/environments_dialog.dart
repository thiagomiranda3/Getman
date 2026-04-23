import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
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
        final selected = _selectedId == null
            ? null
            : environments.firstWhere(
                (e) => e.id == _selectedId,
                orElse: () => EnvironmentEntity(id: '__none__', name: ''),
              );

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
              child: selected == null || selected.id == '__none__'
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
    final showDetail = selected != null && selected.id != '__none__';
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

  Future<void> _importEnvironments(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final bloc = context.read<EnvironmentsBloc>();
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } catch (e) {
      debugPrint('File picker failed: $e');
      messenger?.showSnackBar(SnackBar(content: Text('Import failed: $e')));
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final imported = <EnvironmentEntity>[];
    final failures = <String>[];
    for (final file in result.files) {
      try {
        final content = await _readFileContent(file);
        if (content == null) {
          failures.add('${file.name}: unable to read file');
          continue;
        }
        imported.addAll(PostmanEnvironmentMapper.fromJson(content));
      } catch (e) {
        failures.add('${file.name}: $e');
      }
    }

    if (imported.isNotEmpty) {
      bloc.add(ImportEnvironments(imported));
      setState(() => _selectedId = imported.first.id);
    }
    if (failures.isNotEmpty) {
      messenger?.showSnackBar(SnackBar(
        content: Text(
          imported.isEmpty
              ? 'Import failed: ${failures.join('; ')}'
              : 'Imported ${imported.length} environment(s). Skipped: ${failures.join('; ')}',
        ),
      ));
    } else if (imported.isNotEmpty) {
      messenger?.showSnackBar(SnackBar(
        content: Text('Imported ${imported.length} environment(s).'),
      ));
    }
  }

  Future<void> _exportEnvironment(BuildContext context, EnvironmentEntity env) async {
    await _saveJsonFile(
      context: context,
      jsonString: PostmanEnvironmentMapper.toJson(env),
      fileName: '${_slugFilename(env.name)}.postman_environment.json',
      dialogTitle: 'EXPORT ENVIRONMENT',
    );
  }

  Future<void> _exportAllEnvironments(BuildContext context, List<EnvironmentEntity> envs) async {
    await _saveJsonFile(
      context: context,
      jsonString: PostmanEnvironmentMapper.toJsonAll(envs),
      fileName: 'environments.postman_environments.json',
      dialogTitle: 'EXPORT ALL ENVIRONMENTS',
    );
  }

  Future<void> _saveJsonFile({
    required BuildContext context,
    required String jsonString,
    required String fileName,
    required String dialogTitle,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(jsonString),
      );
      if (path == null) return;
      if (!kIsWeb) {
        await File(path).writeAsString(jsonString);
      }
      messenger?.showSnackBar(SnackBar(content: Text('Exported to $path')));
    } catch (e) {
      debugPrint('Export failed: $e');
      messenger?.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<String?> _readFileContent(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes != null) return utf8.decode(bytes);
    final path = file.path;
    if (path != null) return File(path).readAsString();
    return null;
  }
}

String _slugFilename(String name) {
  final trimmed = name.trim().toLowerCase();
  final slug = trimmed.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? 'untitled' : slug;
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
