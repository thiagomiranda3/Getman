import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';

class ResponseHeadersView extends StatelessWidget {
  final String tabId;
  const ResponseHeadersView({super.key, required this.tabId});

  @override
  Widget build(BuildContext context) {
    final layout = Theme.of(context).extension<LayoutExtension>()!;
    final theme = Theme.of(context);

    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        final tab = state.tabs.firstWhereOrNull((t) => t.tabId == tabId);
        final headers = tab?.responseHeaders;
        if (headers == null) return const SizedBox();
        
        final entries = headers.entries.toList();

        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final e = entries[index];
            return ListTile(
              dense: true,
              title: Text(e.key.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: layout.fontSizeNormal, color: theme.primaryColor)),
              subtitle: Text(e.value, style: TextStyle(fontSize: layout.fontSizeNormal, color: theme.colorScheme.onSurface)),
            );
          },
        );
      },
    );
  }
}
