// Detail editor for one environment: name field + KeyValueListEditor for
// variables with per-row secret toggles and B2 reorder/duplicate (duplicate
// key gets a unique '-copy' suffix and inherits the secret flag). Emits
// UpdateEnvironment on edit; blank-name edits are dropped, and losing focus
// reverts an emptied name.
//
// B2.4 order-significance note: the `equals:` handed to KeyValueListEditor is
// order-SIGNIFICANT (`_orderedVariablesEqual`, a key-order ListEquality
// layered on the plain content MapEquality) — mirrors headers_tab_view.dart's
// `_orderedHeadersEqual` fix (commit c66c211). A plain MapEquality doesn't
// care about key order, so didUpdateWidget's first (echo-suppression) branch
// could treat a pure reorder as "already emitted" and skip resyncing row
// controllers from the new order, purely by chance of timing — the second
// branch's `_sameDecodedOrder` layer already guards this independently, but
// this keeps both checks consistent instead of relying on only one of them.
// (EnvironmentsDialog's own `buildWhen` compares raw `List<EnvironmentEntity>`
// with `!=` — identity-based, so it is trivially always-true given the bloc's
// always-fresh lists; no gating bug there, unlike the headers case.)
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';

const ListEquality<String> _stringListEquality = ListEquality<String>();

/// Order-SIGNIFICANT map equality: same key/value content is not enough —
/// the key SEQUENCE must match too. Variable order is user-visible/editable
/// (drag reorder, B2) and `EnvironmentEntity.props` is order-significant
/// (Task 2B.2), so a pure reorder must compare unequal here too.
bool _orderedVariablesEqual(Map<String, String> a, Map<String, String> b) =>
    stringMapEquality.equals(a, b) &&
    _stringListEquality.equals(a.keys.toList(), b.keys.toList());

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

  // B2: position IS the operation for these two — index-based by design.
  // Indices arrive in decoded-row space from KeyValueListEditor and are
  // range-guarded against the persisted map.
  void _reorderVariable(int oldIndex, int newIndex) {
    final entries = widget.environment.variables.entries.toList();
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    final entry = entries.removeAt(oldIndex);
    entries.insert(newIndex.clamp(0, entries.length), entry);
    _emit(variables: Map.fromEntries(entries));
  }

  void _duplicateVariable(int index) {
    final variables = widget.environment.variables;
    final entries = variables.entries.toList();
    if (index < 0 || index >= entries.length) return;
    final source = entries[index];
    // Map keys are unique — suffix the copy until it doesn't collide.
    var key = '${source.key}-copy';
    while (variables.containsKey(key)) {
      // Bounded suffix growth (duplicates are rare, keys stay short) — not
      // the append-in-a-loop shape use_string_buffers targets.
      // ignore: use_string_buffers
      key = '$key-copy';
    }
    entries.insert(index + 1, MapEntry(key, source.value));
    final secrets = widget.environment.secretKeys;
    _emit(
      variables: Map.fromEntries(entries),
      // A copy of a secret variable is itself secret — it must not render
      // unmasked just because it was duplicated.
      secretKeys: secrets.contains(source.key) ? {...secrets, key} : null,
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
            equals: _orderedVariablesEqual,
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
            onReorder: _reorderVariable,
            onDuplicate: _duplicateVariable,
          ),
        ),
      ],
    );
  }
}
