import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// Writes values captured by extraction rules into the active environment.
///
/// Coordinates at the widget layer (it holds Tabs/Environments/Settings blocs)
/// so TabsBloc never writes to EnvironmentsBloc directly — the same rule the
/// rest of the app follows. Fires when the active tab gains new extraction
/// results after a send.
class ChainingWriteBackListener extends StatelessWidget {
  final Widget child;
  const ChainingWriteBackListener({super.key, required this.child});

  HttpRequestTabEntity? _activeTab(TabsState s) {
    if (s.activeIndex < 0 || s.activeIndex >= s.tabs.length) return null;
    return s.tabs[s.activeIndex];
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) {
        final n = _activeTab(next);
        if (n == null || n.extractionResults.isEmpty) return false;
        return _activeTab(prev)?.extractionResults != n.extractionResults;
      },
      listener: (context, state) {
        final tab = _activeTab(state);
        if (tab == null) return;
        final matched =
            tab.extractionResults.where((e) => e.matched && e.value != null).toList();
        if (matched.isEmpty) return;

        final activeId = context.read<SettingsBloc>().state.settings.activeEnvironmentId;
        final envs = context.read<EnvironmentsBloc>().state.environments;
        final active = activeId == null ? null : envs.firstWhereOrNull((e) => e.id == activeId);

        if (active == null) {
          showAppSnackBar(
            context,
            'Captured ${matched.length} value(s) — select an active environment to save them.',
          );
          return;
        }

        final merged = Map<String, String>.of(active.variables);
        for (final e in matched) {
          merged[e.variable] = e.value!;
        }
        context.read<EnvironmentsBloc>().add(UpdateEnvironment(active.copyWith(variables: merged)));
        showAppSnackBar(
          context,
          'Captured → ${matched.map((e) => '{{${e.variable}}}').join(', ')}',
        );
      },
      child: child,
    );
  }
}
