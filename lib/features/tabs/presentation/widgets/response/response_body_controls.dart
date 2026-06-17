import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/compare_target_picker.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/ui/widgets/response_diff_view.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/core/utils/response_diff_builder.dart';
import 'package:getman/features/collections/domain/entities/saved_example_entity.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:uuid/uuid.dart';

/// The action-button cluster shown in both the small and large response-body
/// views: copy, save-to-file, compare, and save-as-example.
///
/// Each conditional button keeps its existing `BlocBuilder` + `buildWhen` gate
/// — these gates are load-bearing for performance and must not be widened or
/// removed.
///
/// [getCopyableText] is a callback into the parent state that returns the
/// verbatim body text (the large-body cache when in plain-text mode, otherwise
/// the editor text).
class ResponseBodyControls extends StatelessWidget {
  const ResponseBodyControls({
    required this.tabId,
    required this.getCopyableText,
    super.key,
  });

  final String tabId;

  /// Returns the text that Copy and Save-to-file should use.
  final String Function() getCopyableText;

  // ---------------------------------------------------------------------------
  // Copy
  // ---------------------------------------------------------------------------

  Future<void> _copyBody(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = getCopyableText();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    showAppSnackBarVia(messenger, 'Response copied');
  }

  Widget _copyButton(BuildContext context) {
    return IconButton(
      tooltip: 'Copy response',
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.copy_all_outlined, size: context.appLayout.iconSize),
      onPressed: () => _copyBody(context),
    );
  }

  // ---------------------------------------------------------------------------
  // Save to file
  // ---------------------------------------------------------------------------

  /// Writes the verbatim response body (the same text Copy uses, incl. the
  /// large-body cache) to a user-chosen file. JSON default, txt allowed.
  Future<void> _saveBody(BuildContext context) async {
    final text = getCopyableText();
    if (text.isEmpty) return;
    await saveJsonFileWithFeedback(
      context,
      jsonString: text,
      fileName: 'response.json',
      dialogTitle: 'SAVE RESPONSE',
      allowedExtensions: const ['json', 'txt'],
    );
  }

  Widget _saveButton(BuildContext context) {
    return IconButton(
      tooltip: 'Save response to file',
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.save_outlined, size: context.appLayout.iconSize),
      onPressed: () => _saveBody(context),
    );
  }

  // ---------------------------------------------------------------------------
  // Save as example
  // ---------------------------------------------------------------------------

  /// "Save as example" — captures the live request+response as a named snapshot
  /// under the linked collection node. Only shown when the tab is linked to a
  /// saved request (collectionNodeId) and a response exists to capture.
  Widget _saveAsExampleButton(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        return p?.collectionNodeId != n?.collectionNodeId ||
            (p?.response == null) != (n?.response == null);
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null ||
            tab.collectionNodeId == null ||
            tab.response == null) {
          return const SizedBox.shrink();
        }
        return IconButton(
          key: const ValueKey('save_as_example_button'),
          tooltip: 'Save as example',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.bookmark_add_outlined,
            size: context.appLayout.iconSize,
          ),
          onPressed: () => _saveAsExample(context),
        );
      },
    );
  }

  Future<void> _saveAsExample(BuildContext context) async {
    // Re-read at press time so we capture the response currently on screen.
    final tab = context.read<TabsBloc>().state.tabs.byId(tabId);
    final response = tab?.response;
    final nodeId = tab?.collectionNodeId;
    if (tab == null || response == null || nodeId == null) return;

    final collectionsBloc = context.read<CollectionsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final defaultName = '${response.statusCode} · ${_hhmm(now)}';

    await NamePromptDialog.show(
      context,
      title: 'SAVE AS EXAMPLE',
      initialText: defaultName,
      onConfirm: (name) {
        final trimmed = name.trim().isEmpty ? defaultName : name.trim();
        final example = SavedExampleEntity(
          id: const Uuid().v4(),
          name: trimmed,
          capturedAt: now,
          config: tab.config.copyWith(
            statusCode: response.statusCode,
            responseBody: response.body,
            responseHeaders: response.headers,
            durationMs: response.durationMs,
          ),
        );
        collectionsBloc.add(SaveExampleToNode(nodeId, example));
        showAppSnackBarVia(messenger, 'Saved example "$trimmed"');
      },
    );
  }

  static String _hhmm(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  // ---------------------------------------------------------------------------
  // Compare
  // ---------------------------------------------------------------------------

  /// Saved-example targets for the tab's linked node (response captured only).
  List<CompareTarget> _exampleTargets(BuildContext context, String? nodeId) {
    if (nodeId == null) return const [];
    final collections = context.read<CollectionsBloc>().state.collections;
    final node = CollectionsTreeHelper.findNode(collections, nodeId);
    if (node == null) return const [];
    final out = <CompareTarget>[];
    for (final ex in node.examples) {
      final response = responseFromConfig(ex.config);
      if (response == null) continue;
      out.add(
        CompareTarget(
          id: ex.id,
          source: CompareTargetSource.example,
          label: ex.name,
          subtitle: 'captured ${_hhmm(ex.capturedAt)}',
          response: response,
        ),
      );
    }
    return out;
  }

  /// History targets matching the tab's method + url (newest first, capped).
  List<CompareTarget> _historyTargets(
    BuildContext context,
    HttpRequestConfigEntity config,
  ) {
    final history = context.read<HistoryBloc>().state.history;
    final out = <CompareTarget>[];
    for (final entry in history) {
      if (entry.method != config.method || entry.url != config.url) continue;
      final response = responseFromConfig(entry);
      if (response == null) continue;
      out.add(
        CompareTarget(
          id: entry.id,
          source: CompareTargetSource.history,
          label: '${entry.method} ${entry.url} · ${entry.statusCode}',
          subtitle: '${entry.durationMs ?? 0} ms',
          response: response,
        ),
      );
      if (out.length >= 20) break; // cap
    }
    return out;
  }

  /// Earlier responses from this tab's time-travel history (newest-first),
  /// excluding the currently-displayed one and metadata-only placeholders.
  List<CompareTarget> _timelineTargets(
    BuildContext context,
    HttpRequestTabEntity tab,
  ) {
    final current = tab.response;
    final out = <CompareTarget>[];
    for (final entry in tab.responseHistory) {
      final r = entry.response;
      if (r == current) continue;
      if (r.body == kResponseBodyTooLargePlaceholder) continue;
      out.add(
        CompareTarget(
          id: entry.id,
          source: CompareTargetSource.timeline,
          label: 'Response ${r.statusCode}',
          subtitle:
              '${r.durationMs} ms · '
              '${_hhmm(DateTime.fromMillisecondsSinceEpoch(entry.capturedAt))}',
          response: r,
        ),
      );
    }
    return out;
  }

  Widget _compareButton(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        return (p?.response == null) != (n?.response == null) ||
            p?.collectionNodeId != n?.collectionNodeId ||
            p?.config.method != n?.config.method ||
            p?.config.url != n?.config.url ||
            p?.responseHistory.length != n?.responseHistory.length;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null || tab.response == null) {
          return const SizedBox.shrink();
        }
        final hasTargets =
            _exampleTargets(context, tab.collectionNodeId).isNotEmpty ||
            _historyTargets(context, tab.config).isNotEmpty ||
            _timelineTargets(context, tab).isNotEmpty;
        return IconButton(
          key: const ValueKey('compare_response_button'),
          tooltip: hasTargets
              ? 'Compare response'
              : 'No saved examples or matching history to compare',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.difference_outlined,
            size: context.appLayout.iconSize,
          ),
          onPressed: hasTargets ? () => _compareResponse(context) : null,
        );
      },
    );
  }

  Future<void> _compareResponse(BuildContext context) async {
    final tab = context.read<TabsBloc>().state.tabs.byId(tabId);
    final current = tab?.response;
    if (tab == null || current == null) return;

    final examples = _exampleTargets(context, tab.collectionNodeId);
    final history = _historyTargets(context, tab.config);
    final timeline = _timelineTargets(context, tab);
    if (examples.isEmpty && history.isEmpty && timeline.isEmpty) return;

    final target = await showDialog<CompareTarget>(
      context: context,
      builder: (_) => CompareTargetPicker(
        examples: examples,
        history: history,
        timeline: timeline,
      ),
    );
    if (target == null) return;
    if (!context.mounted) return;

    final model = await ResponseDiffBuilder.build(current, target.response);
    if (!context.mounted) return;

    await showResponsiveDialog<void>(
      context,
      builder: (_) => ResponseDiffView(
        model: model,
        leftLabel: 'This response',
        rightLabel: target.label,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Wrap (not Row) so the icons reflow onto a second line rather than
    // overflowing when the response pane is dragged very narrow.
    return Wrap(
      children: [
        _copyButton(context),
        _saveButton(context),
        _compareButton(context),
        _saveAsExampleButton(context),
      ],
    );
  }
}
