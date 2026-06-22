import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_state.dart';
import 'package:getman/features/environments/domain/logic/active_environment_helper.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// Builds the layered (environment + collection + dynamic) variable context
/// for [tabId] from live bloc state, rebuilding when the active environment,
/// the environment set, the collection tree, or the tab's linked node change.
/// Shared by params, headers, auth, form-data, and the body editor so every
/// field offers identical suggestions.
class TabVariableContextBuilder extends StatelessWidget {
  const TabVariableContextBuilder({
    required this.tabId,
    required this.builder,
    super.key,
  });

  final String tabId;
  final Widget Function(BuildContext, LayeredVariableContext) builder;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, n) =>
          p.settings.activeEnvironmentId != n.settings.activeEnvironmentId,
      builder: (context, settingsState) {
        return BlocBuilder<EnvironmentsBloc, EnvironmentsState>(
          buildWhen: (p, n) => p.environments != n.environments,
          builder: (context, envState) {
            return BlocBuilder<TabsBloc, TabsState>(
              buildWhen: (p, n) =>
                  p.tabs.byId(tabId)?.collectionNodeId !=
                  n.tabs.byId(tabId)?.collectionNodeId,
              builder: (context, tabsState) {
                return BlocBuilder<CollectionsBloc, CollectionsState>(
                  buildWhen: (p, n) => p.collections != n.collections,
                  builder: (context, collectionsState) {
                    final env = ActiveEnvironmentHelper.activeEnvironment(
                      envState.environments,
                      settingsState.settings.activeEnvironmentId,
                    );
                    final nodeId = tabsState.tabs.byId(tabId)?.collectionNodeId;
                    final collected = nodeId == null
                        ? (
                            variables: const <String, String>{},
                            secretKeys: const <String>{},
                          )
                        : CollectionsTreeHelper.collectVariables(
                            collectionsState.collections,
                            nodeId,
                          );
                    return builder(
                      context,
                      LayeredVariableContext(
                        environmentVariables: env?.variables ?? const {},
                        environmentSecrets: env?.secretKeys ?? const {},
                        collectionVariables: collected.variables,
                        collectionSecrets: collected.secretKeys,
                        environmentName: env?.name,
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
