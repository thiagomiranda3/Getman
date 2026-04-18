import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/history/presentation/bloc/history_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/history/domain/entities/request_config_entity.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';
import 'package:getman/core/ui/widgets/method_badge.dart';

class HistoryList extends StatefulWidget {
  const HistoryList({super.key});
  
  @override
  State<HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<HistoryList> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<HttpRequestConfigEntity> _items;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = List.from(context.read<HistoryBloc>().state.history);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;

    return BlocBuilder<HistoryBloc, HistoryState>(
      builder: (context, state) {
        return BlocListener<HistoryBloc, HistoryState>(
          listener: (context, state) {
            final next = state.history;
            if (_items.isEmpty && next.isNotEmpty) {
              setState(() {
                _items = List.from(next);
              });
              return;
            }

            if (next.length > _items.length) {
              final diff = next.length - _items.length;
              for (int i = 0; i < diff; i++) {
                _items.insert(i, next[i]);
                _listKey.currentState?.insertItem(i, duration: const Duration(milliseconds: 400));
              }
            } else if (next.length < _items.length) {
              if (next.isEmpty) {
                for (int i = _items.length - 1; i >= 0; i--) {
                  final removedItem = _items[i];
                  _listKey.currentState?.removeItem(
                    i, 
                    (context, animation) => _buildHistoryItem(removedItem, animation, isRemoved: true),
                    duration: const Duration(milliseconds: 300)
                  );
                }
                _items.clear();
                setState(() {});
              } else {
                setState(() {
                  _items = List.from(next);
                });
              }
            }
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'SEARCH HISTORY...',
                    hintStyle: TextStyle(fontSize: layout.fontSizeSmall, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    prefixIcon: Icon(Icons.search, size: layout.iconSize, color: theme.colorScheme.onSurface),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: theme.dividerColor, width: 2)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: state.isLoading && _items.isEmpty 
                  ? const Center(child: RepaintBoundary(child: CircularProgressIndicator())) 
                  : _buildList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList() {
    final query = _searchController.text.toLowerCase();
    final filteredItems = query.isEmpty 
      ? _items 
      : _items.where((item) => 
          item.url.toLowerCase().contains(query) || 
          (item.statusCode?.toString().contains(query) ?? false) ||
          item.method.toLowerCase().contains(query)
        ).toList();

    if (filteredItems.isEmpty) {
      return Center(
        child: Text('NO RESULTS FOUND', style: TextStyle(
          fontSize: 12, 
          fontWeight: FontWeight.w900, 
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5)
        )),
      );
    }

    if (query.isNotEmpty) {
       return ListView.builder(
         itemCount: filteredItems.length,
         itemBuilder: (context, index) {
            return HistoryItemWidget(
              config: filteredItems[index], 
              onTap: () {
                context.read<TabsBloc>().add(AddTab(config: filteredItems[index].copyWith()));
              },
            );
         },
       );
    }

    return AnimatedList(
      key: _listKey,
      initialItemCount: _items.length,
      itemBuilder: (context, index, animation) {
        return _buildHistoryItem(_items[index], animation);
      },
    );
  }

  Widget _buildHistoryItem(HttpRequestConfigEntity config, Animation<double> animation, {bool isRemoved = false}) {
    return SizeTransition(
      sizeFactor: animation,
      child: FadeTransition(
        opacity: animation,
        child: HistoryItemWidget(
          config: config, 
          onTap: isRemoved ? null : () {
            context.read<TabsBloc>().add(AddTab(config: config.copyWith()));
          },
        ),
      ),
    );
  }
}

class HistoryItemWidget extends StatefulWidget {
  final HttpRequestConfigEntity config;
  final VoidCallback? onTap;

  const HistoryItemWidget({super.key, required this.config, this.onTap});

  @override
  State<HistoryItemWidget> createState() => _HistoryItemWidgetState();
}

class _HistoryItemWidgetState extends State<HistoryItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isHovered ? theme.hoverColor : Colors.transparent,
          border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1), width: 1)),
        ),
        child: ListTile(
          dense: true,
          onTap: widget.onTap,
          title: Text(widget.config.url.isEmpty ? '(NO URL)' : widget.config.url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.bold),
          ),
          subtitle: Row(
            children: [
              MethodBadge(method: widget.config.method, small: true),
              if (widget.config.statusCode != null) ...[
                const SizedBox(width: 8),
                Text(widget.config.statusCode.toString(), style: TextStyle(
                  color: _getStatusColor(widget.config.statusCode!),
                  fontWeight: FontWeight.w900,
                  fontSize: layout.fontSizeNormal,
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(int code) {
    if (code >= 200 && code < 300) return Colors.green.shade700;
    if (code >= 400) return Colors.red.shade700;
    return Colors.orange.shade700;
  }
}
