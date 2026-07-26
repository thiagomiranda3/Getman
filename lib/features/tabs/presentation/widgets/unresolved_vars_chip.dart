// Pre-send unresolved-{{var}} warning chip (left of SEND in UrlBar): counts
// the variables the request references that resolve to NOTHING in the
// active env+collection chain (UnresolvedVariableCollector over
// TabVariableContextBuilder's LayeredVariableContext). Click opens a popup
// listing up to 10 names + "Open environment editor…". Purely advisory —
// it never blocks SEND. Hidden when the count is zero.
//
// Gotchas: this chip rebuilds per config keystroke (unlike UrlBar's outer
// builder, whose buildWhen deliberately excludes url/body edits). FIX I3:
// the collect() scan is now debounced (Debouncer, debounceDuration) rather
// than run synchronously in build — a keystroke burst only re-runs the
// regex scan over the (possibly large) body/headers/params/auth once typing
// quiets down, so the chip may lag briefly but never blocks the typing hot
// path. The FIRST schedule after a mount (fresh tab / LRU re-creation, see
// tab_content_stack.dart) computes immediately so an already-unresolved tab
// doesn't show a blank chip for the debounce window.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/tab_variable_context_builder.dart';
import 'package:getman/core/utils/debouncer.dart';
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

  /// FIX I3: how long a keystroke burst must go quiet before the collector
  /// re-scans. Exposed for tests, not tunable in the UI.
  static const Duration debounceDuration = Duration(milliseconds: 300);

  @override
  State<UnresolvedVarsChip> createState() => _UnresolvedVarsChipState();
}

class _UnresolvedVarsChipState extends State<UnresolvedVarsChip> {
  final Debouncer _debouncer = Debouncer(
    duration: UnresolvedVarsChip.debounceDuration,
  );

  // The last (config, LayeredVariableContext) pair a recompute was
  // scheduled/run for — used only to skip re-arming the debounce when an
  // unrelated rebuild passes identical inputs, not as the displayed result.
  HttpRequestConfigEntity? _scheduledConfig;
  LayeredVariableContext? _scheduledContext;

  // The currently-DISPLAYED result. Updated synchronously on the very first
  // schedule (so a freshly-opened tab shows its unresolved count instantly)
  // and via the debounced timer thereafter.
  List<String> _displayed = const [];

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  void _scheduleRecompute(
    HttpRequestConfigEntity config,
    LayeredVariableContext varsContext,
  ) {
    if (config == _scheduledConfig && varsContext == _scheduledContext) {
      return;
    }
    final isFirstSchedule = _scheduledConfig == null;
    _scheduledConfig = config;
    _scheduledContext = varsContext;
    if (isFirstSchedule) {
      _displayed = UnresolvedVariableCollector.collect(
        config: config,
        variables: varsContext.allVariables,
      );
      return;
    }
    _debouncer.run(() {
      if (!mounted) return;
      final result = UnresolvedVariableCollector.collect(
        config: config,
        variables: varsContext.allVariables,
      );
      // Only commit if these are still the latest inputs — a stale timer
      // firing after a newer schedule already ran is a no-op (shouldn't
      // happen given Debouncer.run always cancels the previous timer, but
      // keeps this defensive rather than relying on that invariant).
      if (config != _scheduledConfig || varsContext != _scheduledContext) {
        return;
      }
      setState(() => _displayed = result);
    });
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
            _scheduleRecompute(config, varsContext);
            final unresolved = _displayed;
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
