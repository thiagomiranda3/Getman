import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/branded_tab_bar.dart';
import 'package:getman/core/utils/byte_format.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_body_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_cookies_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_headers_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_metadata_item.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_tests_view.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shimmer/shimmer.dart';

/// Shell for the response pane: the metadata row + the BODY/HEADERS/COOKIES/
/// TESTS tabs. Each tab body is its own widget under `response/`; this widget
/// orchestrates them and handles the sending / empty / loaded states.
class ResponseSection extends StatelessWidget {
  final String tabId;
  final CodeLineEditingController responseController;
  /// When false, the status/duration metadata row is omitted. Used by
  /// [UnifiedRequestPanel] which renders the metadata above the shared tab
  /// strip so it stays visible on every tab.
  final bool showMetadata;
  const ResponseSection({
    super.key,
    required this.tabId,
    required this.responseController,
    this.showMetadata = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        if (p == null || n == null) return true;
        return p.isSending != n.isSending ||
            p.response?.statusCode != n.response?.statusCode ||
            p.response?.durationMs != n.response?.durationMs ||
            p.response?.body.length != n.response?.body.length;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();

        if (tab.isSending) {
          final shimmerFill = theme.colorScheme.onSurface.withValues(alpha: 0.08);
          return Semantics(
            label: 'Loading response',
            liveRegion: true,
            child: Shimmer.fromColors(
            baseColor: theme.dividerColor.withValues(alpha: 0.1),
            highlightColor: theme.dividerColor.withValues(alpha: 0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(width: 100, height: 32, decoration: BoxDecoration(color: shimmerFill, border: Border.all(color: theme.dividerColor, width: layout.borderThin))),
                    const SizedBox(width: 12),
                    Container(width: 100, height: 32, decoration: BoxDecoration(color: shimmerFill, border: Border.all(color: theme.dividerColor, width: layout.borderThin))),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView.builder(
                    itemCount: 15,
                    itemBuilder: (_, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Container(width: double.infinity, height: 20, color: shimmerFill),
                    ),
                  ),
                ),
              ],
            ),
          ),
          );
        }

        final response = tab.response;
        if (response == null) {
           return Center(child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               ExcludeSemantics(child: Icon(Icons.bolt, size: layout.isCompact ? 48 : 64, color: theme.colorScheme.secondary)),
               SizedBox(height: layout.sectionSpacing),
               Text(context.appCopy.emptyResponse, textAlign: TextAlign.center, style: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: context.appTypography.displayWeight, color: theme.colorScheme.onSurface)),
             ],
           ));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showMetadata)
              Padding(
                padding: EdgeInsets.only(bottom: layout.isCompact ? 8.0 : 12.0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ResponseMetadataItem(label: 'STATUS', value: response.statusCode.toString(), color: context.appPalette.statusAccent(response.statusCode), layout: layout),
                    ResponseMetadataItem(label: 'TIME', value: '${response.durationMs} ms', color: theme.colorScheme.secondary, layout: layout),
                    ResponseMetadataItem(label: 'SIZE', value: formatBytes(responseSizeBytes(response)), color: theme.colorScheme.secondary, layout: layout),
                  ],
                ),
              ),
            Expanded(
              child: DefaultTabController(
                length: 4,
                child: Column(
                  children: [
                    const BrandedTabBar(labels: ['BODY', 'HEADERS', 'COOKIES', 'TESTS']),
                    Expanded(
                      child: Container(
                        decoration: context.appDecoration.panelBox(context, offset: 0),
                        child: TabBarView(
                          children: [
                            ResponseBodyView(tabId: tabId, responseController: responseController),
                            ResponseHeadersView(tabId: tabId),
                            ResponseCookiesView(tabId: tabId),
                            ResponseTestsView(tabId: tabId),
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
}
