// HEADERS tab of the request editor: HTTP headers as a Map<String, String>
// via KeyValueListEditor, with a BulkModeToggle for bulk-text editing and a
// per-row enable/disable checkbox (B1): a disabled header stays in the map
// (order preserved) but its key is parked in config.disabledHeaderKeys and
// skipped at send/code-gen. Renaming a disabled row's key renames the set
// entry; deleting the row prunes it. Composed by RequestConfigSection
// (split view) and UnifiedRequestPanel (phone).
//
// B2: drag-reorder rebuilds the insertion-ordered map; duplicate inserts a
// '-copy'-suffixed key below. Unlike params, a disabled header's row stays
// inline in the same map (position is orthogonal to disabledHeaderKeys, a
// key set), so neither operation needs B1-specific handling — both route
// through emit(), which already keeps disabledHeaderKeys in lockstep.
//
// 2B.3 follow-up fix: buildWhen and the `equals:` handed to
// KeyValueListEditor are order-SIGNIFICANT (`_orderedHeadersEqual`, layering
// a key-order ListEquality on top of the plain content MapEquality) — a
// plain MapEquality doesn't care about key order, so with a disabled row
// present a reorder-only UpdateTab (unequal at the entity level since 2B.2)
// would compare equal here, buildWhen would never let the rebuild through,
// and KeyValueListEditor would never see fresh `items` to resync its rows
// from. Concretely: the editor's own enabled-subsequence pre-move (see that
// file's header) computes zero local movement whenever dragging an enabled
// row only crosses disabled ones, so without this fix the canonical map
// silently diverges from the screen forever.
import 'package:collection/collection.dart';
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

const SetEquality<String> _stringSetEquality = SetEquality<String>();
const ListEquality<String> _stringListEquality = ListEquality<String>();

/// Order-SIGNIFICANT map equality: same key/value content is not enough —
/// the key SEQUENCE must match too. Header order is user-visible/editable
/// (drag reorder, B2), so a pure reorder must compare unequal — see the
/// file header's "2B.3 follow-up fix" note for why a plain `MapEquality`
/// here is the actual root cause of the order-desync bug.
bool _orderedHeadersEqual(Map<String, String> a, Map<String, String> b) =>
    stringMapEquality.equals(a, b) &&
    _stringListEquality.equals(a.keys.toList(), b.keys.toList());

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
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId)?.config;
        final n = next.tabs.byId(tabId)?.config;
        return !stringMapEquality.equals(p?.headers, n?.headers) ||
            !_stringListEquality.equals(
              p?.headers.keys.toList(),
              n?.headers.keys.toList(),
            ) ||
            !_stringSetEquality.equals(
              p?.disabledHeaderKeys,
              n?.disabledHeaderKeys,
            );
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();

        final headerKeys = tab.config.headers.keys.toList();
        final disabledKeys = tab.config.disabledHeaderKeys;

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
          // Keep disabledHeaderKeys in lockstep with the map: renaming a
          // disabled row's key renames the set entry; a deleted disabled row
          // is pruned (a stale set entry would keep the tab dirty forever).
          final oldKeys = current.config.headers.keys.toSet();
          final newKeys = map.keys.toSet();
          final removed = oldKeys.difference(newKeys);
          final added = newKeys.difference(oldKeys);
          var nextDisabled = current.config.disabledHeaderKeys;
          if (removed.isNotEmpty && nextDisabled.isNotEmpty) {
            final renamed =
                removed.length == 1 &&
                added.length == 1 &&
                nextDisabled.contains(removed.single);
            nextDisabled = {
              for (final key in nextDisabled)
                if (!removed.contains(key)) key,
              if (renamed) added.single,
            };
          }
          bloc.add(
            UpdateTab(
              current.copyWith(
                config: current.config.copyWith(
                  headers: map,
                  disabledHeaderKeys: nextDisabled,
                ),
              ),
            ),
          );
        }

        // B2: reorder rebuilds the insertion-ordered map; duplicate suffixes
        // '-copy' until unique (map keys must be unique, unlike params).
        // Both route through emit(), so disabledHeaderKeys stays in
        // lockstep exactly as it already does for edits/deletes/renames: a
        // pure reorder changes no keys (nextDisabled passes through
        // unchanged) and a duplicate only adds a key (the new row starts
        // enabled by default).
        void reorder(int oldIndex, int newIndex) {
          final current = context.read<TabsBloc>().state.tabs.byId(tabId);
          if (current == null) return;
          final entries = current.config.headers.entries.toList();
          if (oldIndex < 0 || oldIndex >= entries.length) return;
          final entry = entries.removeAt(oldIndex);
          entries.insert(newIndex.clamp(0, entries.length), entry);
          emit(Map.fromEntries(entries));
        }

        void duplicate(int index) {
          final current = context.read<TabsBloc>().state.tabs.byId(tabId);
          if (current == null) return;
          final headers = current.config.headers;
          final entries = headers.entries.toList();
          if (index < 0 || index >= entries.length) return;
          final source = entries[index];
          final keyBuffer = StringBuffer(source.key)..write('-copy');
          while (headers.containsKey(keyBuffer.toString())) {
            keyBuffer.write('-copy');
          }
          entries.insert(
            index + 1,
            MapEntry(keyBuffer.toString(), source.value),
          );
          emit(Map.fromEntries(entries));
        }

        void toggle(String key, {required bool enabled}) {
          final bloc = context.read<TabsBloc>();
          final current = bloc.state.tabs.byId(tabId);
          if (current == null) return;
          final trimmed = key.trim();
          if (trimmed.isEmpty || !current.config.headers.containsKey(trimmed)) {
            return;
          }
          final next = Set<String>.of(current.config.disabledHeaderKeys);
          enabled ? next.remove(trimmed) : next.add(trimmed);
          bloc.add(
            UpdateTab(
              current.copyWith(
                config: current.config.copyWith(disabledHeaderKeys: next),
              ),
            ),
          );
        }

        void emitBulk(Map<String, String> map, Set<String> disabled) {
          final bloc = context.read<TabsBloc>();
          final current = bloc.state.tabs.byId(tabId);
          if (current == null) return;
          bloc.add(
            UpdateTab(
              current.copyWith(
                config: current.config.copyWith(
                  headers: map,
                  disabledHeaderKeys: disabled,
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
                      fieldPrefix: 'header',
                      initialText: BulkKvCodec.serializeRows([
                        for (final e in tab.config.headers.entries)
                          (
                            key: e.key,
                            value: e.value,
                            disabled: disabledKeys.contains(e.key),
                          ),
                      ]),
                      canonicalize: (raw) => BulkKvCodec.serializeRows(
                        BulkKvCodec.parseRows(raw),
                      ),
                      onChanged: (text) {
                        final rows = BulkKvCodec.parseRows(text);
                        emitBulk(
                          {for (final r in rows) r.key: r.value},
                          {
                            for (final r in rows)
                              if (r.disabled) r.key,
                          },
                        );
                      },
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
                            equals: _orderedHeadersEqual,
                            rowEnabled: (index) =>
                                index >= headerKeys.length ||
                                !disabledKeys.contains(headerKeys[index]),
                            onToggleEnabled: (index, key, value, enabled) =>
                                toggle(key, enabled: enabled),
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
