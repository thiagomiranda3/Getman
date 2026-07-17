import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/core/utils/debouncer.dart';
import 'package:getman/core/utils/fuzzy_matcher.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

/// Cmd/Ctrl+K palette: fuzzy-jump to a saved request, switch environment, or
/// change theme. Reads bloc state at open time (passed in by [show]) and
/// dispatches through the same events the rest of the app uses — no new bloc.
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    required this.tabsBloc,
    required this.collectionsBloc,
    required this.environmentsBloc,
    required this.settingsBloc,
    required this.historyBloc,
    super.key,
  });
  final TabsBloc tabsBloc;
  final CollectionsBloc collectionsBloc;
  final EnvironmentsBloc environmentsBloc;
  final SettingsBloc settingsBloc;
  final HistoryBloc historyBloc;

  static Future<void> show(BuildContext context) {
    return showResponsiveDialog(
      context,
      builder: (_) => CommandPalette(
        tabsBloc: context.read<TabsBloc>(),
        collectionsBloc: context.read<CollectionsBloc>(),
        environmentsBloc: context.read<EnvironmentsBloc>(),
        settingsBloc: context.read<SettingsBloc>(),
        historyBloc: context.read<HistoryBloc>(),
      ),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final TextEditingController _query = TextEditingController();
  // Debounced query drives only the results list, so typing doesn't rebuild the
  // whole dialog or re-run FuzzyMatcher over every command on each keystroke.
  final ValueNotifier<String> _queryText = ValueNotifier<String>('');
  // Index of the keyboard-highlighted row; reset to 0 whenever the query
  // changes (results reorder).
  final ValueNotifier<int> _selected = ValueNotifier<int>(0);
  final Debouncer _debouncer = Debouncer();
  late final List<_Command> _all = _buildCommands();
  // Latest results, cached from the list builder so the key handlers can move
  // the selection / run a row without recomputing on every event.
  List<_Command> _currentResults = const [];

  // Keeps the keyboard-highlighted row scrolled into view. Rows may be
  // scrolled out of the ListView's lazy build range (not just clipped), so a
  // GlobalKey/Scrollable.ensureVisible approach can't reach them — an
  // explicit ScrollController offset can. `_rowExtent` is measured off the
  // first rendered row (every row shares the same dense two-line-tile shape)
  // rather than a hardcoded pixel literal; once known it's also fed back into
  // the ListView as a fixed `itemExtent` so `index * _rowExtent` stays exact.
  final ScrollController _resultsScrollController = ScrollController();
  final GlobalKey _measuredRowKey = GlobalKey();
  double? _rowExtent;

  @override
  void initState() {
    super.initState();
    _selected.addListener(_scrollSelectedIntoView);
  }

  @override
  void dispose() {
    _selected.removeListener(_scrollSelectedIntoView);
    _debouncer.dispose();
    _queryText.dispose();
    _selected.dispose();
    _query.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  static String _matchString(_Command c) => c.matchExtra.isEmpty
      ? '${c.label} ${c.subtitle}'
      : '${c.label} ${c.subtitle} ${c.matchExtra}';

  List<_Command> _resultsFor(String query) =>
      FuzzyMatcher.filter(query, _all, _matchString);

  void _onQueryChanged(String v) {
    _debouncer.run(() {
      _queryText.value = v;
      _selected.value = 0;
    });
  }

  void _moveSelection(int delta) {
    if (_currentResults.isEmpty) return;
    _selected.value = (_selected.value + delta).clamp(
      0,
      _currentResults.length - 1,
    );
  }

  /// Reads the first row's laid-out height once, so scroll math has a real
  /// row extent instead of a guessed literal. A no-op once `_rowExtent` is
  /// set (rows are uniform, so one measurement is enough for the session).
  void _measureRowExtentIfNeeded() {
    if (_rowExtent != null) return;
    final renderObject = _measuredRowKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;
    if (!renderObject.hasSize) return;
    setState(() => _rowExtent = renderObject.size.height);
  }

  /// Scrolls the results list just far enough that the highlighted row is
  /// fully within the viewport, in either direction. A no-op until the row
  /// extent is known or before the list has laid out.
  void _scrollSelectedIntoView() {
    final extent = _rowExtent;
    if (extent == null || !_resultsScrollController.hasClients) return;
    final position = _resultsScrollController.position;
    final top = _selected.value * extent;
    final bottom = top + extent;
    double? target;
    if (top < position.pixels) {
      target = top;
    } else if (bottom > position.pixels + position.viewportDimension) {
      target = bottom - position.viewportDimension;
    }
    if (target == null) return;
    unawaited(
      _resultsScrollController.animateTo(
        target.clamp(0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      ),
    );
  }

  void _runSelected() {
    // Recompute against the live text so Enter works before the debounce fires.
    final results = _resultsFor(_query.text);
    if (results.isEmpty) return;
    // The arrow-key index belongs to the DEBOUNCED result list; against a
    // fresh query it can point at a different row than the visible highlight
    // (the debounce handler resets it to 0 — mirror that here).
    final index = _query.text == _queryText.value ? _selected.value : 0;
    _invoke(results[index.clamp(0, results.length - 1)]);
  }

  List<_Command> _buildCommands() {
    final cmds = <_Command>[];
    _collectRequests(widget.collectionsBloc.state.collections, '', cmds);

    cmds.add(
      _Command(
        label: 'No Environment',
        subtitle: 'Environment',
        icon: Icons.layers_clear_outlined,
        run: () =>
            widget.settingsBloc.add(const UpdateActiveEnvironmentId(null)),
      ),
    );
    for (final env in widget.environmentsBloc.state.environments) {
      cmds.add(
        _Command(
          label: env.name,
          subtitle: 'Environment',
          icon: Icons.layers_outlined,
          run: () => widget.settingsBloc.add(UpdateActiveEnvironmentId(env.id)),
        ),
      );
    }

    for (final t in appThemes.values) {
      cmds.add(
        _Command(
          label: t.displayName,
          subtitle: 'Theme',
          icon: Icons.palette_outlined,
          run: () => widget.settingsBloc.add(UpdateThemeId(t.id)),
        ),
      );
    }

    // History source: newest-first (the repository already reverses insertion
    // order). Opens an UNLINKED tab from the stored, templated config —
    // matching history_list.dart verbatim (no collectionNodeId/Name) so a
    // re-send never compares against / overwrites a collection node, and the
    // {{var}} placeholders stay unresolved for re-sending under another env.
    for (final config in widget.historyBloc.state.history) {
      cmds.add(
        _Command(
          label: config.url.isEmpty ? '(NO URL)' : config.url,
          subtitle: 'History',
          icon: Icons.history,
          matchExtra: config.method,
          run: () => widget.tabsBloc.add(AddTab(config: config.copyWith())),
        ),
      );
    }
    return cmds;
  }

  void _collectRequests(
    List<CollectionNodeEntity> nodes,
    String path,
    List<_Command> out,
  ) {
    for (final node in nodes) {
      if (node.isFolder) {
        _collectRequests(
          node.children,
          path.isEmpty ? node.name : '$path / ${node.name}',
          out,
        );
      } else {
        final config = node.config;
        out.add(
          _Command(
            label: node.name,
            subtitle: path.isEmpty ? 'Request' : path,
            icon: Icons.http,
            matchExtra: config == null ? '' : '${config.method} ${config.url}',
            run: () => widget.tabsBloc.add(
              AddTab(
                config: config,
                collectionNodeId: node.id,
                collectionName: node.name,
              ),
            ),
          ),
        );
      }
    }
  }

  void _invoke(_Command command) {
    command.run();
    unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context) {
    // Measured once the first row has actually laid out; a no-op on every
    // subsequent frame once `_rowExtent` is set.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureRowExtentIfNeeded();
    });
    // These Shortcuts sit between the focused search field and the root
    // DefaultTextEditingShortcuts, so they win the arrow/Enter keys (nearest
    // Shortcuts to the focus is resolved first) — arrow keys move the
    // highlight instead of the text caret.
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveSelectionIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveSelectionIntent(-1),
        SingleActivator(LogicalKeyboardKey.enter): _RunSelectionIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _RunSelectionIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MoveSelectionIntent: CallbackAction<_MoveSelectionIntent>(
            onInvoke: (i) {
              _moveSelection(i.delta);
              return null;
            },
          ),
          _RunSelectionIntent: CallbackAction<_RunSelectionIntent>(
            onInvoke: (_) {
              _runSelected();
              return null;
            },
          ),
        },
        child: _buildScaffold(context),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final layout = context.appLayout;
    return ResponsiveDialogScaffold(
      title: const Text('COMMAND PALETTE'),
      content: SizedBox(
        width: context.isDialogFullscreen ? double.maxFinite : 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('palette_search_field'),
              controller: _query,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                hintText:
                    'Jump to a request, history entry, environment, '
                    'or theme…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: _onQueryChanged,
              // Enter via the soft keyboard action; physical Enter is handled
              // by the Shortcuts above. Both run the highlighted row.
              onSubmitted: (_) => _runSelected(),
            ),
            SizedBox(height: layout.sectionSpacing),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ValueListenableBuilder<String>(
                valueListenable: _queryText,
                builder: (context, query, _) {
                  final results = _resultsFor(query);
                  _currentResults = results;
                  if (results.isEmpty) {
                    return Padding(
                      padding: EdgeInsets.all(layout.pagePadding),
                      child: Text(
                        'NO MATCHES',
                        style: TextStyle(
                          fontWeight: context.appTypography.titleWeight,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    );
                  }
                  return ValueListenableBuilder<int>(
                    valueListenable: _selected,
                    builder: (context, selected, _) {
                      final highlight = Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.14);
                      return ListView.builder(
                        controller: _resultsScrollController,
                        shrinkWrap: true,
                        itemExtent: _rowExtent,
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final c = results[i];
                          // Material (not ColoredBox) is the ListTile's
                          // nearest background/ink ancestor — Flutter 3.44
                          // asserts against a colored ColoredBox between a
                          // ListTile and its Material, which would hide the
                          // row background/splash.
                          return Material(
                            key: ValueKey('palette_result_$i'),
                            color: i == selected
                                ? highlight
                                : Colors.transparent,
                            child: ListTile(
                              // Only row 0 carries the measuring key — used
                              // once to read the real rendered row height
                              // (see `_measureRowExtentIfNeeded`) so arrow-key
                              // scrolling has an accurate extent without a
                              // hardcoded pixel literal.
                              key: i == 0 ? _measuredRowKey : null,
                              dense: true,
                              leading: Icon(c.icon, size: layout.iconSize),
                              title: Text(
                                c.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: context.appTypography.titleWeight,
                                ),
                              ),
                              subtitle: Text(
                                c.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _invoke(c),
                            ),
                          );
                        },
                      );
                    },
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
  const _Command({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.run,
    this.matchExtra = '',
  });
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback run;

  /// Extra text folded into the fuzzy-match string but NOT displayed — lets a
  /// saved request match by method + URL (and a history entry by method)
  /// without changing the visible label/subtitle. Default `''` keeps
  /// environment/theme commands matching on label + subtitle only.
  final String matchExtra;
}

class _MoveSelectionIntent extends Intent {
  const _MoveSelectionIntent(this.delta);
  final int delta;
}

class _RunSelectionIntent extends Intent {
  const _RunSelectionIntent();
}
