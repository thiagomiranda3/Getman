// PARAMS tab of the request editor: ordered key/value query parameters via
// KeyValueListEditor, with a BulkModeToggle for bulk-text editing. Composed
// by RequestConfigSection (split view) and UnifiedRequestPanel (phone).
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/ui/widgets/bulk_kv_editor.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/ui/widgets/tab_variable_context_builder.dart';
import 'package:getman/core/utils/bulk_kv_codec.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/bulk_mode_toggle.dart';

const ListEquality<QueryParamEntity> _queryParamListEquality =
    ListEquality<QueryParamEntity>();

/// Ordered query-param editor. Duplicate keys allowed, order preserved —
/// the URL is the single source of truth, so edits round-trip through it.
class ParamsTabView extends StatefulWidget {
  const ParamsTabView({required this.tabId, super.key});
  final String tabId;

  @override
  State<ParamsTabView> createState() => _ParamsTabViewState();
}

class _ParamsTabViewState extends State<ParamsTabView> {
  // Ephemeral view preference (D7): not persisted, resets to row on reload.
  bool _bulk = false;

  @override
  Widget build(BuildContext context) {
    final tabId = widget.tabId;
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        // URL carries the query — a single equality check captures any params
        // change that would affect this tab.
        return prev.tabs.byId(tabId)?.config.url !=
            next.tabs.byId(tabId)?.config.url;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();

        List<QueryParamEntity> encode(List<(String, String)> rows) => [
          for (final (key, value) in rows)
            if (key.isNotEmpty) QueryParamEntity(key: key, value: value),
        ];
        List<(String, String)> decode(List<QueryParamEntity> params) => [
          for (final p in params) (p.key, p.value),
        ];
        void emit(List<QueryParamEntity> list) {
          final bloc = context.read<TabsBloc>();
          final current = bloc.state.tabs.byId(tabId);
          if (current == null) return;
          bloc.add(
            UpdateTab(
              current.copyWith(config: current.config.copyWith(params: list)),
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
                      fieldPrefix: 'param',
                      initialText: BulkKvCodec.serialize(
                        decode(tab.config.params),
                      ),
                      canonicalize: (raw) =>
                          BulkKvCodec.serialize(BulkKvCodec.parse(raw)),
                      onChanged: (text) =>
                          emit(encode(BulkKvCodec.parse(text))),
                    )
                  : TabVariableContextBuilder(
                      tabId: tab.tabId,
                      builder: (context, varContext) =>
                          KeyValueListEditor<List<QueryParamEntity>>(
                            items: tab.config.params,
                            variableContext: varContext,
                            fieldPrefix: 'param',
                            decode: decode,
                            encode: encode,
                            equals: _queryParamListEquality.equals,
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
