import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/fuzzy_matcher.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

/// Cmd/Ctrl+K palette: fuzzy-jump to a saved request, switch environment, or
/// change theme. Reads bloc state at open time (passed in by [show]) and
/// dispatches through the same events the rest of the app uses — no new bloc.
class CommandPalette extends StatefulWidget {
  final TabsBloc tabsBloc;
  final CollectionsBloc collectionsBloc;
  final EnvironmentsBloc environmentsBloc;
  final SettingsBloc settingsBloc;

  const CommandPalette({
    super.key,
    required this.tabsBloc,
    required this.collectionsBloc,
    required this.environmentsBloc,
    required this.settingsBloc,
  });

  static Future<void> show(BuildContext context) {
    return showResponsiveDialog(
      context,
      builder: (_) => CommandPalette(
        tabsBloc: context.read<TabsBloc>(),
        collectionsBloc: context.read<CollectionsBloc>(),
        environmentsBloc: context.read<EnvironmentsBloc>(),
        settingsBloc: context.read<SettingsBloc>(),
      ),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final TextEditingController _query = TextEditingController();
  late final List<_Command> _all = _buildCommands();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<_Command> _buildCommands() {
    final cmds = <_Command>[];
    _collectRequests(widget.collectionsBloc.state.collections, '', cmds);

    cmds.add(_Command(
      label: 'No Environment',
      subtitle: 'Environment',
      icon: Icons.layers_clear_outlined,
      run: () => widget.settingsBloc.add(const UpdateActiveEnvironmentId(null)),
    ));
    for (final env in widget.environmentsBloc.state.environments) {
      cmds.add(_Command(
        label: env.name,
        subtitle: 'Environment',
        icon: Icons.layers_outlined,
        run: () => widget.settingsBloc.add(UpdateActiveEnvironmentId(env.id)),
      ));
    }

    for (final t in appThemes.values) {
      cmds.add(_Command(
        label: t.displayName,
        subtitle: 'Theme',
        icon: Icons.palette_outlined,
        run: () => widget.settingsBloc.add(UpdateThemeId(t.id)),
      ));
    }
    return cmds;
  }

  void _collectRequests(List<CollectionNodeEntity> nodes, String path, List<_Command> out) {
    for (final node in nodes) {
      if (node.isFolder) {
        _collectRequests(node.children, path.isEmpty ? node.name : '$path / ${node.name}', out);
      } else {
        final config = node.config;
        out.add(_Command(
          label: node.name,
          subtitle: path.isEmpty ? 'Request' : path,
          icon: Icons.http,
          run: () => widget.tabsBloc.add(
            AddTab(config: config, collectionNodeId: node.id, collectionName: node.name),
          ),
        ));
      }
    }
  }

  void _invoke(_Command command) {
    command.run();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final results = FuzzyMatcher.filter(_query.text, _all, (c) => '${c.label} ${c.subtitle}');

    return ResponsiveDialogScaffold(
      title: const Text('COMMAND PALETTE'),
      content: SizedBox(
        width: context.isDialogFullscreen ? double.maxFinite : 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                hintText: 'Jump to a request, environment, or theme…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (results.isNotEmpty) _invoke(results.first);
              },
            ),
            SizedBox(height: layout.sectionSpacing),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: results.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(layout.pagePadding),
                      child: Text(
                        'NO MATCHES',
                        style: TextStyle(
                          fontWeight: context.appTypography.titleWeight,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final c = results[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(c.icon, size: layout.iconSize),
                          title: Text(c.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: context.appTypography.titleWeight)),
                          subtitle: Text(c.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _invoke(c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Command {
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback run;
  const _Command({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.run,
  });
}
