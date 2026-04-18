import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';
import 'package:getman/core/utils/curl_utils.dart';
import 'package:flutter/services.dart';

class UrlBar extends StatefulWidget {
  final String tabId;
  final VoidCallback onSave;
  const UrlBar({super.key, required this.tabId, required this.onSave});

  @override
  State<UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends State<UrlBar> {
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
                             context.read<TabsBloc>().add(UpdateTab(
                               tab.copyWith(config: parsedConfig),
                             ));
                             _urlController.text = parsedConfig.url;
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
                      icon: Icon(Icons.code, color: theme.colorScheme.secondary, size: layout.isCompact ? 24 : 28),
                      tooltip: 'Copy as cURL',
                      onPressed: () {
                        final curl = CurlUtils.generate(tab.config);
                        Clipboard.setData(ClipboardData(text: curl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('cURL command copied to clipboard'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: theme.colorScheme.secondary,
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
