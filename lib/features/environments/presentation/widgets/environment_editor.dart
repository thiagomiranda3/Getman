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
  late final FocusNode _nameFocus;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.environment.name);
    _nameFocus = FocusNode()..addListener(_onNameFocusChange);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // Creation forbids empty names (via NamePromptDialog) — renaming to blank
  // must not persist a blank row either, so a purely-whitespace value is
  // never dispatched.
  void _onNameChanged(String value) {
    if (value.trim().isEmpty) return;
    _emit();
  }

  // Since an empty name is never dispatched, `widget.environment.name` is
  // always the last real persisted name — reverting to it on blur is exactly
  // "undo this abandoned edit", no extra state needed.
  void _onNameFocusChange() {
    if (_nameFocus.hasFocus) return;
    if (_nameController.text.trim().isEmpty) {
      _nameController.text = widget.environment.name;
    }
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
          key: const ValueKey('env_name_field'),
          controller: _nameController,
          focusNode: _nameFocus,
          decoration: const InputDecoration(labelText: 'NAME'),
          style: TextStyle(
            fontSize: layout.fontSizeTitle,
            fontWeight: context.appTypography.titleWeight,
          ),
          onChanged: _onNameChanged,
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
            fieldPrefix: 'env_var',
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
