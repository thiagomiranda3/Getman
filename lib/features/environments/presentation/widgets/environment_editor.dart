import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';

/// Detail editor for a single environment: name field + a key/value variable
/// editor with per-variable secret toggles. Emits UpdateEnvironment on change.
class EnvironmentEditor extends StatefulWidget {
  const EnvironmentEditor({required this.environment, super.key});
  final EnvironmentEntity environment;

  @override
  State<EnvironmentEditor> createState() => _EnvironmentEditorState();
}

class _EnvironmentEditorState extends State<EnvironmentEditor> {
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

  void _emit({Map<String, String>? variables, Set<String>? secretKeys}) {
    context.read<EnvironmentsBloc>().add(
      UpdateEnvironment(
        widget.environment.copyWith(
          name: _nameController.text,
          variables: variables ?? widget.environment.variables,
          secretKeys: secretKeys ?? widget.environment.secretKeys,
        ),
      ),
    );
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
          style: TextStyle(
            fontSize: layout.fontSizeTitle,
            fontWeight: context.appTypography.titleWeight,
          ),
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
            decode: (variables) => [
              for (final e in variables.entries) (e.key, e.value),
            ],
            encode: (rows) => {
              for (final (key, value) in rows)
                if (key.trim().isNotEmpty) key.trim(): value,
            },
            equals: stringMapEquality.equals,
            secretKeys: widget.environment.secretKeys,
            onSecretKeysChanged: (keys) => _emit(secretKeys: keys),
            // Drop secret flags for variables that no longer exist (e.g. a
            // renamed or deleted key) so the set never drifts from the map.
            onChanged: (variables) => _emit(
              variables: variables,
              secretKeys: widget.environment.secretKeys.intersection(
                variables.keys.toSet(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
