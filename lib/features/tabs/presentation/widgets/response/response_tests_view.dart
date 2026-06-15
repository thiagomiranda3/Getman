import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/assertion_result.dart';
import 'package:getman/core/domain/entities/extraction_result.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// TESTS tab: shows the per-send assertion results (with a pass/fail summary)
/// and any captured extraction values.
class ResponseTestsView extends StatelessWidget {
  final String tabId;
  const ResponseTestsView({super.key, required this.tabId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId);
        final n = next.tabs.byId(tabId);
        return p?.assertionResults != n?.assertionResults ||
            p?.extractionResults != n?.extractionResults;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();
        final assertions = tab.assertionResults;
        final extractions = tab.extractionResults;

        if (assertions.isEmpty && extractions.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(layout.pagePadding),
              child: Text(
                'NO RULES — ADD EXTRACTIONS OR ASSERTIONS IN THE RULES TAB',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  fontWeight: context.appTypography.titleWeight,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          );
        }

        final passed = assertions.where((a) => a.passed).length;
        return ListView(
          padding: EdgeInsets.all(layout.pagePadding),
          children: [
            if (assertions.isNotEmpty) ...[
              _testsSummary(context, passed, assertions.length),
              SizedBox(height: layout.tabSpacing),
              for (final a in assertions) _assertionRow(context, a),
            ],
            if (extractions.isNotEmpty) ...[
              SizedBox(height: layout.sectionSpacing),
              Text('CAPTURED',
                  style: TextStyle(
                      fontSize: layout.fontSizeSmall,
                      fontWeight: context.appTypography.displayWeight,
                      color: theme.colorScheme.secondary)),
              SizedBox(height: layout.tabSpacing),
              for (final e in extractions) _extractionRow(context, e),
            ],
          ],
        );
      },
    );
  }

  Widget _testsSummary(BuildContext context, int passed, int total) {
    final layout = context.appLayout;
    final allPassed = passed == total;
    final color = allPassed ? context.appPalette.statusSuccess : context.appPalette.statusError;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: layout.isCompact ? 4 : 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        border: Border.all(color: Theme.of(context).dividerColor, width: layout.borderThin),
      ),
      child: Text(
        '$passed / $total PASSED',
        style: TextStyle(
          color: context.appPalette.onColor(color),
          fontWeight: context.appTypography.displayWeight,
          fontSize: layout.fontSizeNormal,
        ),
      ),
    );
  }

  Widget _assertionRow(BuildContext context, AssertionResult a) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final color = a.passed ? context.appPalette.statusSuccess : context.appPalette.statusError;
    return Padding(
      padding: EdgeInsets.only(bottom: layout.tabSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + (below) the PASS/FAIL word — color is never the only signal.
          Icon(a.passed ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: color, size: layout.iconSize),
          SizedBox(width: layout.tabSpacing),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a.passed ? 'PASS' : 'FAIL'} · ${a.label}',
                    style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                        color: theme.colorScheme.onSurface)),
                Text('got: ${a.actual}',
                    style: TextStyle(
                        fontSize: layout.fontSizeSmall,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _extractionRow(BuildContext context, ExtractionResult e) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final color = e.matched ? context.appPalette.statusSuccess : context.appPalette.statusError;
    return Padding(
      padding: EdgeInsets.only(bottom: layout.tabSpacing),
      child: Row(
        children: [
          Icon(e.matched ? Icons.download_done : Icons.search_off,
              color: color, size: layout.smallIconSize),
          SizedBox(width: layout.tabSpacing),
          Expanded(
            child: Text(
              e.matched ? '{{${e.variable}}} = ${e.value}' : '{{${e.variable}}} — not found',
              style: TextStyle(
                  fontSize: layout.fontSizeNormal,
                  color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
