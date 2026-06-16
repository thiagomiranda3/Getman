import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/core/utils/openapi/collection_builder.dart';
import 'package:getman/core/utils/openapi/import_selection.dart';
import 'package:getman/core/utils/openapi/normalized_api.dart';
import 'package:getman/core/utils/openapi/spec_loader.dart';
import 'package:getman/core/utils/openapi/spec_normalizer.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';

/// Where the spec text comes from: a picked file, a pasted string, or a remote
/// URL fetched via [NetworkService].
enum _Source { file, paste, url }

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

  _Source _source = _Source.file;
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

  void _setSource(_Source source) {
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
              _SourceSelector(source: _source, onChanged: _setSource),
              SizedBox(height: layout.sectionSpacing),
              _buildSourceInput(context),
              if (_error != null) ...[
                SizedBox(height: layout.tabSpacing),
                _ErrorText(message: _error!),
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
                  child: _ImportPreview(
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
      case _Source.file:
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.file_open),
            label: const Text('PICK FILE'),
          ),
        );
      case _Source.paste:
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
      case _Source.url:
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

/// The FILE / PASTE / URL segmented control.
class _SourceSelector extends StatelessWidget {
  const _SourceSelector({required this.source, required this.onChanged});

  final _Source source;
  final ValueChanged<_Source> onChanged;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Row(
      children: [
        for (final entry in const {
          _Source.file: 'FILE',
          _Source.paste: 'PASTE',
          _Source.url: 'URL',
        }.entries) ...[
          if (entry.key != _Source.file) SizedBox(width: layout.tabSpacing),
          Expanded(
            child: _SourceButton(
              label: entry.value,
              selected: source == entry.key,
              onTap: () => onChanged(entry.key),
            ),
          ),
        ],
      ],
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return context.appDecoration.wrapInteractive(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: layout.buttonPaddingVertical),
        decoration: BoxDecoration(
          color: selected ? theme.primaryColor : theme.colorScheme.surface,
          border: Border.all(
            color: theme.dividerColor,
            width: layout.borderThick,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            fontWeight: context.appTypography.displayWeight,
            fontSize: layout.fontSizeNormal,
          ),
        ),
      ),
    );
  }
}

/// The selectable preview: folder rows (tristate group checkbox) with their
/// indented request leaves, plus an environment summary and warnings.
class _ImportPreview extends StatelessWidget {
  const _ImportPreview({
    required this.result,
    required this.selected,
    required this.onToggleFolder,
    required this.onToggleLeaf,
  });

  final ImportResult result;
  final Set<String> selected;
  final void Function(CollectionNodeEntity folder, {required bool select})
  onToggleFolder;
  final void Function(String id, {required bool select}) onToggleLeaf;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final palette = context.appPalette;
    final typography = context.appTypography;
    final theme = Theme.of(context);

    final environments = result.environments;
    final envLabel = environments.isEmpty
        ? 'Creates no environments.'
        : 'Creates ${environments.length} environment(s): '
              '${environments.map((e) => e.name).join(', ')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in result.root.children) ...[
          if (child.isFolder)
            _FolderRow(
              folder: child,
              selected: selected,
              onToggleFolder: onToggleFolder,
              onToggleLeaf: onToggleLeaf,
            )
          else
            _LeafRow(
              leaf: child,
              selected: selected.contains(child.id),
              onChanged: (value) =>
                  onToggleLeaf(child.id, select: value ?? false),
            ),
        ],
        SizedBox(height: layout.sectionSpacing),
        Text(
          envLabel,
          style: TextStyle(
            fontSize: layout.fontSizeNormal,
            fontWeight: typography.bodyWeight,
            color: theme.colorScheme.onSurface,
          ),
        ),
        for (final warning in result.warnings) ...[
          SizedBox(height: layout.tabSpacing),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: layout.smallIconSize,
                color: palette.statusWarning,
              ),
              SizedBox(width: layout.tabSpacing),
              Expanded(
                child: Text(
                  warning,
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    fontWeight: typography.bodyWeight,
                    color: palette.statusWarning,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.selected,
    required this.onToggleFolder,
    required this.onToggleLeaf,
  });

  final CollectionNodeEntity folder;
  final Set<String> selected;
  final void Function(CollectionNodeEntity folder, {required bool select})
  onToggleFolder;
  final void Function(String id, {required bool select}) onToggleLeaf;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final theme = Theme.of(context);

    final leaves = folder.children.where((c) => !c.isFolder).toList();
    final selectedCount = leaves.where((l) => selected.contains(l.id)).length;
    final value = selectedCount == 0
        ? false
        : (selectedCount == leaves.length ? true : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Checkbox(
              tristate: true,
              value: value,
              onChanged: (_) => onToggleFolder(folder, select: value != true),
            ),
            Expanded(
              child: Text(
                folder.name,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: typography.titleWeight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        for (final leaf in leaves)
          Padding(
            padding: EdgeInsets.only(left: layout.depthPaddingMultiplier),
            child: _LeafRow(
              leaf: leaf,
              selected: selected.contains(leaf.id),
              onChanged: (v) => onToggleLeaf(leaf.id, select: v ?? false),
            ),
          ),
      ],
    );
  }
}

class _LeafRow extends StatelessWidget {
  const _LeafRow({
    required this.leaf,
    required this.selected,
    required this.onChanged,
  });

  final CollectionNodeEntity leaf;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final theme = Theme.of(context);
    final method = leaf.config?.method ?? 'GET';

    return Row(
      children: [
        Checkbox(value: selected, onChanged: onChanged),
        MethodBadge(method: method, small: true),
        SizedBox(width: layout.tabSpacing),
        Expanded(
          child: Text(
            leaf.name,
            style: TextStyle(
              fontSize: layout.fontSizeNormal,
              fontWeight: typography.bodyWeight,
              color: theme.colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    return Text(
      message,
      style: TextStyle(
        fontSize: layout.fontSizeSmall,
        fontWeight: context.appTypography.bodyWeight,
        color: theme.colorScheme.error,
      ),
    );
  }
}
