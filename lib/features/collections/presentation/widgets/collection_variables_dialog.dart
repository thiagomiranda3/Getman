import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';

/// Editor for a folder's collection-scoped variables (with per-row secret
/// toggles). Local state is committed on SAVE via [UpdateNodeVariables].
class CollectionVariablesDialog extends StatefulWidget {
  const CollectionVariablesDialog({required this.node, super.key});
  final CollectionNodeEntity node;

  static Future<void> show(BuildContext context, CollectionNodeEntity node) {
    final collectionsBloc = context.read<CollectionsBloc>();
    return showResponsiveDialog<void>(
      context,
      builder: (dialogContext) => BlocProvider<CollectionsBloc>.value(
        value: collectionsBloc,
        child: CollectionVariablesDialog(node: node),
      ),
    );
  }

  @override
  State<CollectionVariablesDialog> createState() =>
      _CollectionVariablesDialogState();
}

class _CollectionVariablesDialogState extends State<CollectionVariablesDialog> {
  late Map<String, String> _variables;
  late Set<String> _secretKeys;

  @override
  void initState() {
    super.initState();
    _variables = Map<String, String>.from(widget.node.variables);
    _secretKeys = Set<String>.from(widget.node.secretKeys);
  }

  void _save() {
    final bloc = context.read<CollectionsBloc>();
    Navigator.pop(context);
    bloc.add(
      UpdateNodeVariables(
        widget.node.id,
        _variables,
        // Never persist secret flags for variables that no longer exist.
        _secretKeys.intersection(_variables.keys.toSet()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: Text('VARIABLES — ${widget.node.name}'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: KeyValueListEditor<Map<String, String>>(
          items: _variables,
          fieldPrefix: 'collection_var',
          decode: (variables) => [
            for (final e in variables.entries) (e.key, e.value),
          ],
          encode: (rows) => {
            for (final (key, value) in rows)
              if (key.trim().isNotEmpty) key.trim(): value,
          },
          equals: stringMapEquality.equals,
          secretKeys: _secretKeys,
          onSecretKeysChanged: (keys) => setState(() => _secretKeys = keys),
          onChanged: (variables) => setState(() {
            _variables = variables;
            _secretKeys = _secretKeys.intersection(variables.keys.toSet());
          }),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        TextButton(onPressed: _save, child: const Text('SAVE')),
      ],
    );
  }
}
