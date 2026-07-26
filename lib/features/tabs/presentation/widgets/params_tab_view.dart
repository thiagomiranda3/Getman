// PARAMS tab of the request editor: ordered key/value query parameters via
// KeyValueListEditor, with a BulkModeToggle for bulk-text editing and a
// per-row enable/disable checkbox (B1). Enabled rows derive from the URL
// (single source of truth); disabled rows are "parked" outside the URL in
// config.disabledParams and interleave at their remembered rowIndex, greyed
// and read-only (re-check to edit). Toggling updates URL + parked list in
// one UpdateTab via ParamRowComposer. Composed by RequestConfigSection
// (split view) and UnifiedRequestPanel (phone).
//
// B2: drag-reorder and duplicate operate on display indices over the
// composed (enabled + parked) row list. Reorder/duplicate touch only the
// enabled/URL sequence — a parked row has no live URL position, so an
// operation sourced from one is a no-op, and a parked row's rowIndex anchor
// is never recomputed from its new display position when an enabled row's
// drag crosses it.
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

        // B2: position IS the operation for these two — index-based over the
        // composed display list (parked rows included). Both re-read the
        // live tab (same guard as emit) and recompute display rows fresh
        // rather than closing over the outer `composed`, matching
        // toggle()/emit()'s existing pattern.
        //
        // Deviation from a naive "operate on config.params directly" (what
        // the plain brief sketch assumed pre-B1): parked rows have no live
        // URL position, so a reorder/duplicate sourced from a parked row is
        // a no-op rather than inventing park semantics nothing else
        // specifies. When an ENABLED row's drag crosses a parked row's
        // display slot, only the enabled/URL sequence is rewritten — a
        // parked row's own rowIndex anchor (disabledParams) is left
        // completely untouched, never recomputed from its new display
        // position.
        void reorder(int oldIndex, int newIndex) {
          final bloc = context.read<TabsBloc>();
          final current = bloc.state.tabs.byId(tabId);
          if (current == null) return;
          final displayRows = ParamRowComposer.compose(
            params: current.config.params,
            parked: current.config.disabledParams,
          );
          if (oldIndex < 0 || oldIndex >= displayRows.length) return;
          if (!displayRows[oldIndex].enabled) return;
          final oldEnabledIndex = displayRows
              .take(oldIndex)
              .where((r) => r.enabled)
              .length;
          final afterRemoval = [...displayRows]..removeAt(oldIndex);
          final target = newIndex.clamp(0, afterRemoval.length);
          final newEnabledIndex = afterRemoval
              .take(target)
              .where((r) => r.enabled)
              .length;
          final enabledRows = [...current.config.params];
          final row = enabledRows.removeAt(oldEnabledIndex);
          enabledRows.insert(
            newEnabledIndex.clamp(0, enabledRows.length),
            row,
          );
          bloc.add(
            UpdateTab(
              current.copyWith(
                config: current.config.copyWith(params: enabledRows),
              ),
            ),
          );
        }

        void duplicate(int index) {
          final bloc = context.read<TabsBloc>();
          final current = bloc.state.tabs.byId(tabId);
          if (current == null) return;
          final displayRows = ParamRowComposer.compose(
            params: current.config.params,
            parked: current.config.disabledParams,
          );
          if (index < 0 || index >= displayRows.length) return;
          if (!displayRows[index].enabled) return;
          final enabledIndex = displayRows
              .take(index)
              .where((r) => r.enabled)
              .length;
          final enabledRows = [...current.config.params];
          // Exact duplicate — duplicate keys are legal in a query string.
          enabledRows.insert(enabledIndex + 1, enabledRows[enabledIndex]);
          bloc.add(
            UpdateTab(
              current.copyWith(
                config: current.config.copyWith(params: enabledRows),
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
                            onReorder: reorder,
                            onDuplicate: duplicate,
                          ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
