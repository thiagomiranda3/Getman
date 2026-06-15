import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/extraction_result.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

const _resultsEquality = ListEquality<ExtractionResult>();

/// Writes values captured by extraction rules into the active environment.
///
/// Coordinates at the widget layer (it holds Tabs/Environments/Settings blocs)
/// so TabsBloc never writes to EnvironmentsBloc directly — the same rule the
/// rest of the app follows.
///
/// Tracks captures across **every** tab, not just the active one (a request can
/// finish while the user is on a different tab). A per-tabId snapshot of
/// already-written results guarantees each capture is written exactly once.
/// Crucially, results are marked written **only after** they are persisted — a
/// capture made while no environment is active stays pending and is flushed the
/// moment an environment is selected (which emits on SettingsBloc, not
/// TabsBloc, so it is listened for separately).
class ChainingWriteBackListener extends StatefulWidget {
  const ChainingWriteBackListener({required this.child, super.key});
  final Widget child;

  @override
  State<ChainingWriteBackListener> createState() =>
      _ChainingWriteBackListenerState();
}

class _ChainingWriteBackListenerState extends State<ChainingWriteBackListener> {
  final Map<String, List<ExtractionResult>> _written = {};
  // Dedupes the "select an environment" notice so unrelated TabsState emissions
  // (e.g. typing in another tab) don't re-spam it while a capture is pending.
  String? _lastNoEnvNotice;

  @override
  Widget build(BuildContext context) {
    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) => _hasPending(next),
      listener: _flush,
      child: BlocListener<SettingsBloc, SettingsState>(
        // A newly-selected environment emits no TabsState, so flush pending
        // captures here too.
        listenWhen: (prev, next) =>
            prev.settings.activeEnvironmentId !=
                next.settings.activeEnvironmentId &&
            next.settings.activeEnvironmentId != null,
        listener: (context, _) =>
            _flush(context, context.read<TabsBloc>().state),
        child: widget.child,
      ),
    );
  }

  bool _hasPending(TabsState next) {
    for (final tab in next.tabs) {
      if (tab.extractionResults.isEmpty) continue;
      if (!_resultsEquality.equals(
        _written[tab.tabId],
        tab.extractionResults,
      )) {
        return true;
      }
    }
    return false;
  }

  void _flush(BuildContext context, TabsState state) {
    final pending = <String, List<ExtractionResult>>{};
    final captured = <ExtractionResult>[];
    for (final tab in state.tabs) {
      if (_resultsEquality.equals(_written[tab.tabId], tab.extractionResults)) {
        continue;
      }
      final matched = tab.extractionResults
          .where((e) => e.matched && e.value != null)
          .toList();
      if (matched.isEmpty) {
        // Nothing to persist for this tab — mark seen so it isn't reconsidered.
        _written[tab.tabId] = tab.extractionResults;
        continue;
      }
      pending[tab.tabId] = tab.extractionResults;
      captured.addAll(matched);
    }
    // Don't let the bookkeeping grow unbounded as tabs come and go.
    final live = state.tabs.map((t) => t.tabId).toSet();
    _written.removeWhere((id, _) => !live.contains(id));

    if (captured.isEmpty) return;

    final activeId = context
        .read<SettingsBloc>()
        .state
        .settings
        .activeEnvironmentId;
    final envs = context.read<EnvironmentsBloc>().state.environments;
    final active = activeId == null
        ? null
        : envs.firstWhereOrNull((e) => e.id == activeId);

    if (active == null) {
      // Do NOT mark pending as written — keep it for when an environment is
      // selected. Notify once per distinct pending set.
      final noticeKey = captured
          .map((e) => '${e.variable}=${e.value}')
          .join('|');
      if (_lastNoEnvNotice != noticeKey) {
        _lastNoEnvNotice = noticeKey;
        showAppSnackBar(
          context,
          'Captured ${captured.length} value(s) — select an active '
          'environment to save them.',
        );
      }
      return;
    }

    final merged = Map<String, String>.of(active.variables);
    for (final e in captured) {
      merged[e.variable] = e.value!;
    }
    context.read<EnvironmentsBloc>().add(
      UpdateEnvironment(active.copyWith(variables: merged)),
    );
    pending.forEach(
      (id, results) => _written[id] = results,
    ); // mark only after persist
    _lastNoEnvNotice = null;
    showAppSnackBar(
      context,
      'Captured → ${captured.map((e) => '{{${e.variable}}}').join(', ')}',
    );
  }
}
