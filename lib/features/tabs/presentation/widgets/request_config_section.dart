import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';

const ListEquality<QueryParamEntity> _queryParamListEquality =
    ListEquality<QueryParamEntity>();

class RequestConfigSection extends StatelessWidget {
  final String tabId;
  final CodeLineEditingController bodyController;
  const RequestConfigSection({super.key, required this.tabId, required this.bodyController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        if (p == null || n == null) return true;
        // URL carries the query — a single equality check captures any params
        // change that would affect the PARAMS tab.
        return p.config.url != n.config.url ||
            !headerMapEquality.equals(p.config.headers, n.config.headers);
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();

        return DefaultTabController(
          length: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabBar(
                dividerColor: Colors.transparent,
                isScrollable: true,
                indicator: BoxDecoration(
                  color: theme.primaryColor,
                  border: Border(
                    top: BorderSide(color: theme.dividerColor, width: layout.borderThick),
                    left: BorderSide(color: theme.dividerColor, width: layout.borderThick),
                    right: BorderSide(color: theme.dividerColor, width: layout.borderThick),
                  ),
                ),
                labelColor: theme.colorScheme.onPrimary,
                unselectedLabelColor: theme.colorScheme.onSurface,
                labelStyle: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: context.appTypography.displayWeight),
                tabs: const [
                  Tab(text: 'PARAMS'),
                  Tab(text: 'HEADERS'),
                  Tab(text: 'BODY'),
                ],
              ),
              Expanded(
                child: Container(
                  decoration: context.appDecoration.panelBox(context, offset: 0),
                  child: TabBarView(
                    children: [
                      QueryParamsEditor(
                        items: tab.config.params,
                        onChanged: (list) {
                          final current = context.read<TabsBloc>().state.tabs.byId(tabId);
                          if (current == null) return;
                          context.read<TabsBloc>().add(UpdateTab(
                            current.copyWith(config: current.config.copyWith(params: list)),
                          ));
                        },
                      ),
                      HeadersEditor(
                        items: tab.config.headers,
                        onChanged: (map) {
                          final current = context.read<TabsBloc>().state.tabs.byId(tabId);
                          if (current == null) return;
                          context.read<TabsBloc>().add(UpdateTab(
                            current.copyWith(config: current.config.copyWith(headers: map)),
                          ));
                        },
                      ),
                      _buildBodyEditor(context, theme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBodyEditor(BuildContext context, ThemeData theme) {
    final layout = context.appLayout;

    return Stack(
      children: [
        JsonCodeEditor(controller: bodyController),
        Positioned(
          top: 8,
          right: 8,
          child: context.appDecoration.wrapInteractive(
            child: IconButton(
              icon: Icon(Icons.auto_fix_high, color: theme.colorScheme.secondary, size: layout.isCompact ? 20 : 24),
              tooltip: 'Beautify JSON',
              onPressed: () async {
                final prettified = await JsonUtils.prettify(bodyController.text);
                bodyController.text = prettified;
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Editor for ordered `List<QueryParamEntity>`. Duplicates allowed, order
/// preserved. Mirrors the echo-suppression pattern of `HeadersEditor`.
class QueryParamsEditor extends StatefulWidget {
  final List<QueryParamEntity> items;
  final Function(List<QueryParamEntity>) onChanged;

  const QueryParamsEditor({super.key, required this.items, required this.onChanged});

  @override
  State<QueryParamsEditor> createState() => _QueryParamsEditorState();
}

class _QueryParamsEditorState extends State<QueryParamsEditor> {
  late List<TextEditingController> _keyControllers;
  late List<TextEditingController> _valControllers;
  List<QueryParamEntity>? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _initControllers(widget.items);
  }

  void _initControllers(List<QueryParamEntity> items) {
    _keyControllers = [];
    _valControllers = [];

    for (final p in items) {
      _keyControllers.add(TextEditingController(text: p.key));
      _valControllers.add(TextEditingController(text: p.value));
    }
    _keyControllers.add(TextEditingController());
    _valControllers.add(TextEditingController());
  }

  @override
  void didUpdateWidget(QueryParamsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastEmitted != null &&
        _queryParamListEquality.equals(widget.items, _lastEmitted)) {
      return;
    }
    if (_queryParamListEquality.equals(widget.items, oldWidget.items)) {
      return;
    }
    _disposeControllers();
    _initControllers(widget.items);
    _lastEmitted = null;
  }

  void _disposeControllers() {
    for (final c in _keyControllers) {
      c.dispose();
    }
    for (final c in _valControllers) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  List<QueryParamEntity> _asList() {
    final list = <QueryParamEntity>[];
    for (int i = 0; i < _keyControllers.length; i++) {
      final key = _keyControllers[i].text;
      final val = _valControllers[i].text;
      if (key.isNotEmpty) {
        list.add(QueryParamEntity(key: key, value: val));
      }
    }
    return list;
  }

  void _emit() {
    final list = _asList();
    _lastEmitted = list;
    widget.onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return ListView.builder(
      itemCount: _keyControllers.length,
      itemBuilder: (context, index) {
        return _KeyValueRow(
          key: ValueKey(_keyControllers[index]),
          keyController: _keyControllers[index],
          valController: _valControllers[index],
          layout: layout,
          isLast: index == _keyControllers.length - 1,
          onKeyChanged: (val) {
            if (index == _keyControllers.length - 1 && val.isNotEmpty) {
              setState(() {
                _keyControllers.add(TextEditingController());
                _valControllers.add(TextEditingController());
              });
            }
            _emit();
          },
          onValChanged: (val) => _emit(),
          onDelete: () {
            setState(() {
              _keyControllers[index].dispose();
              _valControllers[index].dispose();
              _keyControllers.removeAt(index);
              _valControllers.removeAt(index);
              if (_keyControllers.isEmpty) {
                _keyControllers.add(TextEditingController());
                _valControllers.add(TextEditingController());
              }
              _emit();
            });
          },
        );
      },
    );
  }
}

/// Editor for headers, still keyed as `Map<String, String>`. Duplicates are
/// not a real concern for headers in this UI — last-write-wins is fine.
class HeadersEditor extends StatefulWidget {
  final Map<String, String> items;
  final Function(Map<String, String>) onChanged;

  const HeadersEditor({super.key, required this.items, required this.onChanged});

  @override
  State<HeadersEditor> createState() => _HeadersEditorState();
}

class _HeadersEditorState extends State<HeadersEditor> {
  late List<TextEditingController> _keyControllers;
  late List<TextEditingController> _valControllers;
  Map<String, String>? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _initControllers(widget.items);
  }

  void _initControllers(Map<String, String> items) {
    _keyControllers = [];
    _valControllers = [];

    for (final entry in items.entries) {
      _keyControllers.add(TextEditingController(text: entry.key));
      _valControllers.add(TextEditingController(text: entry.value));
    }
    _keyControllers.add(TextEditingController());
    _valControllers.add(TextEditingController());
  }

  @override
  void didUpdateWidget(HeadersEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastEmitted != null && headerMapEquality.equals(widget.items, _lastEmitted)) {
      return;
    }
    if (headerMapEquality.equals(widget.items, oldWidget.items)) {
      return;
    }
    _disposeControllers();
    _initControllers(widget.items);
    _lastEmitted = null;
  }

  void _disposeControllers() {
    for (final c in _keyControllers) {
      c.dispose();
    }
    for (final c in _valControllers) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  Map<String, String> _asMap() {
    final map = <String, String>{};
    for (int i = 0; i < _keyControllers.length; i++) {
      final key = _keyControllers[i].text;
      final val = _valControllers[i].text;
      if (key.isNotEmpty) {
        map[key] = val;
      }
    }
    return map;
  }

  void _emit() {
    final map = _asMap();
    _lastEmitted = map;
    widget.onChanged(map);
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return ListView.builder(
      itemCount: _keyControllers.length,
      itemBuilder: (context, index) {
        return _KeyValueRow(
          key: ValueKey(_keyControllers[index]),
          keyController: _keyControllers[index],
          valController: _valControllers[index],
          layout: layout,
          isLast: index == _keyControllers.length - 1,
          onKeyChanged: (val) {
            if (index == _keyControllers.length - 1 && val.isNotEmpty) {
              setState(() {
                _keyControllers.add(TextEditingController());
                _valControllers.add(TextEditingController());
              });
            }
            _emit();
          },
          onValChanged: (val) => _emit(),
          onDelete: () {
            setState(() {
              _keyControllers[index].dispose();
              _valControllers[index].dispose();
              _keyControllers.removeAt(index);
              _valControllers.removeAt(index);
              if (_keyControllers.isEmpty) {
                _keyControllers.add(TextEditingController());
                _valControllers.add(TextEditingController());
              }
              _emit();
            });
          },
        );
      },
    );
  }
}

class _KeyValueRow extends StatefulWidget {
  final TextEditingController keyController;
  final TextEditingController valController;
  final AppLayout layout;
  final bool isLast;
  final Function(String) onKeyChanged;
  final Function(String) onValChanged;
  final VoidCallback onDelete;

  const _KeyValueRow({
    super.key,
    required this.keyController,
    required this.valController,
    required this.layout,
    required this.isLast,
    required this.onKeyChanged,
    required this.onValChanged,
    required this.onDelete,
  });

  @override
  State<_KeyValueRow> createState() => _KeyValueRowState();
}

class _KeyValueRowState extends State<_KeyValueRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPhone = context.isPhone;
    final fieldPadding = EdgeInsets.all(widget.layout.isCompact ? 8 : 12);
    final textStyle = TextStyle(fontSize: widget.layout.fontSizeNormal, fontWeight: context.appTypography.titleWeight);

    final keyField = TextField(
      style: textStyle,
      decoration: InputDecoration(
        hintText: 'KEY',
        isDense: true,
        contentPadding: fieldPadding,
      ),
      controller: widget.keyController,
      onChanged: widget.onKeyChanged,
    );
    final valueField = TextField(
      style: textStyle,
      decoration: InputDecoration(
        hintText: 'VALUE',
        isDense: true,
        contentPadding: fieldPadding,
      ),
      controller: widget.valController,
      onChanged: widget.onValChanged,
    );
    final deleteButton = context.appDecoration.wrapInteractive(
      child: IconButton(
        icon: Icon(Icons.delete_outline, size: widget.layout.isCompact ? 20 : 24, color: Theme.of(context).colorScheme.error),
        onPressed: widget.onDelete,
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: widget.layout.isCompact ? 8.0 : 12.0),
        padding: EdgeInsets.symmetric(horizontal: isPhone ? 8 : 4, vertical: isPhone ? 8 : 2),
        decoration: BoxDecoration(
          color: _isHovered ? theme.hoverColor : (isPhone ? theme.colorScheme.surface : Colors.transparent),
          borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          border: Border.all(
            color: isPhone
                ? theme.dividerColor.withValues(alpha: 0.6)
                : (_isHovered ? theme.dividerColor.withValues(alpha: 0.5) : Colors.transparent),
            width: widget.layout.borderThin,
          ),
        ),
        child: isPhone
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: keyField),
                      deleteButton,
                    ],
                  ),
                  SizedBox(height: widget.layout.tabSpacing),
                  valueField,
                ],
              )
            : Row(
                children: [
                  Expanded(child: keyField),
                  SizedBox(width: widget.layout.isCompact ? 8 : 12),
                  Expanded(child: valueField),
                  SizedBox(width: widget.layout.isCompact ? 4 : 8),
                  deleteButton,
                ],
              ),
      ),
    );
  }
}
