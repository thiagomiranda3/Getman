import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/utils/json_path.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/core/utils/response_media.dart';
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
import 'package:getman/features/tabs/presentation/widgets/response/viewers/response_media_panel.dart';
import 'package:re_editor/re_editor.dart';
import 'package:uuid/uuid.dart';

/// How the response body is displayed in the sub-threshold path.
enum _BodyMode { pretty, raw, tree }

/// BODY tab: thin dispatcher. Routes non-textual responses to
/// [ResponseMediaPanel] and textual responses to [_TextualResponseBody].
class ResponseBodyView extends StatelessWidget {
  const ResponseBodyView({
    required this.tabId,
    required this.responseController,
    super.key,
  });
  final String tabId;
  final CodeLineEditingController responseController;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId)?.response;
        final n = next.tabs.byId(tabId)?.response;
        return p?.body != n?.body ||
            p?.bodyBytes?.length != n?.bodyBytes?.length ||
            contentTypeOf(p?.headers ?? const {}) !=
                contentTypeOf(n?.headers ?? const {});
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        final resp = tab?.response;
        final kind = classifyResponseMedia(
          contentType: contentTypeOf(resp?.headers ?? const {}),
          url: tab?.config.url,
          sniffBytes: resp?.bodyBytes,
        );
        if (resp != null && kind != ResponseMediaKind.textual) {
          return ResponseMediaPanel(tabId: tabId);
        }
        return _TextualResponseBody(
          tabId: tabId,
          responseController: responseController,
        );
      },
    );
  }
}

/// BODY tab: renders the response body for textual responses. Sub-threshold
/// bodies go through a Pretty/Raw/Tree toggle (the JSON editor or a collapsible
/// tree); bodies over [kLargeResponseViewerChars] fall back to a plain-text
/// viewer (unless the user opts into highlighting). TREE is only offered for
/// JSON object/array bodies under the large threshold.
class _TextualResponseBody extends StatefulWidget {
  const _TextualResponseBody({
    required this.tabId,
    required this.responseController,
  });
  final String tabId;
  final CodeLineEditingController responseController;

  @override
  State<_TextualResponseBody> createState() => _TextualResponseBodyState();
}

class _TextualResponseBodyState extends State<_TextualResponseBody> {
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

  // True while a background (or inline) decode for the tree is in flight.
  bool _treeDecoding = false;

  // Large-mode state: non-null when the current body exceeds the threshold.
  String? _largeBody;
  bool _showFullPreview = false;
  bool _highlightingOptedIn = false;

  // Hoisted out of [_suggestVariableName] so the patterns compile once, not on
  // every "Extract to {{var}}" click.
  static final RegExp _dotTailRe = RegExp(r'\.([A-Za-z_$][\w$]*)$');
  static final RegExp _bracketTailRe = RegExp(r'\[(.+)\]$');
  static final RegExp _quoteStripRe = RegExp('''['"]''');
  static final RegExp _nonIdentRe = RegExp('[^A-Za-z0-9_]');
  static final RegExp _digitsRe = RegExp(r'^[0-9]+$');

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
          !isResponseBodyPlaceholder(rawBody) &&
          canHighlightBody(rawBody.length);
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
    final isPlaceholder = isResponseBodyPlaceholder(rawBody);
    final text = (_mode == _BodyMode.raw || isPlaceholder)
        ? (rawBody ?? '')
        : await JsonUtils.prettify(rawBody);
    // Only apply if no newer sync was started and we're still mounted.
    if (!mounted || syncId != _pendingSyncId) return;
    widget.responseController.text = text;
    // Tree decode is now LAZY (see _decodeForTree): enable TREE optimistically
    // from a cheap shape probe; the real (possibly off-isolate) decode happens
    // only when the user selects TREE. This removes the synchronous jsonDecode
    // that previously ran on every response arrival.
    final treeMaybe = _looksLikeJson(rawBody) && !isPlaceholder;
    setState(() {
      _largeBody = null;
      _showFullPreview = false;
      _highlightingOptedIn = false;
      _decoded = null;
      _treeDecoding = false;
      _treeAvailable = treeMaybe;
      if (_mode == _BodyMode.tree && !treeMaybe) _mode = _BodyMode.pretty;
    });
    // If the user is already viewing TREE and the body changed, re-decode now.
    if (_mode == _BodyMode.tree && treeMaybe) {
      unawaited(_decodeForTree());
    }
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
    final dot = _dotTailRe.firstMatch(jsonPath);
    if (dot != null) {
      raw = dot.group(1)!;
    } else {
      final bracket = _bracketTailRe.firstMatch(jsonPath);
      if (bracket != null) {
        raw = bracket.group(1)!.replaceAll(_quoteStripRe, '');
      }
    }
    final cleaned = raw.replaceAll(_nonIdentRe, '_');
    if (cleaned.isEmpty || _digitsRe.hasMatch(cleaned)) {
      return 'value';
    }
    return cleaned;
  }

  /// Cheap shape probe — a JSON object/array body starts with `{`/`[`. Used to
  /// enable TREE optimistically without paying a full decode on arrival.
  static bool _looksLikeJson(String? body) {
    if (body == null) return false;
    final t = body.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }

  /// Decodes the current body for the tree, lazily and off the UI isolate for
  /// large bodies. On a parse miss (or a JSON scalar), disables TREE and falls
  /// back to PRETTY. Guarded by [_pendingSyncId] so a newer body wins.
  Future<void> _decodeForTree() async {
    final body = context
        .read<TabsBloc>()
        .state
        .tabs
        .byId(widget.tabId)
        ?.response
        ?.body;
    if (body == null || isResponseBodyPlaceholder(body)) {
      setState(() {
        _treeAvailable = false;
        if (_mode == _BodyMode.tree) _mode = _BodyMode.pretty;
      });
      return;
    }
    final syncId = _pendingSyncId;
    setState(() => _treeDecoding = true);
    final decoded = body.length > kTreeInlineDecodeLimit
        ? await compute(JsonPath.tryDecode, body)
        : JsonPath.tryDecode(body);
    if (!mounted || syncId != _pendingSyncId) return;
    final treeOk = decoded is Map || decoded is List;
    setState(() {
      _treeDecoding = false;
      if (treeOk) {
        _decoded = decoded;
      } else {
        _treeAvailable = false;
        if (_mode == _BodyMode.tree) _mode = _BodyMode.pretty;
      }
    });
    if (!treeOk) showAppSnackBar(context, 'Not a JSON object/array');
  }

  /// Resets tree state (large mode has no tree). Call inside a setState.
  void _clearTreeState() {
    _decoded = null;
    _treeAvailable = false;
    _treeDecoding = false;
    if (_mode == _BodyMode.tree) _mode = _BodyMode.pretty;
  }

  void _setMode(_BodyMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    if (mode == _BodyMode.tree) {
      // Lazy: decode only now, and only if not already decoded/in-flight.
      if (_decoded == null && !_treeDecoding) unawaited(_decodeForTree());
    } else {
      // Switching the editor's pretty/raw rendering needs a re-sync.
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
    if (!canHighlightBody(body.length)) {
      showAppSnackBar(
        context,
        'Body too large to highlight (over 3 MB) — showing plain text',
      );
      return;
    }
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
              ? (_decoded != null
                    ? JsonTreeView(
                        data: _decoded,
                        onExtract: _extractToVariable,
                      )
                    : const Center(child: CircularProgressIndicator()))
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
