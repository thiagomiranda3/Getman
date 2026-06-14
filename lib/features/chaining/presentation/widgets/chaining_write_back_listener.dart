import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/extraction_result.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

const _resultsEquality = ListEquality<ExtractionResult>();

/// Writes values captured by extraction rules into the active environment.
///
/// Coordinates at the widget layer (it holds Tabs/Environments/Settings blocs)
/// so TabsBloc never writes to EnvironmentsBloc directly — the same rule the
/// rest of the app follows.
///
/// Tracks captures across **every** tab, not just the active one: a request can
/// finish and emit its extraction results while the user has switched to a
/// different tab, and those values must still reach the environment. A
/// per-tabId snapshot of already-written results guarantees each capture is
/// written exactly once (and never re-written on an unrelated re-emission).
class ChainingWriteBackListener extends StatefulWidget {
  final Widget child;
  const ChainingWriteBackListener({super.key, required this.child});

  @override
  State<ChainingWriteBackListener> createState() => _ChainingWriteBackListenerState();
}

class _ChainingWriteBackListenerState extends State<ChainingWriteBackListener> {
  final Map<String, List<ExtractionResult>> _written = {};

  @override
  Widget build(BuildContext context) {
    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) => _hasUnwritten(next),
      listener: _writeBack,
      child: widget.child,
    );
  }

  bool _hasUnwritten(TabsState next) {
    for (final tab in next.tabs) {
      if (tab.extractionResults.isEmpty) continue;
      if (!_resultsEquality.equals(_written[tab.tabId], tab.extractionResults)) {
        return true;
      }
    }
    return false;
  }

  void _writeBack(BuildContext context, TabsState state) {
    final captured = <ExtractionResult>[];
    for (final tab in state.tabs) {
      if (_resultsEquality.equals(_written[tab.tabId], tab.extractionResults)) continue;
      _written[tab.tabId] = tab.extractionResults;
      captured.addAll(tab.extractionResults.where((e) => e.matched && e.value != null));
    }
    // Don't let the snapshot grow unbounded as tabs come and go.
    final live = state.tabs.map((t) => t.tabId).toSet();
    _written.removeWhere((id, _) => !live.contains(id));

    if (captured.isEmpty) return;

    final activeId = context.read<SettingsBloc>().state.settings.activeEnvironmentId;
    final envs = context.read<EnvironmentsBloc>().state.environments;
    final active = activeId == null ? null : envs.firstWhereOrNull((e) => e.id == activeId);

    if (active == null) {
      showAppSnackBar(
        context,
        'Captured ${captured.length} value(s) — select an active environment to save them.',
      );
      return;
    }

    final merged = Map<String, String>.of(active.variables);
    for (final e in captured) {
      merged[e.variable] = e.value!;
    }
    context.read<EnvironmentsBloc>().add(UpdateEnvironment(active.copyWith(variables: merged)));
    showAppSnackBar(
      context,
      'Captured → ${captured.map((e) => '{{${e.variable}}}').join(', ')}',
    );
  }
}
