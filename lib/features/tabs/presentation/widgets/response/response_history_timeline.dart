import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/byte_format.dart';
import 'package:getman/features/tabs/domain/entities/response_history_entry.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

/// Time-travel control for the response metadata row: a dropdown of recent
/// responses (newest-first). Selecting one swaps the displayed response via
/// [ViewResponseHistoryEntry]. Hidden when fewer than two responses exist.
class ResponseHistoryTimeline extends StatelessWidget {
  const ResponseHistoryTimeline({
    required this.tabId,
    required this.history,
    required this.current,
    super.key,
  });

  final String tabId;
  final List<ResponseHistoryEntry> history;
  final HttpResponseEntity? current;

  static String _clock(int epochMillis) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMillis);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final layout = context.appLayout;

    // The displayed entry is the one whose response matches `current`; default
    // to the head (newest) when nothing matches.
    final currentIndex = current == null
        ? 0
        : history.indexWhere((e) => e.response == current).clamp(0, 0x7fffffff);
    final viewingOld = currentIndex > 0;

    return PopupMenuButton<String>(
      key: const ValueKey('response_history_button'),
      tooltip: 'Response history',
      onSelected: (id) => context.read<TabsBloc>().add(
        ViewResponseHistoryEntry(tabId: tabId, entryId: id),
      ),
      itemBuilder: (context) => [
        for (var i = 0; i < history.length; i++)
          PopupMenuItem<String>(
            value: history[i].id,
            child: _MenuRow(
              entry: history[i],
              label: i == 0 ? 'Latest' : '#${i + 1}',
              selected: i == currentIndex,
              clock: _clock(history[i].capturedAt),
            ),
          ),
      ],
      child: Container(
        margin: EdgeInsets.only(right: layout.isCompact ? 8 : 12),
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: layout.isCompact ? 4 : 8,
        ),
        decoration: BoxDecoration(
          color: viewingOld
              ? theme.colorScheme.secondary.withValues(alpha: 0.2)
              : Colors.transparent,
          border: Border.all(
            color: theme.dividerColor,
            width: layout.borderThin,
          ),
          borderRadius: BorderRadius.circular(context.appShape.panelRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: layout.iconSize,
              color: theme.colorScheme.secondary,
            ),
            SizedBox(width: layout.tabSpacing),
            Text(
              viewingOld ? 'HISTORY: #${currentIndex + 1}' : 'HISTORY',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: layout.fontSizeSmall,
                fontWeight: context.appTypography.titleWeight,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: layout.iconSize,
              color: theme.colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.entry,
    required this.label,
    required this.selected,
    required this.clock,
  });

  final ResponseHistoryEntry entry;
  final String label;
  final bool selected;
  final String clock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final palette = context.appPalette;
    final r = entry.response;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: layout.iconSize,
          color: selected ? theme.colorScheme.secondary : theme.dividerColor,
        ),
        SizedBox(width: layout.tabSpacing),
        Text(
          '$label  ',
          style: TextStyle(
            fontSize: layout.fontSizeSmall,
            fontWeight: context.appTypography.titleWeight,
          ),
        ),
        Text(
          '${r.statusCode}',
          style: TextStyle(
            color: palette.statusAccent(r.statusCode),
            fontSize: layout.fontSizeSmall,
            fontWeight: context.appTypography.displayWeight,
          ),
        ),
        SizedBox(width: layout.tabSpacing),
        Text(
          '${r.durationMs}ms · ${formatBytes(responseSizeBytes(r))} · $clock',
          style: TextStyle(
            color: theme.colorScheme.secondary,
            fontSize: layout.fontSizeSmall,
          ),
        ),
      ],
    );
  }
}
