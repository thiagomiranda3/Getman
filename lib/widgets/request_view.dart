import 'dart:convert' as convert;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/arduino-light.dart';
import 'package:re_highlight/languages/json.dart';
import '../providers/tabs_provider.dart';
import '../providers/collections_provider.dart';
import '../models/request_tab.dart';
import '../utils/neo_brutalist_theme.dart';

class RequestView extends ConsumerStatefulWidget {
  final HttpRequestTabModel tab;
  const RequestView({super.key, required this.tab});

  @override
  ConsumerState<RequestView> createState() => _RequestViewState();
}

class _RequestViewState extends ConsumerState<RequestView> {
  late TextEditingController _urlController;
  CodeLineEditingController? _bodyController;
  CodeLineEditingController? _responseController;
  
  final FocusNode _responseFocusNode = FocusNode();
  final ScrollController _responseScrollController = ScrollController();
  final ScrollController _requestScrollController = ScrollController();
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.tab.config.url);
    _bodyController = CodeLineEditingController.fromText(widget.tab.config.body);
    _responseController = CodeLineEditingController.fromText(_getPrettifiedBody(widget.tab.responseBody));
    _bodyController!.addListener(_onBodyChanged);
  }

  void _onBodyChanged() {
     ref.read(tabsProvider.notifier).updateCurrentTab(
       widget.tab.copyWith(config: widget.tab.config.copyWith(body: _bodyController!.text)),
     );
  }

  String _getPrettifiedBody(String? body) {
    if (body == null || body.isEmpty) return '';
    try {
      final decoded = convert.json.decode(body);
      return const convert.JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return body;
    }
  }

  @override
  void didUpdateWidget(RequestView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.config.id != widget.tab.config.id) {
       _urlController.text = widget.tab.config.url;
       _bodyController?.text = widget.tab.config.body;
    }
    if (oldWidget.tab.responseBody != widget.tab.responseBody) {
       _responseController?.text = _getPrettifiedBody(widget.tab.responseBody);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _bodyController?.removeListener(_onBodyChanged);
    _bodyController?.dispose();
    _responseController?.dispose();
    _responseFocusNode.dispose();
    _responseScrollController.dispose();
    _requestScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _handleSave,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _handleSave,
      },
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            _buildUrlBar(),
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildRequestConfig()),
                  const VerticalDivider(width: 48, thickness: 3, color: NeoBrutalistTheme.border),
                  Expanded(child: _buildResponseSection()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSave() {
    if (widget.tab.collectionNodeId != null) {
      ref.read(collectionsProvider.notifier).updateRequest(
        widget.tab.collectionNodeId!,
        widget.tab.config.copyWith(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NeoBrutalistTheme.primary,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: NeoBrutalistTheme.border, width: 3),
          ),
          content: const Text('REQUEST UPDATED!', style: TextStyle(color: NeoBrutalistTheme.text, fontSize: 12, fontWeight: FontWeight.w900)),
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      _showSaveDialog();
    }
  }

  Widget _buildUrlBar() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: NeoBrutalistTheme.brutalBox(offset: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: NeoBrutalistTheme.border, width: 3)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                dropdownColor: NeoBrutalistTheme.surface,
                value: widget.tab.config.method,
                style: TextStyle(
                  color: NeoBrutalistTheme.text, 
                  fontWeight: FontWeight.w900, 
                  fontSize: 12,
                ),
                selectedItemBuilder: (context) {
                  return ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'].map((m) {
                    return Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: NeoBrutalistTheme.getMethodColor(m),
                        border: Border.all(color: NeoBrutalistTheme.border, width: 2),
                      ),
                      child: Text(m, style: const TextStyle(color: NeoBrutalistTheme.text, fontWeight: FontWeight.w900, fontSize: 12)),
                    );
                  }).toList();
                },
                items: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']
                    .map((m) => DropdownMenuItem(
                      value: m, 
                      child: Container(
                        width: 100,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: NeoBrutalistTheme.getMethodColor(m),
                          border: Border.all(color: NeoBrutalistTheme.border, width: 2),
                        ),
                        child: Text(m, style: const TextStyle(color: NeoBrutalistTheme.text, fontWeight: FontWeight.w900, fontSize: 12)),
                      ),
                    ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    ref.read(tabsProvider.notifier).updateCurrentTab(
                      widget.tab.copyWith(config: widget.tab.config.copyWith(method: val)),
                    );
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _urlController,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: NeoBrutalistTheme.text),
              decoration: const InputDecoration(
                hintText: 'Enter URL...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                filled: false,
              ),
              onChanged: (val) {
                 ref.read(tabsProvider.notifier).updateCurrentTab(
                  widget.tab.copyWith(config: widget.tab.config.copyWith(url: val)),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: widget.tab.isSending ? null : () => ref.read(tabsProvider.notifier).sendRequest(),
            style: ElevatedButton.styleFrom(
               padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
            child: widget.tab.isSending 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: NeoBrutalistTheme.text)) 
              : const Text('SEND'),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(widget.tab.collectionNodeId != null ? Icons.save : Icons.save_as, color: NeoBrutalistTheme.secondary, size: 28),
            tooltip: widget.tab.collectionNodeId != null ? 'Update Request' : 'Save to Collection',
            onPressed: _handleSave,
          ),
        ],
      ),
    );
  }

  Widget _buildRequestConfig() {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TabBar(
            isScrollable: true,
            indicator: BoxDecoration(
              color: NeoBrutalistTheme.primary,
              border: Border(
                top: BorderSide(color: NeoBrutalistTheme.border, width: 3),
                left: BorderSide(color: NeoBrutalistTheme.border, width: 3),
                right: BorderSide(color: NeoBrutalistTheme.border, width: 3),
              ),
            ),
            labelColor: NeoBrutalistTheme.text,
            unselectedLabelColor: NeoBrutalistTheme.text,
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            tabs: [
              Tab(text: 'PARAMS'),
              Tab(text: 'HEADERS'),
              Tab(text: 'BODY'),
            ],
          ),
          Expanded(
            child: Container(
              decoration: NeoBrutalistTheme.brutalBox(offset: 0),
              child: TabBarView(
                children: [
                  _KeyValueEditor(
                    items: widget.tab.config.params,
                    onChanged: (map) {
                      ref.read(tabsProvider.notifier).updateCurrentTab(
                        widget.tab.copyWith(config: widget.tab.config.copyWith(params: map)),
                      );
                    },
                  ),
                  _KeyValueEditor(
                    items: widget.tab.config.headers,
                    onChanged: (map) {
                      ref.read(tabsProvider.notifier).updateCurrentTab(
                        widget.tab.copyWith(config: widget.tab.config.copyWith(headers: map)),
                      );
                    },
                  ),
                  _buildBodyEditor(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyEditor() {
    return Container(
      color: NeoBrutalistTheme.editorBackground,
      child: CodeEditor(
        controller: _bodyController!,
        wordWrap: true,
        style: CodeEditorStyle(
          fontSize: 13,
          fontFamily: 'monospace',
          backgroundColor: Colors.transparent,
          cursorColor: NeoBrutalistTheme.primary,
          selectionColor: NeoBrutalistTheme.primary.withValues(alpha: 0.3),
          codeTheme: CodeHighlightTheme(
            languages: {
              'json': CodeHighlightThemeMode(
                mode: langJson,
              ),
            },
            theme: arduinoLightTheme,
          ),
        ),
        indicatorBuilder: (context, controller, chunkController, notifier) {
          return DefaultCodeLineNumber(
            controller: controller,
            notifier: notifier,
          );
        },
      ),
    );
  }

  Widget _buildResponseSection() {
    if (widget.tab.statusCode == null && !widget.tab.isSending) {
       return Center(child: Column(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           const Icon(Icons.bolt, size: 64, color: NeoBrutalistTheme.secondary),
           const SizedBox(height: 24),
           const Text('HIT SEND TO GET A RESPONSE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: NeoBrutalistTheme.text)),
         ],
       ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              if (widget.tab.statusCode != null)
                _ResponseMetadataItem(label: 'STATUS', value: widget.tab.statusCode.toString(), color: _getStatusColor(widget.tab.statusCode!)),
              if (widget.tab.durationMs != null)
                 _ResponseMetadataItem(label: 'TIME', value: '${widget.tab.durationMs} ms', color: NeoBrutalistTheme.secondary),
            ],
          ),
        ),
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  indicator: BoxDecoration(
                    color: NeoBrutalistTheme.primary,
                    border: Border(
                      top: BorderSide(color: NeoBrutalistTheme.border, width: 3),
                      left: BorderSide(color: NeoBrutalistTheme.border, width: 3),
                      right: BorderSide(color: NeoBrutalistTheme.border, width: 3),
                    ),
                  ),
                  labelColor: NeoBrutalistTheme.text,
                  unselectedLabelColor: NeoBrutalistTheme.text,
                  labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  tabs: [
                    Tab(text: 'BODY'),
                    Tab(text: 'HEADERS'),
                  ],
                ),
                Expanded(
                  child: Container(
                    decoration: NeoBrutalistTheme.brutalBox(offset: 0),
                    child: TabBarView(
                      children: [
                        _buildResponseBody(),
                        _buildResponseHeaders(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResponseBody() {
    if (widget.tab.responseBody == null) return const SizedBox();

    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        width: double.infinity,
        color: NeoBrutalistTheme.editorBackground,
        child: CodeEditor(
          controller: _responseController!,
          readOnly: true,
          wordWrap: true,
          style: CodeEditorStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            backgroundColor: Colors.transparent,
            cursorColor: NeoBrutalistTheme.primary,
            selectionColor: NeoBrutalistTheme.primary.withValues(alpha: 0.3),
            codeTheme: CodeHighlightTheme(
              languages: {
                'json': CodeHighlightThemeMode(
                  mode: langJson,
                ),
              },
              theme: arduinoLightTheme,
            ),
          ),
          indicatorBuilder: (context, controller, chunkController, notifier) {
            return DefaultCodeLineNumber(
              controller: controller,
              notifier: notifier,
            );
          },
        ),
      ),
    );
  }

  Widget _buildResponseHeaders() {
    if (widget.tab.responseHeaders == null) return const SizedBox();
    return ListView(
      children: widget.tab.responseHeaders!.entries.map((e) => ListTile(
        dense: true,
        title: Text(e.key.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: NeoBrutalistTheme.primary)),
        subtitle: Text(e.value, style: const TextStyle(fontSize: 10, color: NeoBrutalistTheme.text)),
      )).toList(),
    );
  }

  Color _getStatusColor(int code) {
    if (code >= 200 && code < 300) return Colors.greenAccent;
    if (code >= 400) return Colors.redAccent;
    return Colors.orangeAccent;
  }

  void _showSaveDialog() {
    final controller = TextEditingController(text: 'NEW REQUEST');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SAVE TO COLLECTION'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'REQUEST NAME')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              final id = ref.read(collectionsProvider.notifier).saveRequest(controller.text, widget.tab.config.copyWith());
              ref.read(tabsProvider.notifier).updateCurrentTab(
                widget.tab.copyWith(collectionNodeId: id, collectionName: controller.text),
              );
              Navigator.pop(context);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }
}

class _ResponseMetadataItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _ResponseMetadataItem({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.2) ?? NeoBrutalistTheme.primary.withValues(alpha: 0.2),
        border: Border.all(color: NeoBrutalistTheme.border, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: NeoBrutalistTheme.text, fontSize: 10, fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(color: NeoBrutalistTheme.text, fontWeight: FontWeight.w900, fontSize: 11)),
        ],
      ),
    );
  }
}

class _KeyValueEditor extends StatefulWidget {
  final Map<String, String> items;
  final Function(Map<String, String>) onChanged;

  const _KeyValueEditor({required this.items, required this.onChanged});

  @override
  _KeyValueEditorState createState() => _KeyValueEditorState();
}

class _KeyValueEditorState extends State<_KeyValueEditor> {
  late List<MapEntry<String, String>> _list;

  @override
  void initState() {
    super.initState();
    _list = widget.items.entries.toList();
    _list.add(const MapEntry('', ''));
  }

  void _update() {
    final Map<String, String> map = {};
    for (var entry in _list) {
      if (entry.key.isNotEmpty) {
        map[entry.key] = entry.value;
      }
    }
    widget.onChanged(map);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _list.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(hintText: 'KEY', isDense: true, contentPadding: EdgeInsets.all(12)),
                  controller: TextEditingController(text: _list[index].key)..selection = TextSelection.fromPosition(TextPosition(offset: _list[index].key.length)),
                  onChanged: (val) {
                    _list[index] = MapEntry(val, _list[index].value);
                    if (index == _list.length - 1 && val.isNotEmpty) {
                      _list.add(const MapEntry('', ''));
                    }
                    _update();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(hintText: 'VALUE', isDense: true, contentPadding: EdgeInsets.all(12)),
                  controller: TextEditingController(text: _list[index].value)..selection = TextSelection.fromPosition(TextPosition(offset: _list[index].value.length)),
                  onChanged: (val) {
                    _list[index] = MapEntry(_list[index].key, val);
                     _update();
                     setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 24, color: Colors.red),
                onPressed: () {
                  setState(() {
                    _list.removeAt(index);
                    if (_list.isEmpty) _list.add(const MapEntry('', ''));
                    _update();
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

