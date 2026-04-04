import 'dart:convert' as convert;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:highlight/languages/json.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import '../providers/tabs_provider.dart';
import '../providers/collections_provider.dart';
import '../models/request_tab.dart';

class RequestView extends ConsumerStatefulWidget {
  final HttpRequestTabModel tab;
  const RequestView({super.key, required this.tab});

  @override
  ConsumerState<RequestView> createState() => _RequestViewState();
}

class _RequestViewState extends ConsumerState<RequestView> {
  late TextEditingController _urlController;
  CodeController? _bodyController;
  CodeController? _responseController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.tab.config.url);
    _bodyController = CodeController(
      text: widget.tab.config.body,
      language: json,
    );
    _responseController = CodeController(
      text: _getPrettifiedBody(widget.tab.responseBody),
      language: json,
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
    _bodyController?.dispose();
    _responseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildUrlBar(),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildRequestConfig()),
                const VerticalDivider(),
                Expanded(child: _buildResponseSection()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrlBar() {
    return Row(
      children: [
        DropdownButton<String>(
          value: widget.tab.config.method,
          items: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']
              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              ref.read(tabsProvider.notifier).updateCurrentTab(
                widget.tab.copyWith(config: widget.tab.config.copyWith(method: val)),
              );
            }
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              hintText: 'Enter URL',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (val) {
               ref.read(tabsProvider.notifier).updateCurrentTab(
                widget.tab.copyWith(config: widget.tab.config.copyWith(url: val)),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: widget.tab.isSending ? null : () => ref.read(tabsProvider.notifier).sendRequest(),
          child: widget.tab.isSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send'),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.save),
          tooltip: 'Save to Collection',
          onPressed: () => _showSaveDialog(),
        ),
      ],
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
            tabs: [
              Tab(text: 'Params'),
              Tab(text: 'Headers'),
              Tab(text: 'Body'),
            ],
          ),
          Expanded(
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
        ],
      ),
    );
  }

  Widget _buildBodyEditor() {
    return CodeTheme(
      data: CodeThemeData(styles: monokaiSublimeTheme),
      child: CodeField(
        controller: _bodyController!,
        expands: true,
        textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        onChanged: (val) {
           ref.read(tabsProvider.notifier).updateCurrentTab(
             widget.tab.copyWith(config: widget.tab.config.copyWith(body: val)),
           );
        },
      ),
    );
  }

  Widget _buildResponseSection() {
    if (widget.tab.statusCode == null && !widget.tab.isSending) {
       return const Center(child: Text('Hit Send to get a response'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              if (widget.tab.statusCode != null)
                _ResponseMetadataItem(label: 'Status', value: widget.tab.statusCode.toString(), color: _getStatusColor(widget.tab.statusCode!)),
              if (widget.tab.durationMs != null)
                 _ResponseMetadataItem(label: 'Time', value: '${widget.tab.durationMs} ms'),
            ],
          ),
        ),
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Body'),
                    Tab(text: 'Headers'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildResponseBody(),
                      _buildResponseHeaders(),
                    ],
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
    
    return Container(
      width: double.infinity,
      color: monokaiSublimeTheme['root']?.backgroundColor ?? const Color(0xff23241f),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: CodeTheme(
          data: const CodeThemeData(styles: monokaiSublimeTheme),
          child: Builder(
            builder: (context) {
              return SelectableText.rich(
                _responseController!.buildTextSpan(
                  context: context,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  withComposing: false,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildResponseHeaders() {
    if (widget.tab.responseHeaders == null) return const SizedBox();
    return ListView(
      children: widget.tab.responseHeaders!.entries.map((e) => ListTile(
        dense: true,
        title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(e.value),
      )).toList(),
    );
  }

  Color _getStatusColor(int code) {
    if (code >= 200 && code < 300) return Colors.green;
    if (code >= 400) return Colors.red;
    return Colors.orange;
  }

  void _showSaveDialog() {
    final controller = TextEditingController(text: 'New Request');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save to Collection'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Request Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(collectionsProvider.notifier).saveRequest(controller.text, widget.tab.config.copyWith());
              Navigator.pop(context);
            },
            child: const Text('Save'),
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
    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.grey)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
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
      itemCount: _list.length,
      itemBuilder: (context, index) {
        return Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(hintText: 'Key', isDense: true),
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
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(hintText: 'Value', isDense: true),
                controller: TextEditingController(text: _list[index].value)..selection = TextSelection.fromPosition(TextPosition(offset: _list[index].value.length)),
                onChanged: (val) {
                  _list[index] = MapEntry(_list[index].key, val);
                   _update();
                   setState(() {});
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 16),
              onPressed: () {
                setState(() {
                  _list.removeAt(index);
                  if (_list.isEmpty) _list.add(const MapEntry('', ''));
                  _update();
                });
              },
            ),
          ],
        );
      },
    );
  }
}
