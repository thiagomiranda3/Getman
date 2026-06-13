import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/branded_tab_bar.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shimmer/shimmer.dart';

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
            p.response?.durationMs != n.response?.durationMs;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();

        if (tab.isSending) {
          final shimmerFill = theme.colorScheme.onSurface.withValues(alpha: 0.08);
          return Shimmer.fromColors(
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
          );
        }

        final response = tab.response;
        if (response == null) {
           return Center(child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               Icon(Icons.bolt, size: layout.isCompact ? 48 : 64, color: theme.colorScheme.secondary),
               SizedBox(height: layout.sectionSpacing),
               Text('HIT SEND TO GET A RESPONSE', style: TextStyle(fontSize: layout.fontSizeTitle, fontWeight: context.appTypography.displayWeight, color: theme.colorScheme.onSurface)),
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
                    _ResponseMetadataItem(label: 'STATUS', value: response.statusCode.toString(), color: context.appPalette.statusAccent(response.statusCode), layout: layout),
                    _ResponseMetadataItem(label: 'TIME', value: '${response.durationMs} ms', color: theme.colorScheme.secondary, layout: layout),
                  ],
                ),
              ),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const BrandedTabBar(labels: ['BODY', 'HEADERS']),
                    Expanded(
                      child: Container(
                        decoration: context.appDecoration.panelBox(context, offset: 0),
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
}

class _ResponseBodyView extends StatefulWidget {
  final String tabId;
  final CodeLineEditingController responseController;
  const _ResponseBodyView({required this.tabId, required this.responseController});

  @override
  State<_ResponseBodyView> createState() => _ResponseBodyViewState();
}

class _ResponseBodyViewState extends State<_ResponseBodyView> {
  int _pendingSyncId = 0;

  // Large-mode state: non-null when the current body exceeds the threshold.
  String? _largeBody;
  bool _showFullPreview = false;
  bool _highlightingOptedIn = false;

  @override
  void initState() {
    super.initState();
    final tab = context.read<TabsBloc>().state.tabs.byId(widget.tabId);
    _syncBody(tab?.response?.body);
  }

  Future<void> _syncBody(String? rawBody) async {
    final syncId = ++_pendingSyncId;

    if (rawBody != null && rawBody.length > kLargeResponseViewerChars) {
      // Large path — skip prettify and editor; go to plain-text mode.
      if (!mounted || syncId != _pendingSyncId) return;
      setState(() {
        _largeBody = rawBody;
        _showFullPreview = false;
        _highlightingOptedIn = false;
      });
      return;
    }

    // Normal path — prettify then load into the editor.
    final prettified = await JsonUtils.prettify(rawBody);
    // Only apply if no newer sync was started and we're still mounted.
    if (!mounted || syncId != _pendingSyncId) return;
    widget.responseController.text = prettified;
    // Clear large mode if a previous response triggered it.
    if (_largeBody != null) {
      setState(() {
        _largeBody = null;
        _showFullPreview = false;
        _highlightingOptedIn = false;
      });
    }
  }

  Future<void> _prettifyAndOptIn() async {
    final body = _largeBody;
    if (body == null) return;
    final syncId = ++_pendingSyncId;
    final prettified = await JsonUtils.prettify(body);
    if (!mounted || syncId != _pendingSyncId) return;
    widget.responseController.text = prettified;
    setState(() => _highlightingOptedIn = true);
  }

  String _humanSize(int chars) {
    if (chars < 1024) return '$chars B';
    final kb = chars / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) {
        final prevTab = prev.tabs.byId(widget.tabId);
        final nextTab = next.tabs.byId(widget.tabId);
        return prevTab?.response?.body != nextTab?.response?.body;
      },
      listener: (context, state) {
        final tab = state.tabs.byId(widget.tabId);
        _syncBody(tab?.response?.body);
      },
      child: _largeBody != null ? _buildLargeMode(context) : _buildEditorMode(),
    );
  }

  Widget _buildEditorMode() {
    return SizedBox(
      width: double.infinity,
      child: JsonCodeEditor(
        controller: widget.responseController,
        readOnly: true,
        wordWrap: _highlightingOptedIn ? false : true,
      ),
    );
  }

  Widget _buildLargeMode(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final body = _largeBody!;
    final sizeLabel = _humanSize(body.length);

    final displayText = _showFullPreview
        ? body
        : body.substring(0, body.length.clamp(0, kLargeResponsePreviewChars));
    final isTruncated = !_showFullPreview && body.length > kLargeResponsePreviewChars;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner row
        ColoredBox(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: layout.pagePadding,
              vertical: layout.pagePadding / 2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _highlightingOptedIn
                        ? 'LARGE RESPONSE ($sizeLabel) — HIGHLIGHTING ENABLED'
                        : 'LARGE RESPONSE ($sizeLabel) — HIGHLIGHTING DISABLED',
                    style: TextStyle(
                      fontSize: layout.fontSizeSmall,
                      fontWeight: typography.titleWeight,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (!_highlightingOptedIn) ...[
                  TextButton(
                    onPressed: _prettifyAndOptIn,
                    child: Text(
                      'PRETTIFY ANYWAY',
                      style: TextStyle(
                        fontSize: layout.fontSizeSmall,
                        fontWeight: typography.titleWeight,
                      ),
                    ),
                  ),
                  if (isTruncated)
                    TextButton(
                      onPressed: () => setState(() => _showFullPreview = true),
                      child: Text(
                        'SHOW FULL',
                        style: TextStyle(
                          fontSize: layout.fontSizeSmall,
                          fontWeight: typography.titleWeight,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        // Body — editor when opted-in, plain text otherwise
        Expanded(
          child: _highlightingOptedIn
              ? _buildEditorMode()
              : ColoredBox(
                  color: palette.codeBackground,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(layout.pagePadding),
                    child: SelectableText(
                      displayText,
                      style: TextStyle(
                        fontFamily: typography.codeFontFamily,
                        fontSize: layout.fontSizeCode,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ResponseHeadersView extends StatelessWidget {
  final String tabId;
  const _ResponseHeadersView({required this.tabId});

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        return !stringMapEquality.equals(p?.response?.headers, n?.response?.headers);
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        final headers = tab?.response?.headers;
        if (headers == null) return const SizedBox();

        final entries = headers.entries.toList();

        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final e = entries[index];
            return ListTile(
              dense: true,
              title: Text(e.key.toUpperCase(), style: TextStyle(fontWeight: context.appTypography.titleWeight, fontSize: layout.fontSizeNormal, color: theme.primaryColor)),
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
  final AppLayout layout;
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
            border: Border.all(color: theme.dividerColor, width: layout.borderThin),
            borderRadius: BorderRadius.circular(context.appShape.panelRadius),
          ),
          child: child,
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: Colors.white, fontSize: layout.fontSizeSmall, fontWeight: context.appTypography.titleWeight)),
          Text(value, style: TextStyle(color: Colors.white, fontWeight: context.appTypography.displayWeight, fontSize: layout.fontSizeNormal)),
        ],
      ),
    );
  }
}
