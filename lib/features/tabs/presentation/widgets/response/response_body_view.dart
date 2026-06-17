import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/utils/json_path.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/response/json_tree_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_body_controls.dart';
import 'package:getman/features/tabs/presentation/widgets/response/response_large_body_view.dart';
import 'package:re_editor/re_editor.dart';
import 'package:uuid/uuid.dart';

/// How the response body is displayed in the sub-threshold path.
enum _BodyMode { pretty, raw, tree }

/// BODY tab: renders the response body. Sub-threshold bodies go through a
/// Pretty/Raw/Tree toggle (the JSON editor or a collapsible tree); bodies over
/// [kLargeResponseViewerChars] fall back to a plain-text viewer (unless the
/// user opts into highlighting). TREE is only offered for JSON object/array
/// bodies under the large threshold.
class ResponseBodyView extends StatefulWidget {
  const ResponseBodyView({
    required this.tabId,
    required this.responseController,
    super.key,
  });
  final String tabId;
  final CodeLineEditingController responseController;

  @override
  State<ResponseBodyView> createState() => _ResponseBodyViewState();
}

class _ResponseBodyViewState extends State<ResponseBodyView> {
  int _pendingSyncId = 0;

  // Pretty (prettified JSON) / Raw (verbatim) / Tree (collapsible). Applies to
  // the normal, sub-threshold path; the large-response banner has its own
  // controls.
  _BodyMode _mode = _BodyMode.pretty;

  // Decoded JSON for the tree view, cached so the same instance survives
  // rebuilds (a fresh decode would reset the tree's expansion state). Null +
  // false when the body isn't a JSON object/array or is in large mode.
  Object? _decoded;
  bool _treeAvailable = false;

  // Large-mode state: non-null when the current body exceeds the threshold.
  String? _largeBody;
  bool _showFullPreview = false;
  bool _highlightingOptedIn = false;

  @override
  void initState() {
    super.initState();
    final tab = context.read<TabsBloc>().state.tabs.byId(widget.tabId);
    unawaited(_syncBody(tab?.response?.body));
  }

  Future<void> _syncBody(String? rawBody) async {
    final syncId = ++_pendingSyncId;

    if (rawBody != null && rawBody.length > kLargeResponseViewerChars) {
      // Opt-in setting: prettify + highlight large bodies automatically (the
      // user accepts the render cost). The over-1-MB placeholder is a known
      // non-JSON sentinel, so it always stays in plain-text mode.
      final autoPrettify =
          context
              .read<SettingsBloc>()
              .state
              .settings
              .alwaysPrettifyLargeResponses &&
          rawBody != kResponseBodyTooLargePlaceholder;
      if (autoPrettify) {
        final prettified = await JsonUtils.prettify(rawBody);
        if (!mounted || syncId != _pendingSyncId) return;
        widget.responseController.text = prettified;
        setState(() {
          _largeBody = rawBody;
          _showFullPreview = false;
          _highlightingOptedIn = true;
          _clearTreeState();
        });
        return;
      }
      // Large path — skip prettify and editor; go to plain-text mode.
      if (!mounted || syncId != _pendingSyncId) return;
      setState(() {
        _largeBody = rawBody;
        _showFullPreview = false;
        _highlightingOptedIn = false;
        _clearTreeState();
      });
      return;
    }

    // Normal path — prettify (or pass through verbatim in raw mode), then load
    // into the editor. The over-1-MB sentinel is known non-JSON, so render it
    // as plain text rather than spawning an isolate to fail-parse it.
    final isPlaceholder = rawBody == kResponseBodyTooLargePlaceholder;
    final text = (_mode == _BodyMode.raw || isPlaceholder)
        ? (rawBody ?? '')
        : await JsonUtils.prettify(rawBody);
    // Only apply if no newer sync was started and we're still mounted.
    if (!mounted || syncId != _pendingSyncId) return;
    widget.responseController.text = text;
    // Decode once for the tree view; cache the instance so the tree keeps its
    // expansion state across rebuilds. Falls back out of tree mode if the body
    // isn't a JSON object/array.
    final decoded = (rawBody == null || isPlaceholder)
        ? null
        : JsonPath.tryDecode(rawBody);
    final treeOk = decoded is Map || decoded is List;
    setState(() {
      _largeBody = null;
      _showFullPreview = false;
      _highlightingOptedIn = false;
      _decoded = decoded;
      _treeAvailable = treeOk;
      if (_mode == _BodyMode.tree && !treeOk) _mode = _BodyMode.pretty;
    });
  }

  /// Creates a JSONPath extraction rule from a tree node and appends it to the
  /// active request's chaining rules — the bridge from "I see this value" to
  /// "capture it into {{var}}". The user refines the variable name in RULES.
  void _extractToVariable(String jsonPath) {
    if (!JsonPath.isValid(jsonPath)) {
      showAppSnackBar(context, 'Cannot extract: unsupported path');
      return;
    }
    final configId = context
        .read<TabsBloc>()
        .state
        .tabs
        .byId(widget.tabId)
        ?.config
        .id;
    if (configId == null) return;
    final varName = _suggestVariableName(jsonPath);
    context.read<RulesBloc>().add(
      AddExtractionRule(
        configId: configId,
        rule: ExtractionRule(
          id: const Uuid().v4(),
          expression: jsonPath,
          targetVariable: varName,
        ),
      ),
    );
    showAppSnackBar(context, 'Added extraction → {{$varName}} (edit in RULES)');
  }

  /// Derives a starting variable name from a JSONPath's last named segment;
  /// falls back to `value` for array-index or unnamed tails.
  static String _suggestVariableName(String jsonPath) {
    var raw = '';
    final dot = RegExp(r'\.([A-Za-z_$][\w$]*)$').firstMatch(jsonPath);
    if (dot != null) {
      raw = dot.group(1)!;
    } else {
      final bracket = RegExp(r'\[(.+)\]$').firstMatch(jsonPath);
      if (bracket != null) {
        raw = bracket.group(1)!.replaceAll(RegExp('''['"]'''), '');
      }
    }
    final cleaned = raw.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
    if (cleaned.isEmpty || RegExp(r'^[0-9]+$').hasMatch(cleaned)) {
      return 'value';
    }
    return cleaned;
  }

  /// Resets tree state (large mode has no tree). Call inside a setState.
  void _clearTreeState() {
    _decoded = null;
    _treeAvailable = false;
    if (_mode == _BodyMode.tree) _mode = _BodyMode.pretty;
  }

  void _setMode(_BodyMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    // Switching the editor's pretty/raw rendering needs a re-sync; switching to
    // the tree uses the already-cached decode (no editor reload).
    if (mode != _BodyMode.tree) {
      final body = context
          .read<TabsBloc>()
          .state
          .tabs
          .byId(widget.tabId)
          ?.response
          ?.body;
      unawaited(_syncBody(body));
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

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<TabsBloc, TabsState>(
          listenWhen: (prev, next) {
            final prevTab = prev.tabs.byId(widget.tabId);
            final nextTab = next.tabs.byId(widget.tabId);
            return prevTab?.response?.body != nextTab?.response?.body;
          },
          listener: (context, state) {
            final tab = state.tabs.byId(widget.tabId);
            unawaited(_syncBody(tab?.response?.body));
          },
        ),
        // Re-render the current body when the user flips the prettify-large
        // setting, so the change is visible without re-sending.
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (prev, next) =>
              prev.settings.alwaysPrettifyLargeResponses !=
              next.settings.alwaysPrettifyLargeResponses,
          listener: (context, state) {
            final body = context
                .read<TabsBloc>()
                .state
                .tabs
                .byId(widget.tabId)
                ?.response
                ?.body;
            unawaited(_syncBody(body));
          },
        ),
      ],
      child: _largeBody != null ? _buildLargeMode() : _buildSmallMode(),
    );
  }

  /// The text a Copy action should put on the clipboard: the verbatim large
  /// body when highlighting is off, otherwise whatever the editor shows.
  String _copyableText() => _largeBody != null && !_highlightingOptedIn
      ? _largeBody!
      : widget.responseController.text;

  /// Sub-threshold view: a Pretty/Raw/Tree toggle (+ copy) above the body.
  Widget _buildSmallMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // PRETTY/RAW/TREE toggle (left) + the copy/save/compare cluster
        // (right). A Wrap keeps them side by side while the pane is wide
        // enough, and drops the cluster onto a second line the moment the two
        // would collide — so dragging the splitter narrow degrades gracefully
        // instead of throwing a RenderFlex overflow. spaceBetween pins the
        // toggle left and the cluster right on the one-line layout; both
        // children also reflow internally (see _BodyModeToggle and
        // ResponseBodyControls) so neither overflows in an extremely narrow
        // pane.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _BodyModeToggle(
              mode: _mode,
              treeEnabled: _treeAvailable,
              onChanged: _setMode,
            ),
            ResponseBodyControls(
              tabId: widget.tabId,
              getCopyableText: _copyableText,
            ),
          ],
        ),
        Expanded(
          child: _mode == _BodyMode.tree
              ? JsonTreeView(data: _decoded, onExtract: _extractToVariable)
              : _buildEditorMode(),
        ),
      ],
    );
  }

  Widget _buildEditorMode() {
    return SizedBox(
      width: double.infinity,
      child: JsonCodeEditor(
        controller: widget.responseController,
        readOnly: true,
        wordWrap: !_highlightingOptedIn,
      ),
    );
  }

  Widget _buildLargeMode() {
    final palette = context.appPalette;
    final typography = context.appTypography;
    final layout = context.appLayout;
    final theme = Theme.of(context);
    final body = _largeBody!;
    final displayText = _showFullPreview
        ? body
        : body.substring(0, body.length.clamp(0, kLargeResponsePreviewChars));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner row — extracted to ResponseLargeBodyView.
        ResponseLargeBodyView(
          body: body,
          showFullPreview: _showFullPreview,
          highlightingOptedIn: _highlightingOptedIn,
          onPrettifyAndOptIn: _prettifyAndOptIn,
          onShowFull: () => setState(() => _showFullPreview = true),
          controls: ResponseBodyControls(
            tabId: widget.tabId,
            getCopyableText: _copyableText,
          ),
        ),
        // Body — editor when opted-in, plain text otherwise. Kept here so the
        // editor widget occupies the same Column.children[1] position in both
        // small and large mode, preventing re_editor state teardown on switch.
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

class _BodyModeToggle extends StatelessWidget {
  const _BodyModeToggle({
    required this.mode,
    required this.treeEnabled,
    required this.onChanged,
  });
  final _BodyMode mode;
  final bool treeEnabled;
  final ValueChanged<_BodyMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: layout.pagePadding,
        vertical: layout.isCompact ? 4 : 6,
      ),
      // Wrap (not Row) so the segments reflow onto a second line in an
      // extremely narrow pane instead of overflowing their fixed-width
      // segments.
      child: Wrap(
        spacing: layout.tabSpacing,
        runSpacing: layout.tabSpacing,
        children: [
          _seg(context, 'PRETTY', mode == _BodyMode.pretty, true, () {
            onChanged(_BodyMode.pretty);
          }),
          _seg(context, 'RAW', mode == _BodyMode.raw, true, () {
            onChanged(_BodyMode.raw);
          }),
          _seg(context, 'TREE', mode == _BodyMode.tree, treeEnabled, () {
            onChanged(_BodyMode.tree);
          }),
        ],
      ),
    );
  }

  Widget _seg(
    BuildContext context,
    String label,
    bool active,
    bool enabled,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final activeBg = context.appPalette.selectorActive;
    final activeIsDark =
        ThemeData.estimateBrightnessForColor(activeBg) == Brightness.dark;
    // Deliberate contrast: a readable foreground picked from the dynamic,
    // theme-derived `activeBg` brightness (CLAUDE.md §4.8 exception) — not a
    // themeable surface color.
    // ignore: avoid_hardcoded_brand_colors
    final onActive = activeIsDark ? Colors.white : Colors.black;
    final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.35);
    final seg = Container(
      key: ValueKey('body_toggle_$label'),
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
          color: !enabled
              ? disabledColor
              : (active ? onActive : theme.colorScheme.onSurface),
        ),
      ),
    );
    if (!enabled) {
      return Tooltip(
        message: 'Tree view needs a JSON object/array under the size limit',
        child: seg,
      );
    }
    return context.appDecoration.wrapInteractive(onTap: onTap, child: seg);
  }
}
