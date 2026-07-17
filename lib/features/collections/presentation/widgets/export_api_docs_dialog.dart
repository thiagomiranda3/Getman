// Dialog to export a collection node as API docs: OpenAPI 3.0.3
// (JSON/YAML) or Markdown, resolved against an optional environment for
// variable substitution. `buildExport` is a pure, unit-testable
// build+serialize step; the dialog itself only picks format/environment
// and saves the file via saveTextFileWithFeedback.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/apidoc/collection_to_api_doc.dart';
import 'package:getman/core/utils/apidoc/markdown_doc_serializer.dart';
import 'package:getman/core/utils/apidoc/openapi_serializer.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';

enum ExportDocFormat { openApiJson, openApiYaml, markdown }

/// Pure build+serialize step (no picker / context) so it is unit-testable.
@visibleForTesting
({String content, String fileName, List<String> ext, List<String> warnings})
buildExport(
  CollectionNodeEntity node,
  EnvironmentEntity? env,
  ExportDocFormat format,
) {
  final doc = CollectionToApiDoc.build(node, env: env);
  final slug = slugFilename(node.name);
  switch (format) {
    case ExportDocFormat.openApiJson:
      return (
        content: OpenApiSerializer.toJson(doc),
        fileName: '$slug.openapi.json',
        ext: const ['json'],
        warnings: doc.warnings,
      );
    case ExportDocFormat.openApiYaml:
      return (
        content: OpenApiSerializer.toYaml(doc),
        fileName: '$slug.openapi.yaml',
        ext: const ['yaml'],
        warnings: doc.warnings,
      );
    case ExportDocFormat.markdown:
      return (
        content: MarkdownDocSerializer.toMarkdown(doc),
        fileName: '$slug.md',
        ext: const ['md'],
        warnings: doc.warnings,
      );
  }
}

class ExportApiDocsDialog extends StatefulWidget {
  const ExportApiDocsDialog({required this.node, super.key});
  final CollectionNodeEntity node;

  static Future<void> show(BuildContext context, CollectionNodeEntity node) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<EnvironmentsBloc>(),
        child: BlocProvider.value(
          value: context.read<SettingsBloc>(),
          child: ExportApiDocsDialog(node: node),
        ),
      ),
    );
  }

  @override
  State<ExportApiDocsDialog> createState() => _ExportApiDocsDialogState();
}

class _ExportApiDocsDialogState extends State<ExportApiDocsDialog> {
  ExportDocFormat _format = ExportDocFormat.openApiJson;
  String? _envId; // null = No Environment
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final envs = context.watch<EnvironmentsBloc>().state.environments;
    final settings = context.watch<SettingsBloc>().state.settings;

    if (!_seeded) {
      final active = settings.activeEnvironmentId;
      _envId = envs.any((e) => e.id == active) ? active : null;
      _seeded = true;
    }

    return ResponsiveDialogScaffold(
      title: const Text('EXPORT AS API DOCS'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FORMAT',
            style: TextStyle(fontWeight: context.appTypography.titleWeight),
          ),
          RadioGroup<ExportDocFormat>(
            groupValue: _format,
            onChanged: (v) {
              if (v != null) setState(() => _format = v);
            },
            // A transparency Material gives the radio rows their own ink
            // surface. Under the glass theme the dialog wraps its content in a
            // frosted card (a colored DecoratedBox); Flutter 3.44 asserts when
            // a (Radio)ListTile's nearest background ancestor is that colored
            // box rather than a Material.
            child: const Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  RadioListTile<ExportDocFormat>(
                    key: ValueKey('fmt_openapi_json'),
                    value: ExportDocFormat.openApiJson,
                    title: Text('OpenAPI 3.0.3 (JSON)'),
                  ),
                  RadioListTile<ExportDocFormat>(
                    key: ValueKey('fmt_openapi_yaml'),
                    value: ExportDocFormat.openApiYaml,
                    title: Text('OpenAPI 3.0.3 (YAML)'),
                  ),
                  RadioListTile<ExportDocFormat>(
                    key: ValueKey('fmt_markdown'),
                    value: ExportDocFormat.markdown,
                    title: Text('Markdown'),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: layout.tabSpacing),
          Text(
            'ENVIRONMENT',
            style: TextStyle(fontWeight: context.appTypography.titleWeight),
          ),
          DropdownButton<String?>(
            key: const ValueKey('export_env_dropdown'),
            isExpanded: true,
            value: _envId,
            items: [
              const DropdownMenuItem<String?>(
                child: Text('No Environment'),
              ),
              for (final e in envs)
                DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
            ],
            onChanged: (v) => setState(() => _envId = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        TextButton(
          key: const ValueKey('export_confirm'),
          onPressed: () => _export(context, envs),
          child: const Text('EXPORT'),
        ),
      ],
    );
  }

  Future<void> _export(
    BuildContext context,
    List<EnvironmentEntity> envs,
  ) async {
    final env = _envId == null ? null : envs.firstWhere((e) => e.id == _envId);
    final out = buildExport(widget.node, env, _format);
    // Capture before the first await so we don't touch context afterwards.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Save first (context still mounted; the picker is a native modal), then
    // pop. saveTextFileWithFeedback captures its own messenger before awaiting.
    await saveTextFileWithFeedback(
      context,
      content: out.content,
      fileName: out.fileName,
      dialogTitle: 'EXPORT AS API DOCS',
      allowedExtensions: out.ext,
    );
    if (out.warnings.isNotEmpty && messenger != null) {
      showAppSnackBarVia(messenger, out.warnings.first);
    }
    navigator.pop();
  }
}
