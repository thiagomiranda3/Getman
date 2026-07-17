// HEADERS tab of the request editor: HTTP headers as a Map<String, String>
// via KeyValueListEditor, with a BulkModeToggle for bulk-text editing.
// Composed by RequestConfigSection (split view) and UnifiedRequestPanel
// (phone).
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/ui/widgets/bulk_kv_editor.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/ui/widgets/tab_variable_context_builder.dart';
import 'package:getman/core/utils/bulk_kv_codec.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/bulk_mode_toggle.dart';

/// Header editor keyed as `Map<String, String>` — duplicates are not a real
/// concern for headers in this UI; last-write-wins is fine.
class HeadersTabView extends StatefulWidget {
  const HeadersTabView({required this.tabId, super.key});
  final String tabId;

  @override
  State<HeadersTabView> createState() => _HeadersTabViewState();
}

class _HeadersTabViewState extends State<HeadersTabView> {
  // Ephemeral view preference (D7): not persisted, resets to row on reload.
  bool _bulk = false;

  @override
  Widget build(BuildContext context) {
    final tabId = widget.tabId;
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) => !stringMapEquality.equals(
        prev.tabs.byId(tabId)?.config.headers,
        next.tabs.byId(tabId)?.config.headers,
      ),
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();

        Map<String, String> encode(List<(String, String)> rows) => {
          for (final (key, value) in rows)
            if (key.isNotEmpty) key: value,
        };
        List<(String, String)> decode(Map<String, String> headers) => [
          for (final e in headers.entries) (e.key, e.value),
        ];
        void emit(Map<String, String> map) {
          final bloc = context.read<TabsBloc>();
          final current = bloc.state.tabs.byId(tabId);
          if (current == null) return;
          bloc.add(
            UpdateTab(
              current.copyWith(config: current.config.copyWith(headers: map)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BulkModeToggle(
              bulk: _bulk,
              onToggle: () => setState(() => _bulk = !_bulk),
            ),
            Expanded(
              child: _bulk
                  ? BulkKvEditor(
                      fieldPrefix: 'header',
                      initialText: BulkKvCodec.serialize(
                        decode(tab.config.headers),
                      ),
                      canonicalize: (raw) =>
                          BulkKvCodec.serialize(BulkKvCodec.parse(raw)),
                      onChanged: (text) =>
                          emit(encode(BulkKvCodec.parse(text))),
                    )
                  : TabVariableContextBuilder(
                      tabId: tab.tabId,
                      builder: (context, varContext) =>
                          KeyValueListEditor<Map<String, String>>(
                            items: tab.config.headers,
                            variableContext: varContext,
                            fieldPrefix: 'header',
                            decode: decode,
                            encode: encode,
                            equals: stringMapEquality.equals,
                            onChanged: emit,
                          ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
