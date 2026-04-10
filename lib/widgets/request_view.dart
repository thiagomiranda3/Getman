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
  final String tabId;
  const RequestView({super.key, required this.tabId});

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

  @override
  void initState() {
    super.initState();
    final tab = _getTab();
    _urlController = TextEditingController(text: tab.config.url);
    _bodyController = CodeLineEditingController.fromText(tab.config.body);
    _responseController = CodeLineEditingController.fromText(_getPrettifiedBody(tab.responseBody));
    _bodyController!.addListener(_onBodyChanged);
  }

  HttpRequestTabModel _getTab() {
    return ref.read(tabsProvider).tabs.firstWhere((t) => t.tabId == widget.tabId);
  }

  void _onBodyChanged() {
     final tab = _getTab();
     final newText = _bodyController!.text;
     if (tab.config.body == newText) return;
     
     Future.microtask(() {
       if (!mounted) return;
       ref.read(tabsProvider.notifier).updateCurrentTab(
         tab.copyWith(config: tab.config.copyWith(body: newText)),
       );
     });
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
    if (oldWidget.tabId != widget.tabId) {
       final tab = _getTab();
       _urlController.text = tab.config.url;
       _bodyController?.text = tab.config.body;
       _responseController?.text = _getPrettifiedBody(tab.responseBody);
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
    final tab = ref.watch(tabsProvider.select((s) => s.tabs.firstWhere((t) => t.tabId == widget.tabId)));
    
    // Sync controllers if model changed from outside
    if (_urlController.text != tab.config.url) {
       _urlController.text = tab.config.url;
    }
    // We don't sync _bodyController here because it would mess up typing.
    // _bodyController is synced in didUpdateWidget if tabId changes,
    // or it's updated via _onBodyChanged.
    
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _handleSave(tab),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () => _handleSave(tab),
      },
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            _buildUrlBar(context, tab),
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildRequestConfig(context, tab)),
                  VerticalDivider(width: 48, thickness: 3, color: theme.dividerColor),
                  Expanded(child: _buildResponseSection(context, tab)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSave(HttpRequestTabModel tab) {
    final theme = Theme.of(context);
    if (tab.collectionNodeId != null) {
      ref.read(collectionsProvider.notifier).updateRequest(
        tab.collectionNodeId!,
        tab.config.copyWith(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: theme.primaryColor,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: theme.dividerColor, width: 3),
          ),
          content: Text('REQUEST UPDATED!', style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 12, fontWeight: FontWeight.w900)),
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      _showSaveDialog(tab);
    }
  }

  Widget _buildUrlBar(BuildContext context, HttpRequestTabModel tab) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: NeoBrutalistTheme.brutalBox(context, offset: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: theme.dividerColor, width: 3)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                dropdownColor: theme.colorScheme.surface,
                value: tab.config.method,
                style: TextStyle(
                  color: theme.colorScheme.onSurface, 
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
                        border: Border.all(color: theme.dividerColor, width: 2),
                      ),
                      child: Text(m, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
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
                          border: Border.all(color: theme.dividerColor, width: 2),
                        ),
                        child: Text(m, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
                      ),
                    ))
                    .toList(),
                onChanged: (val) {
                  if (val != null && tab.config.method != val) {
                    Future.microtask(() {
                      if (!mounted) return;
                      ref.read(tabsProvider.notifier).updateCurrentTab(
                        tab.copyWith(config: tab.config.copyWith(method: val)),
                      );
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _urlController,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
              decoration: const InputDecoration(
                hintText: 'Enter URL...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                filled: false,
              ),
              onChanged: (val) {
                 if (tab.config.url == val) return;
                 Future.microtask(() {
                   if (!mounted) return;
                   ref.read(tabsProvider.notifier).updateCurrentTab(
                    tab.copyWith(config: tab.config.copyWith(url: val)),
                  );
                 });
              },
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: tab.isSending ? null : () => ref.read(tabsProvider.notifier).sendRequest(),
            style: ElevatedButton.styleFrom(
               padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
            child: tab.isSending 
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: theme.colorScheme.onPrimary)) 
              : const Text('SEND'),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(tab.collectionNodeId != null ? Icons.save : Icons.save_as, color: theme.colorScheme.secondary, size: 28),
            tooltip: tab.collectionNodeId != null ? 'Update Request' : 'Save to Collection',
            onPressed: () => _handleSave(tab),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestConfig(BuildContext context, HttpRequestTabModel tab) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabBar(
            isScrollable: true,
            indicator: BoxDecoration(
              color: theme.primaryColor,
              border: Border(
                top: BorderSide(color: theme.dividerColor, width: 3),
                left: BorderSide(color: theme.dividerColor, width: 3),
                right: BorderSide(color: theme.dividerColor, width: 3),
              ),
            ),
            labelColor: theme.colorScheme.onSurface,
            unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            tabs: const [
              Tab(text: 'PARAMS'),
              Tab(text: 'HEADERS'),
              Tab(text: 'BODY'),
            ],
          ),
          Expanded(
            child: Container(
              decoration: NeoBrutalistTheme.brutalBox(context, offset: 0),
              child: TabBarView(
                children: [
                  _KeyValueEditor(
                    items: tab.config.params,
                    onChanged: (map) {
                      Future.microtask(() {
                        if (!mounted) return;
                        ref.read(tabsProvider.notifier).updateCurrentTab(
                          tab.copyWith(config: tab.config.copyWith(params: map)),
                        );
                      });
                    },
                  ),
                  _KeyValueEditor(
                    items: tab.config.headers,
                    onChanged: (map) {
                      Future.microtask(() {
                        if (!mounted) return;
                        ref.read(tabsProvider.notifier).updateCurrentTab(
                          tab.copyWith(config: tab.config.copyWith(headers: map)),
                        );
                      });
                    },
                  ),
                  _buildBodyEditor(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyEditor(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: CodeEditor(
        controller: _bodyController!,
        wordWrap: true,
        style: CodeEditorStyle(
          fontSize: 13,
          fontFamily: 'monospace',
          backgroundColor: Colors.transparent,
          cursorColor: theme.primaryColor,
          selectionColor: theme.primaryColor.withValues(alpha: 0.3),
          cursorLineColor: theme.primaryColor.withValues(alpha: 0.1),
          codeTheme: CodeHighlightTheme(
            languages: {
              'json': CodeHighlightThemeMode(
                mode: langJson,
              ),
            },
            theme: arduinoLightTheme, // Still using light but with transparent bg
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

  Widget _buildResponseSection(BuildContext context, HttpRequestTabModel tab) {
    final theme = Theme.of(context);
    if (tab.statusCode == null && !tab.isSending) {
       return Center(child: Column(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           Icon(Icons.bolt, size: 64, color: theme.colorScheme.secondary),
           const SizedBox(height: 24),
           Text('HIT SEND TO GET A RESPONSE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
         ],
       ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (tab.statusCode != null)
                _ResponseMetadataItem(label: 'STATUS', value: tab.statusCode.toString(), color: _getStatusColor(tab.statusCode!)),
              if (tab.durationMs != null)
                 _ResponseMetadataItem(label: 'TIME', value: '${tab.durationMs} ms', color: theme.colorScheme.secondary),
            ],
          ),
        ),
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  indicator: BoxDecoration(
                    color: theme.primaryColor,
                    border: Border(
                      top: BorderSide(color: theme.dividerColor, width: 3),
                      left: BorderSide(color: theme.dividerColor, width: 3),
                      right: BorderSide(color: theme.dividerColor, width: 3),
                    ),
                  ),
                  labelColor: theme.colorScheme.onSurface,
                  unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  tabs: const [
                    Tab(text: 'BODY'),
                    Tab(text: 'HEADERS'),
                  ],
                ),
                Expanded(
                  child: Container(
                    decoration: NeoBrutalistTheme.brutalBox(context, offset: 0),
                    child: TabBarView(
                      children: [
                        _buildResponseBody(context, tab),
                        _buildResponseHeaders(context, tab),
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

  Widget _buildResponseBody(BuildContext context, HttpRequestTabModel tab) {
    final theme = Theme.of(context);
    if (tab.responseBody == null) return const SizedBox();

    // Sync response controller if body changed
    final prettified = _getPrettifiedBody(tab.responseBody);
    if (_responseController?.text != prettified) {
       _responseController?.text = prettified;
    }

    return Container(
        width: double.infinity,
        color: theme.colorScheme.surface,
        child: CodeEditor(
          controller: _responseController!,
          readOnly: true,
          wordWrap: true,
          style: CodeEditorStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            backgroundColor: Colors.transparent,
            cursorColor: theme.primaryColor,
            selectionColor: theme.primaryColor.withValues(alpha: 0.3),
            cursorLineColor: theme.primaryColor.withValues(alpha: 0.2),
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

  Widget _buildResponseHeaders(BuildContext context, HttpRequestTabModel tab) {
    final theme = Theme.of(context);
    if (tab.responseHeaders == null) return const SizedBox();
    return ListView(
      children: tab.responseHeaders!.entries.map((e) => ListTile(
        dense: true,
        title: Text(e.key.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: theme.primaryColor)),
        subtitle: Text(e.value, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface)),
      )).toList(),
    );
  }

  Color _getStatusColor(int code) {
    if (code >= 200 && code < 300) return Colors.greenAccent;
    if (code >= 400) return Colors.redAccent;
    return Colors.orangeAccent;
  }

  void _showSaveDialog(HttpRequestTabModel tab) {
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
              final id = ref.read(collectionsProvider.notifier).saveRequest(controller.text, tab.config.copyWith());
              ref.read(tabsProvider.notifier).updateCurrentTab(
                tab.copyWith(collectionNodeId: id, collectionName: controller.text),
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
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.2) ?? theme.primaryColor.withValues(alpha: 0.2),
        border: Border.all(color: theme.dividerColor, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 10, fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 11)),
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
  late List<TextEditingController> _keyControllers;
  late List<TextEditingController> _valControllers;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    _keyControllers = [];
    _valControllers = [];
    
    for (var entry in widget.items.entries) {
      _keyControllers.add(TextEditingController(text: entry.key));
      _valControllers.add(TextEditingController(text: entry.value));
    }
    // Add one empty row
    _keyControllers.add(TextEditingController());
    _valControllers.add(TextEditingController());
  }

  @override
  void didUpdateWidget(_KeyValueEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-init if the map entries actually changed from outside
    if (!_isSame(oldWidget.items, widget.items)) {
       // To avoid losing focus while typing, we should be careful here.
       // But usually, changes come from user typing which we already handle.
       // If changes come from outside (e.g. loading a request), we re-init.
       _disposeControllers();
       _initControllers();
    }
  }

  bool _isSame(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (var key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  void _disposeControllers() {
    for (var c in _keyControllers) {
      c.dispose();
    }
    for (var c in _valControllers) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _update() {
    final Map<String, String> map = {};
    for (int i = 0; i < _keyControllers.length; i++) {
      final key = _keyControllers[i].text;
      final val = _valControllers[i].text;
      if (key.isNotEmpty) {
        map[key] = val;
      }
    }
    widget.onChanged(map);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _keyControllers.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(hintText: 'KEY', isDense: true, contentPadding: EdgeInsets.all(12)),
                  controller: _keyControllers[index],
                  onChanged: (val) {
                    if (index == _keyControllers.length - 1 && val.isNotEmpty) {
                      setState(() {
                        _keyControllers.add(TextEditingController());
                        _valControllers.add(TextEditingController());
                      });
                    }
                    _update();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(hintText: 'VALUE', isDense: true, contentPadding: EdgeInsets.all(12)),
                  controller: _valControllers[index],
                  onChanged: (val) {
                     _update();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 24, color: Colors.red),
                onPressed: () {
                  setState(() {
                    _keyControllers[index].dispose();
                    _valControllers[index].dispose();
                    _keyControllers.removeAt(index);
                    _valControllers.removeAt(index);
                    if (_keyControllers.isEmpty) {
                      _keyControllers.add(TextEditingController());
                      _valControllers.add(TextEditingController());
                    }
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