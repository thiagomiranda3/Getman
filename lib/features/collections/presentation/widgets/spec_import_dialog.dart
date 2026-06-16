import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/core/utils/openapi/collection_builder.dart';
import 'package:getman/core/utils/openapi/import_selection.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/openapi/spec_loader.dart';
import 'package:getman/core/utils/openapi/spec_normalizer.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/widgets/spec_import_preview.dart';
import 'package:getman/features/collections/presentation/widgets/spec_import_source.dart';

/// Multi-step importer for OpenAPI 3.x / Swagger 2.0 specs (JSON or YAML).
///
/// Step 1 picks a source (file / paste / URL) and parses the spec; step 2 shows
/// a selectable preview of the resulting collection tree plus an environment
/// summary, and commits the (pruned) [ImportResult] via [onImport].
///
/// Bloc-agnostic by design: the caller wires the blocs and reads the
/// [NetworkService]; this widget only needs the service (for URL fetch) and a
/// plain callback (see plan "Design decisions locked in" #5).
class SpecImportDialog extends StatefulWidget {
  const SpecImportDialog({
    required this.networkService,
    required this.onImport,
    super.key,
  });

  /// Used only by the URL source; `null` disables remote fetch.
  final NetworkService? networkService;

  /// Receives the final, selection-pruned [ImportResult] on Import.
  final void Function(ImportResult) onImport;

  /// Opens the importer as a responsive dialog (centered modal or full-screen).
  static Future<void> show(
    BuildContext context, {
    required NetworkService? networkService,
    required void Function(ImportResult) onImport,
  }) {
    return showResponsiveDialog<void>(
      context,
      builder: (_) => SpecImportDialog(
        networkService: networkService,
        onImport: onImport,
      ),
    );
  }

  @override
  State<SpecImportDialog> createState() => _SpecImportDialogState();
}

class _SpecImportDialogState extends State<SpecImportDialog> {
  final TextEditingController _pasteController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  SpecImportSource _source = SpecImportSource.file;
  ImportResult? _result;
  Set<String> _selected = <String>{};
  String? _error;
  bool _fetching = false;

  @override
  void dispose() {
    _pasteController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _parse(String text) {
    try {
      final api = normalizeSpec(loadSpec(text));
      setState(() {
        _result = buildImport(api);
        _selected = collectLeafIds(_result!.root);
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'yaml', 'yml'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final content = await readPickedFile(result.files.first);
      if (content == null) {
        setState(() => _error = 'Unable to read the selected file.');
        return;
      }
      _parse(content);
    } on Object catch (e) {
      setState(() => _error = 'File import failed: $e');
    }
  }

  Future<void> _fetchUrl() async {
    final service = widget.networkService;
    if (service == null) {
      setState(() => _error = 'Remote fetch is unavailable.');
      return;
    }
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Enter a URL to fetch.');
      return;
    }
    setState(() => _fetching = true);
    try {
      final response = await service.request(url: url, method: 'GET');
      _parse(response.body);
    } on Object catch (e) {
      setState(() => _error = 'Fetch failed: $e');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _setSource(SpecImportSource source) {
    if (source == _source) return;
    setState(() => _source = source);
  }

  /// Toggles every leaf id under [folder] on/off as a group.
  void _toggleFolder(CollectionNodeEntity folder, {required bool select}) {
    final ids = collectLeafIds(folder);
    setState(() {
      if (select) {
        _selected = {..._selected, ...ids};
      } else {
        _selected = {..._selected}..removeAll(ids);
      }
    });
  }

  void _toggleLeaf(String id, {required bool select}) {
    setState(() {
      _selected = {..._selected};
      if (select) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  void _import() {
    final result = _result;
    if (result == null || _selected.isEmpty || !mounted) return;
    Navigator.pop(context);
    widget.onImport(applySelection(result, _selected));
  }

  void _reset() {
    setState(() {
      _result = null;
      _selected = <String>{};
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final result = _result;
    return ResponsiveDialogScaffold(
      title: const Text('IMPORT API SPEC'),
      content: SizedBox(
        width: layout.dialogWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Before a successful parse, show the full source picker + input.
            // Afterwards, collapse to a compact "re-parse" row so the
            // selectable preview is the primary content.
            if (result == null) ...[
              SpecImportSourceSelector(source: _source, onChanged: _setSource),
              SizedBox(height: layout.sectionSpacing),
              _buildSourceInput(context),
              if (_error != null) ...[
                SizedBox(height: layout.tabSpacing),
                SpecImportErrorText(message: _error!),
              ],
            ] else ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('LOAD ANOTHER'),
                ),
              ),
              SizedBox(height: layout.tabSpacing),
              Flexible(
                child: SingleChildScrollView(
                  child: SpecImportPreview(
                    result: result,
                    selected: _selected,
                    onToggleFolder: _toggleFolder,
                    onToggleLeaf: _toggleLeaf,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: _selected.isEmpty ? null : _import,
          child: const Text('IMPORT'),
        ),
      ],
    );
  }

  Widget _buildSourceInput(BuildContext context) {
    switch (_source) {
      case SpecImportSource.file:
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.file_open),
            label: const Text('PICK FILE'),
          ),
        );
      case SpecImportSource.paste:
        final layout = context.appLayout;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pasteController,
              minLines: 6,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'Paste an OpenAPI / Swagger spec (JSON or YAML)',
              ),
            ),
            SizedBox(height: layout.tabSpacing),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _parse(_pasteController.text),
                child: const Text('PARSE'),
              ),
            ),
          ],
        );
      case SpecImportSource.url:
        final layout = context.appLayout;
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: 'https://example.com/openapi.json',
                ),
                onSubmitted: (_) => _fetchUrl(),
              ),
            ),
            SizedBox(width: layout.tabSpacing),
            TextButton(
              onPressed: _fetching ? null : _fetchUrl,
              child: const Text('FETCH'),
            ),
          ],
        );
    }
  }
}
