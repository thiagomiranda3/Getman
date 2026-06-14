import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/assertion_result.dart';
import 'package:getman/core/domain/entities/extraction_result.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/branded_tab_bar.dart';
import 'package:getman/core/utils/byte_format.dart';
import 'package:getman/core/utils/cookie_parser.dart';
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
                    _ResponseMetadataItem(label: 'STATUS', value: response.statusCode.toString(), color: context.appPalette.statusAccent(response.statusCode), layout: layout),
                    _ResponseMetadataItem(label: 'TIME', value: '${response.durationMs} ms', color: theme.colorScheme.secondary, layout: layout),
                    _ResponseMetadataItem(label: 'SIZE', value: formatBytes(responseSizeBytes(response)), color: theme.colorScheme.secondary, layout: layout),
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
                            _ResponseBodyView(tabId: tabId, responseController: responseController),
                            _ResponseHeadersView(tabId: tabId),
                            _ResponseCookiesView(tabId: tabId),
                            _ResponseTestsView(tabId: tabId),
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

  // Pretty (prettified JSON) vs Raw (verbatim body). Applies to the normal,
  // sub-threshold path; the large-response banner has its own controls.
  bool _raw = false;

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

    // Normal path — prettify (or pass through verbatim in raw mode), then load
    // into the editor.
    final text = _raw ? (rawBody ?? '') : await JsonUtils.prettify(rawBody);
    // Only apply if no newer sync was started and we're still mounted.
    if (!mounted || syncId != _pendingSyncId) return;
    widget.responseController.text = text;
    // Clear large mode if a previous response triggered it.
    if (_largeBody != null) {
      setState(() {
        _largeBody = null;
        _showFullPreview = false;
        _highlightingOptedIn = false;
      });
    }
  }

  void _setRaw(bool raw) {
    if (_raw == raw) return;
    setState(() => _raw = raw);
    final body = context.read<TabsBloc>().state.tabs.byId(widget.tabId)?.response?.body;
    _syncBody(body);
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
      child: _largeBody != null ? _buildLargeMode(context) : _buildSmallMode(),
    );
  }

  /// Sub-threshold view: a Pretty/Raw toggle above the editor.
  Widget _buildSmallMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PrettyRawToggle(raw: _raw, onChanged: _setRaw),
        Expanded(child: _buildEditorMode()),
      ],
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
    final sizeLabel = formatBytes(body.length);

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

class _PrettyRawToggle extends StatelessWidget {
  final bool raw;
  final ValueChanged<bool> onChanged;
  const _PrettyRawToggle({required this.raw, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: layout.pagePadding,
        vertical: layout.isCompact ? 4 : 6,
      ),
      child: Row(
        children: [
          _seg(context, 'PRETTY', !raw, () => onChanged(false)),
          SizedBox(width: layout.tabSpacing),
          _seg(context, 'RAW', raw, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, String label, bool active, VoidCallback onTap) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final activeBg = context.appPalette.selectorActive;
    final onActive = ThemeData.estimateBrightnessForColor(activeBg) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return context.appDecoration.wrapInteractive(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: layout.badgePaddingHorizontal + 4,
          vertical: layout.badgePaddingVertical + 2,
        ),
        decoration: BoxDecoration(
          color: active ? activeBg : Colors.transparent,
          border: Border.all(color: theme.dividerColor, width: layout.borderThin),
          borderRadius: BorderRadius.circular(context.appShape.buttonRadius),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: layout.fontSizeSmall,
            fontWeight: context.appTypography.displayWeight,
            color: active ? onActive : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ResponseCookiesView extends StatelessWidget {
  final String tabId;
  const _ResponseCookiesView({required this.tabId});

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
        final headers = state.tabs.byId(tabId)?.response?.headers;
        if (headers == null) return const SizedBox();

        String? setCookie;
        for (final e in headers.entries) {
          if (e.key.toLowerCase() == 'set-cookie') {
            setCookie = e.value;
            break;
          }
        }
        final cookies = CookieParser.parse(setCookie);

        if (cookies.isEmpty) {
          return Center(
            child: Text(
              'NO COOKIES',
              style: TextStyle(
                fontSize: layout.fontSizeTitle,
                fontWeight: context.appTypography.displayWeight,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: cookies.length,
          itemBuilder: (context, index) {
            final c = cookies[index];
            return ListTile(
              dense: true,
              title: Text(
                c.name,
                style: TextStyle(
                  fontWeight: context.appTypography.titleWeight,
                  fontSize: layout.fontSizeNormal,
                  color: theme.primaryColor,
                ),
              ),
              subtitle: Text(
                c.attributes.isEmpty ? c.value : '${c.value}\n${c.attributes}',
                style: TextStyle(fontSize: layout.fontSizeNormal, color: theme.colorScheme.onSurface),
              ),
            );
          },
        );
      },
    );
  }
}

class _ResponseTestsView extends StatelessWidget {
  final String tabId;
  const _ResponseTestsView({required this.tabId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        return p?.assertionResults != n?.assertionResults ||
            p?.extractionResults != n?.extractionResults;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();
        final assertions = tab.assertionResults;
        final extractions = tab.extractionResults;

        if (assertions.isEmpty && extractions.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(layout.pagePadding),
              child: Text(
                'NO RULES — ADD EXTRACTIONS OR ASSERTIONS IN THE RULES TAB',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.titleWeight,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          );
        }

        final passed = assertions.where((a) => a.passed).length;
        return ListView(
          padding: EdgeInsets.all(layout.pagePadding),
          children: [
            if (assertions.isNotEmpty) ...[
              _testsSummary(context, passed, assertions.length),
              SizedBox(height: layout.tabSpacing),
              for (final a in assertions) _assertionRow(context, a),
            ],
            if (extractions.isNotEmpty) ...[
              SizedBox(height: layout.sectionSpacing),
              Text('CAPTURED',
                  style: TextStyle(
                      fontSize: layout.fontSizeSmall,
                      fontWeight: context.appTypography.displayWeight,
                      color: theme.colorScheme.secondary)),
              SizedBox(height: layout.tabSpacing),
              for (final e in extractions) _extractionRow(context, e),
            ],
          ],
        );
      },
    );
  }

  Widget _testsSummary(BuildContext context, int passed, int total) {
    final layout = context.appLayout;
    final allPassed = passed == total;
    final color = allPassed ? context.appPalette.statusSuccess : context.appPalette.statusError;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: layout.isCompact ? 4 : 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        border: Border.all(color: Theme.of(context).dividerColor, width: layout.borderThin),
      ),
      child: Text(
        '$passed / $total PASSED',
        style: TextStyle(
          color: context.appPalette.onColor(color),
          fontWeight: context.appTypography.displayWeight,
          fontSize: layout.fontSizeNormal,
        ),
      ),
    );
  }

  Widget _assertionRow(BuildContext context, AssertionResult a) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final color = a.passed ? context.appPalette.statusSuccess : context.appPalette.statusError;
    return Padding(
      padding: EdgeInsets.only(bottom: layout.tabSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + (below) the PASS/FAIL word — color is never the only signal.
          Icon(a.passed ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: color, size: layout.iconSize),
          SizedBox(width: layout.tabSpacing),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a.passed ? 'PASS' : 'FAIL'} · ${a.label}',
                    style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                        color: theme.colorScheme.onSurface)),
                Text('got: ${a.actual}',
                    style: TextStyle(
                        fontSize: layout.fontSizeSmall,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _extractionRow(BuildContext context, ExtractionResult e) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final color = e.matched ? context.appPalette.statusSuccess : context.appPalette.statusError;
    return Padding(
      padding: EdgeInsets.only(bottom: layout.tabSpacing),
      child: Row(
        children: [
          Icon(e.matched ? Icons.download_done : Icons.search_off,
              color: color, size: layout.smallIconSize),
          SizedBox(width: layout.tabSpacing),
          Expanded(
            child: Text(
              e.matched ? '{{${e.variable}}} = ${e.value}' : '{{${e.variable}}} — not found',
              style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  color: theme.colorScheme.onSurface),
            ),
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
          Text('$label: ', style: TextStyle(color: context.appPalette.onColor(baseColor), fontSize: layout.fontSizeSmall, fontWeight: context.appTypography.titleWeight)),
          Text(value, style: TextStyle(color: context.appPalette.onColor(baseColor), fontWeight: context.appTypography.displayWeight, fontSize: layout.fontSizeNormal)),
        ],
      ),
    );
  }
}
