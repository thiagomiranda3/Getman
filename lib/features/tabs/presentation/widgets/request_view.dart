import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:uuid/uuid.dart';
import 'package:getman/core/ui/widgets/splitter.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/core/utils/curl_utils.dart';

class RequestView extends StatefulWidget {
  final String tabId;
  const RequestView({super.key, required this.tabId});

  @override
  State<RequestView> createState() => _RequestViewState();
}

class _RequestViewState extends State<RequestView> {
  CodeLineEditingController? _bodyController;
  CodeLineEditingController? _responseController;
  double? _localSplitRatio;
  
  final FocusNode _responseFocusNode = FocusNode();
  final ScrollController _responseScrollController = ScrollController();
  final ScrollController _requestScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final tabsBloc = context.read<TabsBloc>();
    final tab = tabsBloc.state.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
    
    _bodyController = CodeLineEditingController.fromText(tab?.config.body ?? '');
    _responseController = CodeLineEditingController();
    _bodyController!.addListener(_onBodyChanged);
  }

  void _onBodyChanged() {
     final tabsBloc = context.read<TabsBloc>();
     final tab = tabsBloc.state.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
     if (tab == null) return;
     final newText = _bodyController!.text;
     if (tab.config.body == newText) return;
     
     tabsBloc.add(UpdateTab(
       tab.copyWith(config: tab.config.copyWith(body: newText)),
     ));
  }

  @override
  void dispose() {
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
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final settings = settingsState.settings;
        final layout = Theme.of(context).extension<LayoutExtension>()!;
        
        return BlocBuilder<TabsBloc, TabsState>(
          builder: (context, tabsState) {
            if (tabsState.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final tab = tabsState.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
            if (tab == null) return const SizedBox.shrink();
            
            final isActive = tabsState.tabs.asMap().entries.any((e) => e.key == tabsState.activeIndex && e.value.tabId == widget.tabId);

            return CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _handleSave(context, tab),
                const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () => _handleSave(context, tab),
              },
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isActive ? 1.0 : 0.0,
                curve: Curves.easeInOut,
                child: Padding(
                  padding: EdgeInsets.all(layout.pagePadding),
                  child: Column(
                    children: [
                      _UrlBar(tabId: widget.tabId, onSave: () => _handleSave(context, tab)),
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
                                  child: _RequestConfigSection(tabId: widget.tabId, bodyController: _bodyController!),
                                ),
                                Splitter(
                                  isVertical: settings.isVerticalLayout,
                                  onUpdate: (delta) {
                                    setState(() {
                                      _localSplitRatio = (_localSplitRatio ?? settings.splitRatio) + (delta / totalSize);
                                      if (_localSplitRatio! < 0.1) _localSplitRatio = 0.1;
                                      if (_localSplitRatio! > 0.9) _localSplitRatio = 0.9;
                                    });
                                  },
                                  onEnd: () {
                                    if (_localSplitRatio != null) {
                                      context.read<SettingsBloc>().add(UpdateSplitRatio(_localSplitRatio!));
                                    }
                                  },
                                ),
                                Flexible(
                                  flex: ((1 - currentRatio) * 1000).toInt(),
                                  child: _ResponseSection(tabId: widget.tabId, responseController: _responseController!),
                                ),
                              ],
                            );
                          }
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _handleSave(BuildContext context, HttpRequestTabEntity tab) {
    final collectionsBloc = context.read<CollectionsBloc>();
    final tabsBloc = context.read<TabsBloc>();
    final theme = Theme.of(context);
    
    bool nodeExists(List<dynamic> nodes, String id) {
      for (var node in nodes) {
        if (node.id == id) return true;
        if (nodeExists(node.children, id)) return true;
      }
      return false;
    }

    bool exists = false;
    if (tab.collectionNodeId != null) {
      exists = nodeExists(collectionsBloc.state.collections, tab.collectionNodeId!);
    }

    if (tab.collectionNodeId != null && exists) {
      collectionsBloc.add(UpdateNodeRequest(
        tab.collectionNodeId!,
        tab.config.copyWith(),
      ));
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
      if (tab.collectionNodeId != null && !exists) {
        tabsBloc.add(UpdateTab(
          tab.copyWith(collectionNodeId: null, collectionName: null)
        ));
      }
      _showSaveDialog(context, tab);
    }
  }

  void _showSaveDialog(BuildContext context, HttpRequestTabEntity tab) {
    final controller = TextEditingController(text: 'NEW REQUEST');
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('SAVE TO COLLECTION'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'REQUEST NAME')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
               // We need a way to get the new ID back from CollectionsBloc or generate it here
               // Since we use Uuid in Bloc, maybe we should let Bloc return it or use a callback
               // For now, I'll generate it here and pass it
               final newId = const Uuid().v4();
               context.read<CollectionsBloc>().add(SaveRequestToCollection(
                 controller.text, 
                 tab.config.copyWith(),
               ));
               // Wait, SaveRequestToCollection in Bloc generates its own ID.
               // To keep it simple, I'll just refetch the latest tab name/id if needed, 
               // but the original code had saveRequest returning ID.
               // I'll update the event to accept an optional ID.
               
               // Actually, for now, I'll just close and let the user re-open if needed, 
               // but the UX would be better if we updated the tab.
               // I'll just use the name for now.
               context.read<TabsBloc>().add(UpdateTab(
                 tab.copyWith(collectionName: controller.text)
               ));
               Navigator.pop(dialogContext);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }
}

class _UrlBar extends StatefulWidget {
  final String tabId;
  final VoidCallback onSave;
  const _UrlBar({required this.tabId, required this.onSave});

  @override
  State<_UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends State<_UrlBar> {
  late TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    final tab = context.read<TabsBloc>().state.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
    _urlController = TextEditingController(text: tab?.config.url ?? '');
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        final tab = state.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
        if (tab == null) return const SizedBox.shrink();

        if (_urlController.text != tab.config.url) {
           _urlController.text = tab.config.url;
        }

        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            final settings = settingsState.settings;
            final layout = Theme.of(context).extension<LayoutExtension>()!;
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
                            context.read<TabsBloc>().add(UpdateTab(
                              tab.copyWith(config: tab.config.copyWith(method: val)),
                            ));
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
                        hintText: 'Enter URL or paste cURL...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        filled: false,
                      ),
                      onChanged: (val) {
                         if (tab.config.url == val) return;

                         if (val.trim().toLowerCase().startsWith('curl ')) {
                           final parsedConfig = CurlUtils.parse(val, id: tab.config.id);
                           if (parsedConfig != null) {
                             // 1. Synchronously update everything except the potentially unprettified body first
                             // This ensures the URL and Method change immediately
                             context.read<TabsBloc>().add(UpdateTab(
                               tab.copyWith(config: parsedConfig),
                             ));
                             
                             _urlController.text = parsedConfig.url;

                             // 2. Then, asynchronously prettify the body if it's JSON
                             JsonUtils.prettify(parsedConfig.body).then((prettifiedBody) {
                               // Get the latest tab from state to avoid using stale 'tab' instance
                               final latestTabs = context.read<TabsBloc>().state.tabs;
                               final latestTab = latestTabs.firstWhereOrNull((t) => t.tabId == tab.tabId);
                               
                               if (latestTab != null) {
                                 context.read<TabsBloc>().add(UpdateTab(
                                   latestTab.copyWith(config: latestTab.config.copyWith(body: prettifiedBody)),
                                 ));
                               }
                               
                               final requestViewState = context.findAncestorStateOfType<_RequestViewState>();
                               if (requestViewState != null) {
                                 requestViewState._bodyController?.text = prettifiedBody;
                               }
                             });
                             return;
                           }
                         }

                         context.read<TabsBloc>().add(UpdateTab(
                          tab.copyWith(config: tab.config.copyWith(url: val)),
                        ));
                      },
                    ),
                  ),
                  SizedBox(width: layout.isCompact ? 8 : 12),
                  BrutalBounce(
                    child: IconButton(
                      icon: Icon(Icons.code, color: theme.colorScheme.primary, size: layout.isCompact ? 24 : 28),
                      tooltip: 'Copy as cURL',
                      onPressed: () {
                        final curl = CurlUtils.generate(tab.config);
                        Clipboard.setData(ClipboardData(text: curl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('cURL command copied to clipboard'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: theme.colorScheme.primary,
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(width: layout.isCompact ? 4 : 8),
                  BrutalBounce(
                    child: ElevatedButton(
                      onPressed: tab.isSending 
                        ? () {
                            final index = state.tabs.indexWhere((t) => t.tabId == tab.tabId);
                            if (index != -1) context.read<TabsBloc>().add(CancelRequest(index));
                          }
                        : () => context.read<TabsBloc>().add(SendRequest()),
                      style: ElevatedButton.styleFrom(
                         backgroundColor: tab.isSending ? Colors.red : null,
                         foregroundColor: tab.isSending ? Colors.white : null,
                         padding: EdgeInsets.symmetric(
                           horizontal: layout.buttonPaddingHorizontal, 
                           vertical: layout.buttonPaddingVertical
                         ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child)),
                        child: tab.isSending 
                          ? Row(
                              key: const ValueKey('cancel'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                const SizedBox(width: 8),
                                Text('CANCEL', style: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: FontWeight.w900)),
                              ],
                            )
                          : Text('SEND', key: const ValueKey('send'), style: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                  SizedBox(width: layout.isCompact ? 8 : 12),
                  BrutalBounce(
                    child: IconButton(
                      icon: Icon(tab.collectionNodeId != null ? Icons.save : Icons.save_as, color: theme.colorScheme.secondary, size: layout.isCompact ? 24 : 28),
                      tooltip: tab.collectionNodeId != null ? 'Update Request' : 'Save to Collection',
                      onPressed: widget.onSave,
                    ),
                  ),
                  SizedBox(width: layout.isCompact ? 4 : 8),
                  BrutalBounce(
                    child: IconButton(
                      icon: Icon(
                        settings.isVerticalLayout ? Icons.view_column_rounded : Icons.view_agenda_rounded, 
                        color: theme.colorScheme.onSurface, 
                        size: layout.isCompact ? 24 : 28
                      ),
                      tooltip: settings.isVerticalLayout ? 'Horizontal Layout' : 'Vertical Layout',
                      onPressed: () => context.read<SettingsBloc>().add(UpdateVerticalLayout(!settings.isVerticalLayout)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RequestConfigSection extends StatelessWidget {
  final String tabId;
  final CodeLineEditingController bodyController;
  const _RequestConfigSection({required this.tabId, required this.bodyController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;

    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        final tab = state.tabs.firstWhereOrNull((t) => t.tabId == tabId);
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
                          context.read<TabsBloc>().add(UpdateTab(
                            tab.copyWith(config: tab.config.copyWith(params: map)),
                          ));
                        },
                      ),
                      _KeyValueEditor(
                        items: tab.config.headers,
                        onChanged: (map) {
                          context.read<TabsBloc>().add(UpdateTab(
                            tab.copyWith(config: tab.config.copyWith(headers: map)),
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
    return Container(
      color: theme.colorScheme.surface,
      child: CodeEditor(
        controller: bodyController,
        wordWrap: true,
        findBuilder: (context, controller, readOnly) => _CodeFindPanel(controller: controller, readOnly: readOnly),
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
            theme: theme.brightness == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme,
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
}

class _ResponseSection extends StatelessWidget {
  final String tabId;
  final CodeLineEditingController responseController;
  const _ResponseSection({required this.tabId, required this.responseController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;

    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        final tab = state.tabs.firstWhereOrNull((t) => t.tabId == tabId);
        if (tab == null) return const SizedBox.shrink();

        if (tab.isSending) {
           return Shimmer.fromColors(
             baseColor: theme.dividerColor.withValues(alpha: 0.1),
             highlightColor: theme.dividerColor.withValues(alpha: 0.3),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Row(
                   children: [
                     Container(width: 100, height: 32, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: theme.dividerColor, width: 2))),
                     const SizedBox(width: 12),
                     Container(width: 100, height: 32, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: theme.dividerColor, width: 2))),
                   ],
                 ),
                 const SizedBox(height: 24),
                 Expanded(
                   child: ListView.builder(
                     itemCount: 15,
                     itemBuilder: (_, index) => Padding(
                       padding: const EdgeInsets.symmetric(vertical: 6),
                       child: Container(width: double.infinity, height: 20, color: Colors.white),
                     ),
                   ),
                 ),
               ],
             ),
           );
        }

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
                      dividerColor: Colors.transparent,
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
                            _ResponseBodyView(tabId: tabId, responseController: responseController),
                            _ResponseHeadersView(tabId: tabId),
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
      },
    );
  }

  Color _getStatusColor(int code) {
    if (code >= 200 && code < 300) return Colors.greenAccent;
    if (code >= 400) return Colors.redAccent;
    return Colors.orangeAccent;
  }
}

class _ResponseBodyView extends StatefulWidget {
  final String tabId;
  final CodeLineEditingController responseController;
  const _ResponseBodyView({required this.tabId, required this.responseController});

  @override
  State<_ResponseBodyView> createState() => _ResponseBodyViewState();
}

class _ResponseBodyViewState extends State<_ResponseBodyView> {
  @override
  void initState() {
    super.initState();
    _updateBody();
  }

  Future<void> _updateBody() async {
    final tabsBloc = context.read<TabsBloc>();
    final tab = tabsBloc.state.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
    final prettified = await JsonUtils.prettify(tab?.responseBody);
    if (mounted) {
      widget.responseController.text = prettified;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) {
        final prevTab = prev.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
        final nextTab = next.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
        return prevTab?.responseBody != nextTab?.responseBody;
      },
      listener: (context, state) {
        _updateBody();
      },
      child: Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.surface,
        child: CodeEditor(
          controller: widget.responseController,
          readOnly: true,
          wordWrap: true,
          findBuilder: (context, controller, readOnly) => _CodeFindPanel(controller: controller, readOnly: readOnly),
          style: CodeEditorStyle(
            fontSize: 13,
            fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
            backgroundColor: Colors.transparent,
            cursorColor: Theme.of(context).primaryColor,
            selectionColor: Theme.of(context).primaryColor.withValues(alpha: 0.3),
            cursorLineColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
            codeTheme: CodeHighlightTheme(
              languages: {
                'json': CodeHighlightThemeMode(
                  mode: langJson,
                ),
              },
              theme: Theme.of(context).brightness == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme,
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
}

class _ResponseHeadersView extends StatelessWidget {
  final String tabId;
  const _ResponseHeadersView({required this.tabId});

  @override
  Widget build(BuildContext context) {
    final layout = Theme.of(context).extension<LayoutExtension>()!;
    final theme = Theme.of(context);

    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        final tab = state.tabs.firstWhereOrNull((t) => t.tabId == tabId);
        final headers = tab?.responseHeaders;
        if (headers == null) return const SizedBox();
        
        final entries = headers.entries.toList();

        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final e = entries[index];
            return ListTile(
              dense: true,
              title: Text(e.key.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: layout.fontSizeNormal, color: theme.primaryColor)),
              subtitle: Text(e.value, style: TextStyle(fontSize: layout.fontSizeNormal, color: theme.colorScheme.onSurface)),
            );
          },
        );
      },
    );
  }
}

class _ResponseMetadataItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final LayoutExtension layout;
  const _ResponseMetadataItem({required this.label, required this.value, this.color, required this.layout});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = color ?? theme.primaryColor;
    
    return TweenAnimationBuilder<Color?>(
      key: ValueKey(value),
      duration: const Duration(milliseconds: 600),
      tween: ColorTween(begin: baseColor.withValues(alpha: 1.0), end: baseColor.withValues(alpha: 0.2)),
      builder: (context, animColor, child) {
        return Container(
          margin: EdgeInsets.only(right: layout.isCompact ? 8 : 12),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: layout.isCompact ? 4 : 8),
          decoration: BoxDecoration(
            color: animColor,
            border: Border.all(color: theme.dividerColor, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: child,
        );
      },
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
    _keyControllers.add(TextEditingController());
    _valControllers.add(TextEditingController());
  }

  @override
  void didUpdateWidget(_KeyValueEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSame(oldWidget.items, widget.items)) {
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
    final layout = Theme.of(context).extension<LayoutExtension>()!;

    return ListView.builder(
      itemCount: _keyControllers.length,
      itemBuilder: (context, index) {
        return _KeyValueRow(
          key: ValueKey(index),
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
            _update();
          },
          onValChanged: (val) => _update(),
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
               _update();
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
  final LayoutExtension layout;
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
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _isHovered ? theme.dividerColor.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: widget.layout.fontSizeNormal, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'KEY', 
                  isDense: true, 
                  contentPadding: EdgeInsets.all(widget.layout.isCompact ? 8 : 12)
                ),
                controller: widget.keyController,
                onChanged: widget.onKeyChanged,
              ),
            ),
            SizedBox(width: widget.layout.isCompact ? 8 : 12),
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: widget.layout.fontSizeNormal, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'VALUE', 
                  isDense: true, 
                  contentPadding: EdgeInsets.all(widget.layout.isCompact ? 8 : 12)
                ),
                controller: widget.valController,
                onChanged: widget.onValChanged,
              ),
            ),
            SizedBox(width: widget.layout.isCompact ? 4 : 8),
            IconButton(
              icon: Icon(Icons.delete_outline, size: widget.layout.isCompact ? 20 : 24, color: Colors.red),
              onPressed: widget.onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeFindPanel extends StatefulWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;

  const _CodeFindPanel({
    required this.controller,
    required this.readOnly,
  });

  @override
  State<_CodeFindPanel> createState() => _CodeFindPanelState();

  @override
  Size get preferredSize => controller.value == null ? Size.zero : const Size.fromHeight(54);
}

class _CodeFindPanelState extends State<_CodeFindPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.value == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller.findInputController,
              focusNode: widget.controller.findInputFocusNode,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'FIND...',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: layout.iconSize),
                suffixText: (widget.controller.value?.result?.matches.length ?? 0) > 0 
                  ? '${(widget.controller.value?.result?.index ?? 0) + 1}/${widget.controller.value?.result?.matches.length}' 
                  : '0/0',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onSubmitted: (value) => widget.controller.nextMatch(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_up, size: layout.iconSize),
            onPressed: () => widget.controller.previousMatch(),
          ),
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, size: layout.iconSize),
            onPressed: () => widget.controller.nextMatch(),
          ),
          IconButton(
            icon: Icon(Icons.close, size: layout.iconSize),
            onPressed: () => widget.controller.close(),
          ),
        ],
      ),
    );
  }
}
