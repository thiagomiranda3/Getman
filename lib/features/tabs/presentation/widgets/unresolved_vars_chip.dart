// Pre-send unresolved-{{var}} warning chip (left of SEND in UrlBar): counts
// the variables the request references that resolve to NOTHING in the
// active env+collection chain (UnresolvedVariableCollector over
// TabVariableContextBuilder's LayeredVariableContext). Click opens a popup
// listing up to 10 names + "Open environment editor…". Purely advisory —
// it never blocks SEND. Hidden when the count is zero.
//
// Gotchas: this chip rebuilds per config keystroke (unlike UrlBar's outer
// builder, whose buildWhen deliberately excludes url/body edits), so the
// collect() scan is memoized on the (config, LayeredVariableContext) pair —
// unchanged inputs return the cached list without re-running the regex over
// a potentially large body.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/tab_variable_context_builder.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/core/utils/unresolved_variable_collector.dart';
import 'package:getman/features/environments/presentation/widgets/environments_dialog.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

const String _openEnvEditorValue = '__open_env_editor__';

/// Warning chip + popover for `{{vars}}` that resolve to nothing. Renders
/// nothing when every referenced variable resolves in the active chain.
class UnresolvedVarsChip extends StatefulWidget {
  const UnresolvedVarsChip({required this.tabId, super.key});

  final String tabId;

  /// Max names listed in the popover; the rest collapse into "+N more".
  static const int maxListedNames = 10;

  @override
  State<UnresolvedVarsChip> createState() => _UnresolvedVarsChipState();
}

class _UnresolvedVarsChipState extends State<UnresolvedVarsChip> {
  // Memo over the two inputs (both Equatable). Recomputing only on a real
  // change keeps the regex scan off the per-emission hot path.
  HttpRequestConfigEntity? _memoConfig;
  LayeredVariableContext? _memoContext;
  List<String> _memoResult = const [];

  List<String> _unresolvedFor(
    HttpRequestConfigEntity config,
    LayeredVariableContext varsContext,
  ) {
    if (config == _memoConfig && varsContext == _memoContext) {
      return _memoResult;
    }
    _memoConfig = config;
    _memoContext = varsContext;
    return _memoResult = UnresolvedVariableCollector.collect(
      config: config,
      variables: varsContext.allVariables,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TabVariableContextBuilder(
      tabId: widget.tabId,
      builder: (context, varsContext) {
        return BlocBuilder<TabsBloc, TabsState>(
          buildWhen: (p, n) =>
              p.tabs.byId(widget.tabId)?.config !=
              n.tabs.byId(widget.tabId)?.config,
          builder: (context, state) {
            final config = state.tabs.byId(widget.tabId)?.config;
            if (config == null) return const SizedBox.shrink();
            final unresolved = _unresolvedFor(config, varsContext);
            if (unresolved.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.only(right: context.appLayout.tabSpacing),
              child: _chip(context, unresolved),
            );
          },
        );
      },
    );
  }

  Widget _chip(BuildContext context, List<String> unresolved) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final warnColor = context.appPalette.variableUnresolved;
    return PopupMenuButton<String>(
      key: const ValueKey('unresolved_vars_chip'),
      tooltip: 'Unresolved variables',
      position: PopupMenuPosition.under,
      color: theme.colorScheme.surface,
      onSelected: (value) {
        if (value == _openEnvEditorValue) {
          unawaited(EnvironmentsDialog.show(context));
        }
      },
      itemBuilder: (context) => _menuItems(context, unresolved),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: layout.badgePaddingHorizontal,
          vertical: layout.badgePaddingVertical,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: warnColor, width: layout.borderThin),
          borderRadius: BorderRadius.circular(context.appShape.buttonRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: layout.smallIconSize,
              color: warnColor,
            ),
            SizedBox(width: layout.tabSpacing),
            Text(
              '${unresolved.length}',
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.titleWeight,
                color: warnColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _menuItems(
    BuildContext context,
    List<String> unresolved,
  ) {
    final layout = context.appLayout;
    final listed = unresolved.take(UnresolvedVarsChip.maxListedNames).toList();
    final overflow = unresolved.length - listed.length;
    return [
      for (final name in listed)
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            '{{$name}}',
            style: TextStyle(
              fontFamily: context.appTypography.codeFontFamily,
              fontSize: layout.fontSizeNormal,
              color: context.appPalette.variableUnresolved,
            ),
          ),
        ),
      if (overflow > 0)
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            '+$overflow more',
            style: TextStyle(fontSize: layout.fontSizeSmall),
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: _openEnvEditorValue,
        child: Row(
          children: [
            Icon(Icons.tune, size: layout.smallIconSize),
            const SizedBox(width: 6),
            const Text('Open environment editor…'),
          ],
        ),
      ),
    ];
  }
}
