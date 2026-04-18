import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:shimmer/shimmer.dart';
import 'package:re_editor/re_editor.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';
import 'response_body_view.dart';
import 'response_headers_view.dart';

class ResponseSection extends StatelessWidget {
  final String tabId;
  final CodeLineEditingController responseController;
  const ResponseSection({super.key, required this.tabId, required this.responseController});

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
                    ResponseMetadataItem(label: 'STATUS', value: tab.statusCode.toString(), color: _getStatusColor(tab.statusCode!), layout: layout),
                  if (tab.durationMs != null)
                    ResponseMetadataItem(label: 'TIME', value: '${tab.durationMs} ms', color: theme.colorScheme.secondary, layout: layout),
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
                            ResponseBodyView(tabId: tabId, responseController: responseController),
                            ResponseHeadersView(tabId: tabId),
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

class ResponseMetadataItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final LayoutExtension layout;
  const ResponseMetadataItem({super.key, required this.label, required this.value, this.color, required this.layout});

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
