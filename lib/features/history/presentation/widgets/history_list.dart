import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/hover_highlight.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';
import 'package:getman/core/utils/debouncer.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
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
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'SEARCH HISTORY...',
                  hintStyle: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    fontWeight: context.appTypography.displayWeight,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final config = items[index];
        return _HistoryItemWidget(
          key: ValueKey(config.id),
          config: config,
          onTap: () {
            context.read<TabsBloc>().add(AddTab(config: config.copyWith()));
            Scaffold.maybeOf(context)?.closeDrawer();
          },
        );
      },
    );
  }
}

class _HistoryItemWidget extends StatelessWidget {
  const _HistoryItemWidget({
    required this.config,
    required this.onTap,
    super.key,
  });
  final HttpRequestConfigEntity config;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    // The ListTile is built once here and passed as the stable child of
    // HoverHighlight, so hovering rebuilds only the row's background, not the
    // tile + MethodBadge + text subtree.
    return HoverHighlight(
      decoration: (hovered) => BoxDecoration(
        color: hovered ? theme.hoverColor : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        title: Text(
          config.url.isEmpty ? '(NO URL)' : config.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: layout.fontSizeNormal,
            fontWeight: context.appTypography.titleWeight,
          ),
        ),
        subtitle: Row(
          children: [
            MethodBadge(method: config.method, small: true),
            if (config.statusCode != null) ...[
              const SizedBox(width: 8),
              Text(
                config.statusCode.toString(),
                style: TextStyle(
                  color: context.appPalette.statusColor(config.statusCode!),
                  fontWeight: context.appTypography.displayWeight,
                  fontSize: layout.fontSizeNormal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
