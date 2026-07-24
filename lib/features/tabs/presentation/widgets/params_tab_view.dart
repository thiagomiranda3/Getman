// PARAMS tab of the request editor: ordered key/value query parameters via
// KeyValueListEditor, with a BulkModeToggle for bulk-text editing and a
// per-row enable/disable checkbox (B1). Enabled rows derive from the URL
// (single source of truth); disabled rows are "parked" outside the URL in
// config.disabledParams and interleave at their remembered rowIndex, greyed
// and read-only (re-check to edit). Toggling updates URL + parked list in
// one UpdateTab via ParamRowComposer. Composed by RequestConfigSection
// (split view) and UnifiedRequestPanel (phone).
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/parked_param_entity.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/ui/widgets/bulk_kv_editor.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/ui/widgets/tab_variable_context_builder.dart';
import 'package:getman/core/utils/bulk_kv_codec.dart';
import 'package:getman/core/utils/param_row_composer.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/bulk_mode_toggle.dart';

const ListEquality<ParamRow> _paramRowListEquality = ListEquality<ParamRow>();
const ListEquality<ParkedParamEntity> _parkedListEquality =
    ListEquality<ParkedParamEntity>();

/// Ordered query-param editor. Duplicate keys allowed, order preserved —
/// the URL is the single source of truth for enabled rows, so edits
/// round-trip through it; parked rows ride config.disabledParams.
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
        // URL carries the enabled query rows; disabledParams carries the
        // parked ones — together they capture any params change.
        final p = prev.tabs.byId(tabId)?.config;
        final n = next.tabs.byId(tabId)?.config;
        return p?.url != n?.url ||
            !_parkedListEquality.equals(p?.disabledParams, n?.disabledParams);
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();

        final composed = ParamRowComposer.compose(
          params: tab.config.params,
          parked: tab.config.disabledParams,
        );

        List<(String, String)> decode(List<ParamRow> rows) => [
          for (final r in rows) (r.key, r.value),
        ];
        List<ParamRow> encode(List<(String, String)> rows) {
          final result = ParamRowComposer.decompose(
            rows: rows,
            parked: tab.config.disabledParams,
          );
          return ParamRowComposer.compose(
            params: result.params,
            parked: result.parked,
          );
        }

        void emit(List<ParamRow> rows) {
          final bloc = context.read<TabsBloc>();
          final current = bloc.state.tabs.byId(tabId);
          if (current == null) return;
          bloc.add(
            UpdateTab(
              current.copyWith(
                config: current.config.copyWith(
                  params: [
                    for (final r in rows)
                      if (r.enabled)
                        QueryParamEntity(key: r.key, value: r.value),
                  ],
                  disabledParams: [
                    for (final (i, r) in rows.indexed)
                      if (!r.enabled)
                        ParkedParamEntity(
                          key: r.key,
                          value: r.value,
                          rowIndex: i,
                        ),
                  ],
                ),
              ),
            ),
          );
        }

        void toggle(int displayIndex, {required bool enabled}) {
          final bloc = context.read<TabsBloc>();
          final current = bloc.state.tabs.byId(tabId);
          if (current == null) return;
          final result = enabled
              ? ParamRowComposer.unpark(
                  params: current.config.params,
                  parked: current.config.disabledParams,
                  displayIndex: displayIndex,
                )
              : ParamRowComposer.park(
                  params: current.config.params,
                  parked: current.config.disabledParams,
                  displayIndex: displayIndex,
                );
          // Single UpdateTab: URL rewrite + parked list change atomically.
          bloc.add(
            UpdateTab(
              current.copyWith(
                config: current.config.copyWith(
                  params: result.params,
                  disabledParams: result.parked,
                ),
              ),
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
                      initialText: BulkKvCodec.serializeRows([
                        for (final r in composed)
                          (key: r.key, value: r.value, disabled: !r.enabled),
                      ]),
                      canonicalize: (raw) => BulkKvCodec.serializeRows(
                        BulkKvCodec.parseRows(raw),
                      ),
                      onChanged: (text) => emit([
                        for (final r in BulkKvCodec.parseRows(text))
                          ParamRow(
                            key: r.key,
                            value: r.value,
                            enabled: !r.disabled,
                          ),
                      ]),
                    )
                  : TabVariableContextBuilder(
                      tabId: tab.tabId,
                      builder: (context, varContext) =>
                          KeyValueListEditor<List<ParamRow>>(
                            items: composed,
                            variableContext: varContext,
                            fieldPrefix: 'param',
                            decode: decode,
                            encode: encode,
                            equals: _paramRowListEquality.equals,
                            rowEnabled: (index) =>
                                index >= composed.length ||
                                composed[index].enabled,
                            onToggleEnabled: (index, key, value, enabled) =>
                                toggle(index, enabled: enabled),
                            disabledRowsReadOnly: true,
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
