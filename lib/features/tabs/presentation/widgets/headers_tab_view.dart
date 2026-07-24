// HEADERS tab of the request editor: HTTP headers as a Map<String, String>
// via KeyValueListEditor, with a BulkModeToggle for bulk-text editing and a
// per-row enable/disable checkbox (B1): a disabled header stays in the map
// (order preserved) but its key is parked in config.disabledHeaderKeys and
// skipped at send/code-gen. Renaming a disabled row's key renames the set
// entry; deleting the row prunes it. Composed by RequestConfigSection
// (split view) and UnifiedRequestPanel (phone).
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
                            equals: stringMapEquality.equals,
                            rowEnabled: (index) =>
                                index >= headerKeys.length ||
                                !disabledKeys.contains(headerKeys[index]),
                            onToggleEnabled: (index, key, value, enabled) =>
                                toggle(key, enabled: enabled),
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
