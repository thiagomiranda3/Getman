// Side-menu HISTORY tab: a debounced search field over HistoryBloc's
// newest-first list (filter by URL/method/status code) with day-group
// headers (TODAY / YESTERDAY / 'MON, JUL 20' / EARLIER via
// groupHistoryByDay), a hover ✕ per row (instant delete + 5 s UNDO
// snackbar), and a CLEAR ALL toolbar button (ConfirmDialog, then UNDO
// snackbar restoring the captured list) — the A1 undo patterns. Tapping an
// entry opens it as a new (unlinked) tab via AddTab with the stored,
// templated config — re-sending stays free to pick up whatever environment
// is active. Zero-history first-run shows guidance copy, distinct from the
// search-miss 'NO RESULTS FOUND'.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/core/ui/widgets/hover_highlight.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
import 'package:getman/core/utils/debouncer.dart';
import 'package:getman/features/history/domain/logic/history_day_grouper.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_event.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

class HistoryList extends StatefulWidget {
  const HistoryList({super.key});

  @override
  State<HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<HistoryList> {
  final TextEditingController _searchController = TextEditingController();
  // Debounced query drives only the results list (via ValueListenableBuilder),
  // so the search field and surrounding chrome don't rebuild on every keystroke
  // and the O(n) filter runs only once typing pauses.
  final ValueNotifier<String> _query = ValueNotifier<String>('');
  final Debouncer _debouncer = Debouncer();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
      () => _debouncer.run(() => _query.value = _searchController.text),
    );
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _query.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// A1 single-item pattern: instant delete, then a 5 s UNDO snackbar that
  /// restores the captured record.
  void _deleteEntry(BuildContext context, HttpRequestConfigEntity config) {
    final bloc = context.read<HistoryBloc>()
      ..add(DeleteHistoryEntry(config.id));
    showAppSnackBar(
      context,
      'History entry deleted',
      actionLabel: 'UNDO',
      duration: const Duration(seconds: 5),
      onAction: () => bloc.add(RestoreHistoryEntries([config])),
    );
  }

  /// A1 bulk pattern: ConfirmDialog first, then clear + a 5 s UNDO snackbar
  /// restoring the full captured list.
  void _confirmClearAll(BuildContext context) {
    final bloc = context.read<HistoryBloc>();
    final captured = List<HttpRequestConfigEntity>.of(bloc.state.history);
    if (captured.isEmpty) return;
    unawaited(
      ConfirmDialog.show(
        context,
        title: 'CLEAR ALL HISTORY',
        message: 'Clear all history?',
        confirmLabel: 'CLEAR',
        onConfirm: () {
          bloc.add(const ClearHistory());
          // ConfirmDialog pops itself before onConfirm runs, so this context
          // (the HistoryList's) is still mounted.
          showAppSnackBar(
            context,
            'History cleared',
            actionLabel: 'UNDO',
            duration: const Duration(seconds: 5),
            onAction: () => bloc.add(RestoreHistoryEntries(captured)),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return BlocBuilder<HistoryBloc, HistoryState>(
      builder: (context, state) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('history_search_field'),
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'SEARCH HISTORY...',
                        hintStyle: TextStyle(
                          fontSize: layout.fontSizeSmall,
                          fontWeight: context.appTypography.displayWeight,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          size: layout.iconSize,
                          color: theme.colorScheme.onSurface,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            context.appShape.panelRadius,
                          ),
                          borderSide: BorderSide(
                            color: theme.dividerColor,
                            width: layout.borderThin,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        isDense: true,
                      ),
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                  ),
                  SizedBox(width: layout.tabSpacing),
                  context.appDecoration.wrapInteractive(
                    child: TextButton(
                      key: const ValueKey('history_clear_all'),
                      onPressed: state.history.isEmpty
                          ? null
                          : () => _confirmClearAll(context),
                      child: Text(
                        'CLEAR ALL',
                        style: TextStyle(
                          fontSize: layout.fontSizeSmall,
                          fontWeight: context.appTypography.displayWeight,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.isLoading && state.history.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ValueListenableBuilder<String>(
                      valueListenable: _query,
                      builder: (context, query, _) =>
                          _buildList(context, state.history, query),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    List<HttpRequestConfigEntity> history,
    String rawQuery,
  ) {
    final query = rawQuery.toLowerCase();
    final items = query.isEmpty
        ? history
        : history
              .where(
                (item) =>
                    item.url.toLowerCase().contains(query) ||
                    (item.statusCode?.toString().contains(query) ?? false) ||
                    item.method.toLowerCase().contains(query),
              )
              .toList();

    if (items.isEmpty) {
      // First-run (nothing sent yet, no query) vs. a search with no match.
      if (history.isEmpty && query.isEmpty) {
        return _buildFirstRunEmptyState(context);
      }
      return Center(
        child: Text(
          'NO RESULTS FOUND',
          style: TextStyle(
            fontSize: context.appLayout.fontSizeNormal,
            fontWeight: context.appTypography.displayWeight,
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    // Flatten day groups into a sealed row list so ListView.builder stays
    // lazy (only visible rows build their widgets).
    final groups = groupHistoryByDay(items, DateTime.now());
    final rows = <_HistoryRow>[
      for (final group in groups) ...[
        _HeaderRow(group.label),
        for (final config in group.entries) _EntryRow(config),
      ],
    ];

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) => switch (rows[index]) {
        _HeaderRow(:final label) => _DayHeader(
          key: ValueKey('history_group_$label'),
          label: label,
        ),
        _EntryRow(:final config) => _HistoryItemWidget(
          key: ValueKey(config.id),
          config: config,
          onTap: () {
            context.read<TabsBloc>().add(AddTab(config: config.copyWith()));
            Scaffold.maybeOf(context)?.closeDrawer();
          },
          onDelete: () => _deleteEntry(context, config),
        ),
      },
    );
  }

  /// First-run guidance — styled like the collections tree's empty state
  /// (icon + caps title + sentence subtitle), with a distinct icon/copy.
  Widget _buildFirstRunEmptyState(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(layout.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_toggle_off,
              size: layout.iconSize * 2,
              color: theme.dividerColor,
            ),
            SizedBox(height: layout.sectionSpacing),
            Text(
              'NO REQUESTS SENT YET',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: layout.fontSizeNormal,
                fontWeight: context.appTypography.displayWeight,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            SizedBox(height: layout.tabSpacing),
            Text(
              'Sent requests appear here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.bodyWeight,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sealed union for the flattened, lazily-built list: a day header or an
/// entry (mirrors collections_list.dart's _TreeItem pattern).
sealed class _HistoryRow {}

class _HeaderRow extends _HistoryRow {
  _HeaderRow(this.label);
  final String label;
}

class _EntryRow extends _HistoryRow {
  _EntryRow(this.config);
  final HttpRequestConfigEntity config;
}

/// One day-group header (TODAY / YESTERDAY / 'MON, JUL 20' / EARLIER).
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.inputPadding,
        layout.tabSpacing,
        layout.inputPadding,
        layout.tabSpacing / 2,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            fontSize: layout.fontSizeSmall,
            fontWeight: context.appTypography.displayWeight,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _HistoryItemWidget extends StatefulWidget {
  const _HistoryItemWidget({
    required this.config,
    required this.onTap,
    required this.onDelete,
    super.key,
  });
  final HttpRequestConfigEntity config;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_HistoryItemWidget> createState() => _HistoryItemWidgetState();
}

class _HistoryItemWidgetState extends State<_HistoryItemWidget> {
  // Drives the hover-only ✕. Separate from HoverHighlight's internal hover
  // (which only repaints the background decoration, not the tile subtree).
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    // The ListTile is built once here and passed as the stable child of
    // HoverHighlight, so hovering rebuilds only this row, not siblings.
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: HoverHighlight(
        decoration: (hovered) => BoxDecoration(
          color: hovered ? theme.hoverColor : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.1),
            ),
          ),
        ),
        // The hover background is painted by HoverHighlight's
        // AnimatedContainer (a colored BoxDecoration). A transparency
        // Material gives the ListTile its own ink surface so Flutter 3.44
        // doesn't assert that the colored container hides the tile's
        // background/splash — the hover color behind it still shows through.
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            dense: true,
            onTap: widget.onTap,
            title: Text(
              widget.config.url.isEmpty ? '(NO URL)' : widget.config.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: layout.fontSizeNormal,
                fontWeight: context.appTypography.titleWeight,
              ),
            ),
            subtitle: Row(
              children: [
                MethodBadge(method: widget.config.method, small: true),
                if (widget.config.statusCode != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    widget.config.statusCode.toString(),
                    style: TextStyle(
                      color: context.appPalette.statusColor(
                        widget.config.statusCode!,
                      ),
                      fontWeight: context.appTypography.displayWeight,
                      fontSize: layout.fontSizeNormal,
                    ),
                  ),
                ],
              ],
            ),
            trailing: _hovered
                ? IconButton(
                    key: ValueKey('history_delete_${widget.config.id}'),
                    icon: Icon(
                      Icons.close,
                      size: layout.smallIconSize,
                      color: theme.colorScheme.error,
                    ),
                    tooltip: 'Delete entry',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.all(layout.badgePaddingVertical),
                    onPressed: widget.onDelete,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
