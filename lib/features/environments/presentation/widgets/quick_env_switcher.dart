import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/theme/responsive.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/environments/domain/entities/environment_entity.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';

/// Cmd/Ctrl+E quick switcher: an arrow-navigable list of `No Environment` plus
/// every saved environment. A smaller sibling of `CommandPalette` scoped to
/// environments only, with no text search. Reads both blocs at open time
/// (passed in by [show]) and dispatches the existing
/// [UpdateActiveEnvironmentId] event — no new bloc.
class QuickEnvSwitcher extends StatefulWidget {
  const QuickEnvSwitcher({
    required this.environments,
    required this.activeId,
    required this.settingsBloc,
    super.key,
  });

  /// Snapshot of the env list read at open time.
  final List<EnvironmentEntity> environments;

  /// Active environment id at open time; null == No Environment.
  final String? activeId;

  /// Held so the widget can dispatch the switch itself, mirroring how
  /// `CommandPalette` holds [SettingsBloc].
  final SettingsBloc settingsBloc;

  static Future<void> show(BuildContext context) {
    final envState = context.read<EnvironmentsBloc>().state;
    final settingsBloc = context.read<SettingsBloc>();
    return showResponsiveDialog<void>(
      context,
      builder: (_) => QuickEnvSwitcher(
        environments: envState.environments,
        activeId: settingsBloc.state.settings.activeEnvironmentId,
        settingsBloc: settingsBloc,
      ),
    );
  }

  @override
  State<QuickEnvSwitcher> createState() => _QuickEnvSwitcherState();
}

class _QuickEnvSwitcherState extends State<QuickEnvSwitcher> {
  late final List<_EnvRow> _rows = _buildRows();
  // Index of the keyboard-highlighted row; opens on the active row so a stray
  // Enter is a harmless re-select.
  late final ValueNotifier<int> _selected = ValueNotifier<int>(
    _rows.indexWhere((r) => r.isActive).clamp(0, _rows.length - 1),
  );

  @override
  void dispose() {
    _selected.dispose();
    super.dispose();
  }

  List<_EnvRow> _buildRows() {
    return [
      _EnvRow(
        label: 'No Environment',
        envId: null,
        isActive: widget.activeId == null,
      ),
      for (final env in widget.environments)
        _EnvRow(
          label: env.name,
          envId: env.id,
          isActive: env.id == widget.activeId,
        ),
    ];
  }

  void _moveSelection(int delta) {
    _selected.value = (_selected.value + delta).clamp(0, _rows.length - 1);
  }

  void _runSelected() => _invoke(_selected.value.clamp(0, _rows.length - 1));

  void _invoke(int index) {
    final row = _rows[index.clamp(0, _rows.length - 1)];
    widget.settingsBloc.add(UpdateActiveEnvironmentId(row.envId));
    unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context) {
    // There is no text field competing for arrow/Enter, so an autofocused
    // Focus wrapper makes the Shortcuts resolve immediately on open.
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
        child: Focus(autofocus: true, child: _buildScaffold(context)),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final layout = context.appLayout;
    return ResponsiveDialogScaffold(
      title: const Text('SWITCH ENVIRONMENT'),
      content: SizedBox(
        width: context.isDialogFullscreen
            ? double.maxFinite
            : layout.dialogWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: layout.quickListMaxHeight),
          child: ValueListenableBuilder<int>(
            valueListenable: _selected,
            builder: (context, selected, _) {
              final highlight = Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.14);
              return ListView.builder(
                shrinkWrap: true,
                itemCount: _rows.length,
                itemBuilder: (context, i) {
                  final row = _rows[i];
                  return ColoredBox(
                    key: ValueKey('quick_env_row_$i'),
                    color: i == selected ? highlight : Colors.transparent,
                    child: ListTile(
                      dense: true,
                      leading: row.isActive
                          ? Icon(
                              Icons.check,
                              size: layout.smallIconSize,
                              color: Theme.of(context).colorScheme.secondary,
                            )
                          : SizedBox(width: layout.smallIconSize),
                      title: Text(
                        row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: context.appTypography.titleWeight,
                        ),
                      ),
                      onTap: () => _invoke(i),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }
}

/// One row in the switcher: the `No Environment` row ([envId] == null) or a
/// saved environment. A small union so selection is a single index with no
/// magic-string sentinels in the keyboard code.
class _EnvRow {
  const _EnvRow({
    required this.label,
    required this.envId,
    required this.isActive,
  });
  final String label;
  final String? envId;
  final bool isActive;
}

class _MoveSelectionIntent extends Intent {
  const _MoveSelectionIntent(this.delta);
  final int delta;
}

class _RunSelectionIntent extends Intent {
  const _RunSelectionIntent();
}
