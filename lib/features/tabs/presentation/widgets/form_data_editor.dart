import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// Editor for `urlencoded` / `multipart` form bodies. Backs the list of
/// [MultipartFieldEntity] on `config.formFields`. When [allowFiles] is true
/// (multipart), each row can toggle to a file picker; otherwise (urlencoded)
/// rows are text-only.
///
/// Holds its own row controllers and suppresses echoes of its own emissions
/// (mirrors [KeyValueListEditor]) so typing never loses focus across the bloc
/// round-trip.
class FormDataEditor extends StatefulWidget {
  final String tabId;
  final bool allowFiles;
  const FormDataEditor({super.key, required this.tabId, required this.allowFiles});

  @override
  State<FormDataEditor> createState() => _FormDataEditorState();
}

const ListEquality<MultipartFieldEntity> _fieldListEquality =
    ListEquality<MultipartFieldEntity>();

class _FormDataEditorState extends State<FormDataEditor> {
  late List<_RowState> _rows;
  List<MultipartFieldEntity>? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _initRows(_currentFields());
  }

  List<MultipartFieldEntity> _currentFields() =>
      context.read<TabsBloc>().state.tabs.byId(widget.tabId)?.config.formFields ??
      const [];

  void _initRows(List<MultipartFieldEntity> fields) {
    _rows = [for (final f in fields) _RowState.from(f), _RowState.empty()];
  }

  void _disposeRows() {
    for (final r in _rows) {
      r.dispose();
    }
  }

  @override
  void dispose() {
    _disposeRows();
    super.dispose();
  }

  void _emit() {
    final fields = <MultipartFieldEntity>[
      for (final r in _rows)
        if (r.nameController.text.isNotEmpty) r.toEntity(),
    ];
    _lastEmitted = fields;
    final bloc = context.read<TabsBloc>();
    final tab = bloc.state.tabs.byId(widget.tabId);
    if (tab == null) return;
    bloc.add(UpdateTab(tab.copyWith(config: tab.config.copyWith(formFields: fields))));
  }

  Future<void> _pickFile(_RowState row) async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    if (picked.path == null) {
      if (mounted) {
        showAppSnackBar(context, 'File uploads need the desktop or mobile app.');
      }
      return;
    }
    setState(() {
      row.filePath = picked.path;
      row.fileName = picked.name;
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) => !_fieldListEquality.equals(
        prev.tabs.byId(widget.tabId)?.config.formFields,
        next.tabs.byId(widget.tabId)?.config.formFields,
      ),
      listener: (context, state) {
        final fields = state.tabs.byId(widget.tabId)?.config.formFields ?? const [];
        if (_lastEmitted != null && _fieldListEquality.equals(fields, _lastEmitted)) {
          return;
        }
        setState(() {
          _disposeRows();
          _initRows(fields);
          _lastEmitted = null;
        });
      },
      child: ListView.builder(
        padding: EdgeInsets.all(layout.pagePadding),
        itemCount: _rows.length,
        itemBuilder: (context, index) => _buildRow(context, index),
      ),
    );
  }

  Widget _buildRow(BuildContext context, int index) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final row = _rows[index];
    final textStyle = TextStyle(
      fontSize: layout.fontSizeNormal,
      fontWeight: context.appTypography.titleWeight,
    );
    final fieldPadding = EdgeInsets.all(layout.isCompact ? 8 : 12);

    final nameField = TextField(
      key: ValueKey('name_${row.id}'),
      controller: row.nameController,
      style: textStyle,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(hintText: 'KEY', isDense: true, contentPadding: fieldPadding),
      onChanged: (val) {
        if (index == _rows.length - 1 && val.isNotEmpty) {
          setState(() => _rows.add(_RowState.empty()));
        }
        _emit();
      },
    );

    final Widget valueWidget = row.isFile
        ? _FilePickButton(
            label: row.fileLabel,
            onTap: () => _pickFile(row),
          )
        : TextField(
            key: ValueKey('val_${row.id}'),
            controller: row.valueController,
            style: textStyle,
            autocorrect: false,
            enableSuggestions: false,
            decoration:
                InputDecoration(hintText: 'VALUE', isDense: true, contentPadding: fieldPadding),
            onChanged: (_) => _emit(),
          );

    final children = <Widget>[
      Expanded(child: nameField),
      SizedBox(width: layout.isCompact ? 8 : 12),
      Expanded(child: valueWidget),
    ];

    if (widget.allowFiles) {
      children.add(context.appDecoration.wrapInteractive(
        child: IconButton(
          icon: Icon(
            row.isFile ? Icons.text_fields : Icons.attach_file,
            size: layout.isCompact ? 20 : 24,
            color: theme.colorScheme.onSurface,
          ),
          tooltip: row.isFile ? 'Use a text value' : 'Attach a file',
          onPressed: () {
            setState(() => row.isFile = !row.isFile);
            _emit();
          },
        ),
      ));
    }

    children.add(context.appDecoration.wrapInteractive(
      child: IconButton(
        icon: Icon(Icons.delete_outline, size: layout.isCompact ? 20 : 24, color: theme.colorScheme.error),
        onPressed: () {
          setState(() {
            _rows.removeAt(index).dispose();
            if (_rows.isEmpty) _rows.add(_RowState.empty());
          });
          _emit();
        },
      ),
    ));

    return Padding(
      padding: EdgeInsets.only(bottom: layout.isCompact ? 8.0 : 12.0),
      child: Row(children: children),
    );
  }
}

class _FilePickButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FilePickButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return context.appDecoration.wrapInteractive(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: layout.inputPadding, vertical: layout.inputPaddingVertical),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor, width: layout.borderThin),
          borderRadius: BorderRadius.circular(context.appShape.inputRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file, size: layout.smallIconSize, color: theme.colorScheme.secondary),
            SizedBox(width: layout.tabSpacing),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.titleWeight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-row mutable UI state. [id] keys the row's widgets stably across rebuilds.
class _RowState {
  static int _counter = 0;
  final int id;
  final TextEditingController nameController;
  final TextEditingController valueController;
  bool isFile;
  String? filePath;
  String? fileName;

  _RowState({
    required this.nameController,
    required this.valueController,
    this.isFile = false,
    this.filePath,
    this.fileName,
  }) : id = _counter++;

  factory _RowState.from(MultipartFieldEntity f) => _RowState(
        nameController: TextEditingController(text: f.name),
        valueController: TextEditingController(text: f.value),
        isFile: f.isFile,
        filePath: f.filePath,
        fileName: f.filePath?.split(RegExp(r'[/\\]')).last,
      );

  factory _RowState.empty() => _RowState(
        nameController: TextEditingController(),
        valueController: TextEditingController(),
      );

  String get fileLabel => fileName ?? 'CHOOSE FILE';

  MultipartFieldEntity toEntity() => MultipartFieldEntity(
        name: nameController.text,
        value: isFile ? '' : valueController.text,
        isFile: isFile,
        filePath: isFile ? filePath : null,
      );

  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}
