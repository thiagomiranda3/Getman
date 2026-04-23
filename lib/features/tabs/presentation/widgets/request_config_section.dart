import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';

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
        return !headerMapEquality.equals(p.config.params, n.config.params) ||
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
                      _KeyValueEditor(
                        items: tab.config.params,
                        onChanged: (map) {
                          final current = context.read<TabsBloc>().state.tabs.byId(tabId);
                          if (current == null) return;
                          context.read<TabsBloc>().add(UpdateTab(
                            current.copyWith(config: current.config.copyWith(params: map)),
                          ));
                        },
                      ),
                      _KeyValueEditor(
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

class _KeyValueEditor extends StatefulWidget {
  final Map<String, String> items;
  final Function(Map<String, String>) onChanged;

  const _KeyValueEditor({required this.items, required this.onChanged});

  @override
  State<_KeyValueEditor> createState() => _KeyValueEditorState();
}

class _KeyValueEditorState extends State<_KeyValueEditor> {
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
  void didUpdateWidget(_KeyValueEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the incoming items are the echo of our own last emission, the
    // current controllers are already correct — don't wipe them (which
    // would drop focus and blow away the user's half-typed row).
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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: widget.layout.isCompact ? 8.0 : 12.0),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: _isHovered ? theme.hoverColor : Colors.transparent,
          borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          border: Border.all(color: _isHovered ? theme.dividerColor.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: widget.layout.fontSizeNormal, fontWeight: context.appTypography.titleWeight),
                decoration: InputDecoration(
                  hintText: 'KEY',
                  isDense: true,
                  contentPadding: EdgeInsets.all(widget.layout.isCompact ? 8 : 12),
                ),
                controller: widget.keyController,
                onChanged: widget.onKeyChanged,
              ),
            ),
            SizedBox(width: widget.layout.isCompact ? 8 : 12),
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: widget.layout.fontSizeNormal, fontWeight: context.appTypography.titleWeight),
                decoration: InputDecoration(
                  hintText: 'VALUE',
                  isDense: true,
                  contentPadding: EdgeInsets.all(widget.layout.isCompact ? 8 : 12),
                ),
                controller: widget.valController,
                onChanged: widget.onValChanged,
              ),
            ),
            SizedBox(width: widget.layout.isCompact ? 4 : 8),
            context.appDecoration.wrapInteractive(
              child: IconButton(
                icon: Icon(Icons.delete_outline, size: widget.layout.isCompact ? 20 : 24, color: Theme.of(context).colorScheme.error),
                onPressed: widget.onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
