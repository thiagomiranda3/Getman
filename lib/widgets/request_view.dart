import 'dart:convert' as convert;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/arduino-light.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/tabs_provider.dart';
import '../providers/collections_provider.dart';
import '../providers/settings_provider.dart';
import '../models/request_tab.dart';
import '../models/settings_model.dart';
import '../utils/neo_brutalist_theme.dart';
import '../utils/layout_constants.dart';

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
  double? _localSplitRatio;
  
  final FocusNode _responseFocusNode = FocusNode();
  final ScrollController _responseScrollController = ScrollController();
  final ScrollController _requestScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final tab = _getTab();
    if (tab != null) {
      _urlController = TextEditingController(text: tab.config.url);
      _bodyController = CodeLineEditingController.fromText(tab.config.body);
      _responseController = CodeLineEditingController.fromText(_getPrettifiedBody(tab.responseBody));
      _bodyController!.addListener(_onBodyChanged);
    } else {
      _urlController = TextEditingController();
      _bodyController = CodeLineEditingController();
      _responseController = CodeLineEditingController();
    }
  }

  HttpRequestTabModel? _getTab() {
    return ref.read(tabsProvider).tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
  }

  void _onBodyChanged() {
     final tab = _getTab();
     if (tab == null) return;
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
      return const convert.JsonEncoder.withIndent('    ').convert(decoded);
    } catch (_) {
      return body;
    }
  }

  @override
  void didUpdateWidget(RequestView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabId != widget.tabId) {
       final tab = _getTab();
       if (tab != null) {
        _urlController.text = tab.config.url;
        _bodyController?.text = tab.config.body;
        _responseController?.text = _getPrettifiedBody(tab.responseBody);
       }
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
    final tab = ref.watch(tabsProvider.select((s) => s.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId)));
    if (tab == null) return const SizedBox.shrink();
    
    final settings = ref.watch(settingsProvider);
    final layout = LayoutConstants(settings.isCompactMode);
    
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
        padding: EdgeInsets.all(layout.pagePadding),
        child: Column(
          children: [
            _buildUrlBar(context, tab, layout, settings),
            SizedBox(height: layout.sectionSpacing),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalSize = settings.isVerticalLayout ? constraints.maxHeight : constraints.maxWidth;
                  final currentRatio = _localSplitRatio ?? settings.splitRatio;
                  
                  return Flex(
                    direction: settings.isVerticalLayout ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        flex: (currentRatio * 1000).toInt(),
                        child: _buildRequestConfig(context, tab, layout),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanUpdate: (details) {
                          final delta = settings.isVerticalLayout ? details.delta.dy : details.delta.dx;
                          setState(() {
                            _localSplitRatio = (_localSplitRatio ?? settings.splitRatio) + (delta / totalSize);
                            if (_localSplitRatio! < 0.1) _localSplitRatio = 0.1;
                            if (_localSplitRatio! > 0.9) _localSplitRatio = 0.9;
                          });
                        },
                        onPanEnd: (_) {
                          if (_localSplitRatio != null) {
                            ref.read(settingsProvider.notifier).updateSplitRatio(_localSplitRatio!);
                            // We don't reset _localSplitRatio to null here because 
                            // settingsProvider will take a moment to update and we want to keep the UI steady.
                            // The sync below handles external changes.
                          }
                        },
                        child: MouseRegion(
                          cursor: settings.isVerticalLayout ? SystemMouseCursors.resizeUpDown : SystemMouseCursors.resizeLeftRight,
                          child: settings.isVerticalLayout
                            ? Padding(
                                padding: EdgeInsets.symmetric(vertical: layout.isCompact ? 8 : 12),
                                child: Divider(height: 3, thickness: 3, color: theme.dividerColor),
                              )
                            : VerticalDivider(width: layout.verticalDividerWidth, thickness: 3, color: theme.dividerColor),
                        ),
                      ),
                      Flexible(
                        flex: ((1 - currentRatio) * 1000).toInt(),
                        child: _buildResponseSection(context, tab, layout),
                      ),
                    ],
                  );
                }
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

  Widget _buildUrlBar(BuildContext context, HttpRequestTabModel tab, LayoutConstants layout, SettingsModel settings) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: NeoBrutalistTheme.brutalBox(context, offset: layout.cardOffset),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: layout.isCompact ? 8 : 12),
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
                  fontSize: layout.fontSizeNormal,
                ),
                selectedItemBuilder: (context) {
                  return ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'].map((m) {
                    return Container(
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(horizontal: layout.isCompact ? 8 : 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: NeoBrutalistTheme.getMethodColor(m),
                        border: Border.all(color: theme.dividerColor, width: 2),
                      ),
                      child: Text(m, style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: layout.fontSizeNormal)),
                    );
                  }).toList();
                },
                items: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']
                    .map((m) => DropdownMenuItem(
                      value: m, 
                      child: Container(
                        width: layout.isCompact ? 80 : 100,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: NeoBrutalistTheme.getMethodColor(m),
                          border: Border.all(color: theme.dividerColor, width: 2),
                        ),
                        child: Text(m, style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: layout.fontSizeNormal)),
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
          SizedBox(width: layout.isCompact ? 8 : 12),
          Expanded(
            child: TextField(
              controller: _urlController,
              style: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
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
          SizedBox(width: layout.isCompact ? 8 : 12),
          ElevatedButton(
            onPressed: tab.isSending ? null : () => ref.read(tabsProvider.notifier).sendRequest(),
            style: ElevatedButton.styleFrom(
               padding: EdgeInsets.symmetric(
                 horizontal: layout.buttonPaddingHorizontal, 
                 vertical: layout.buttonPaddingVertical
               ),
            ),
            child: tab.isSending 
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: theme.colorScheme.onPrimary)) 
              : Text('SEND', style: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: FontWeight.w900)),
          ),
          SizedBox(width: layout.isCompact ? 8 : 12),
          IconButton(
            icon: Icon(tab.collectionNodeId != null ? Icons.save : Icons.save_as, color: theme.colorScheme.secondary, size: layout.isCompact ? 24 : 28),
            tooltip: tab.collectionNodeId != null ? 'Update Request' : 'Save to Collection',
            onPressed: () => _handleSave(tab),
          ),
          SizedBox(width: layout.isCompact ? 4 : 8),
          IconButton(
            icon: Icon(
              settings.isVerticalLayout ? Icons.view_column_rounded : Icons.view_agenda_rounded, 
              color: theme.colorScheme.onSurface, 
              size: layout.isCompact ? 24 : 28
            ),
            tooltip: settings.isVerticalLayout ? 'Horizontal Layout' : 'Vertical Layout',
            onPressed: () => ref.read(settingsProvider.notifier).updateVerticalLayout(!settings.isVerticalLayout),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestConfig(BuildContext context, HttpRequestTabModel tab, LayoutConstants layout) {
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
            labelStyle: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.w900),
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
                  _buildBodyEditor(context, layout),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyEditor(BuildContext context, LayoutConstants layout) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: CodeEditor(
        controller: _bodyController!,
        wordWrap: true,
        style: CodeEditorStyle(
          fontSize: 13,
          fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
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

  Widget _buildResponseSection(BuildContext context, HttpRequestTabModel tab, LayoutConstants layout) {
    final theme = Theme.of(context);
    if (tab.statusCode == null && !tab.isSending) {
       return Center(child: Column(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           Icon(Icons.bolt, size: layout.isCompact ? 48 : 64, color: theme.colorScheme.secondary),
           SizedBox(height: layout.sectionSpacing),
           Text('HIT SEND TO GET A RESPONSE', style: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
         ],
       ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: layout.isCompact ? 8.0 : 12.0),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (tab.statusCode != null)
                _ResponseMetadataItem(label: 'STATUS', value: tab.statusCode.toString(), color: _getStatusColor(tab.statusCode!), layout: layout),
              if (tab.durationMs != null)
                 _ResponseMetadataItem(label: 'TIME', value: '${tab.durationMs} ms', color: theme.colorScheme.secondary, layout: layout),
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
                  labelStyle: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.w900),
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
                        _buildResponseBody(context, tab, layout),
                        _buildResponseHeaders(context, tab, layout),
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

  Widget _buildResponseBody(BuildContext context, HttpRequestTabModel tab, LayoutConstants layout) {
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
            fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
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

  Widget _buildResponseHeaders(BuildContext context, HttpRequestTabModel tab, LayoutConstants layout) {
    final theme = Theme.of(context);
    if (tab.responseHeaders == null) return const SizedBox();
    return ListView(
      children: tab.responseHeaders!.entries.map((e) => ListTile(
        dense: true,
        title: Text(e.key.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: layout.fontSizeNormal, color: theme.primaryColor)),
        subtitle: Text(e.value, style: TextStyle(fontSize: layout.fontSizeNormal, color: theme.colorScheme.onSurface)),
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
  final LayoutConstants layout;
  const _ResponseMetadataItem({required this.label, required this.value, this.color, required this.layout});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.only(right: layout.isCompact ? 8 : 12),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: layout.isCompact ? 4 : 8),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.2) ?? theme.primaryColor.withValues(alpha: 0.2),
        border: Border.all(color: theme.dividerColor, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: layout.fontSizeSmall, fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: layout.fontSizeNormal)),
        ],
      ),
    );
  }
}

class _KeyValueEditor extends ConsumerStatefulWidget {
  final Map<String, String> items;
  final Function(Map<String, String>) onChanged;

  const _KeyValueEditor({required this.items, required this.onChanged});

  @override
  ConsumerState<_KeyValueEditor> createState() => _KeyValueEditorState();
}

class _KeyValueEditorState extends ConsumerState<_KeyValueEditor> {
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
    final settings = ref.watch(settingsProvider);
    final layout = LayoutConstants(settings.isCompactMode);

    return ListView.builder(
      padding: EdgeInsets.all(layout.isCompact ? 8 : 12),
      itemCount: _keyControllers.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(bottom: layout.isCompact ? 8.0 : 12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'KEY', 
                    isDense: true, 
                    contentPadding: EdgeInsets.all(layout.isCompact ? 8 : 12)
                  ),
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
              SizedBox(width: layout.isCompact ? 8 : 12),
              Expanded(
                child: TextField(
                  style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'VALUE', 
                    isDense: true, 
                    contentPadding: EdgeInsets.all(layout.isCompact ? 8 : 12)
                  ),
                  controller: _valControllers[index],
                  onChanged: (val) {
                     _update();
                  },
                ),
              ),
              SizedBox(width: layout.isCompact ? 4 : 8),
              IconButton(
                icon: Icon(Icons.delete_outline, size: layout.isCompact ? 20 : 24, color: Colors.red),
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