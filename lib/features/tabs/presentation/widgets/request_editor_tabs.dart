import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:re_editor/re_editor.dart';

/// The three request-editor tab bodies (PARAMS / HEADERS / BODY), shared by
/// the split-pane [RequestConfigSection] and the phone [UnifiedRequestPanel]
/// so both layouts stay behaviorally identical.

const ListEquality<QueryParamEntity> _queryParamListEquality =
    ListEquality<QueryParamEntity>();

/// Ordered query-param editor. Duplicate keys allowed, order preserved —
/// the URL is the single source of truth, so edits round-trip through it.
class ParamsTabView extends StatelessWidget {
  final String tabId;
  const ParamsTabView({super.key, required this.tabId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        // URL carries the query — a single equality check captures any params
        // change that would affect this tab.
        return prev.tabs.byId(tabId)?.config.url != next.tabs.byId(tabId)?.config.url;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();
        return KeyValueListEditor<List<QueryParamEntity>>(
          items: tab.config.params,
          decode: (params) => [for (final p in params) (p.key, p.value)],
          encode: (rows) => [
            for (final (key, value) in rows)
              if (key.isNotEmpty) QueryParamEntity(key: key, value: value),
          ],
          equals: _queryParamListEquality.equals,
          onChanged: (list) {
            final bloc = context.read<TabsBloc>();
            final current = bloc.state.tabs.byId(tabId);
            if (current == null) return;
            bloc.add(UpdateTab(current.copyWith(config: current.config.copyWith(params: list))));
          },
        );
      },
    );
  }
}

/// Header editor keyed as `Map<String, String>` — duplicates are not a real
/// concern for headers in this UI; last-write-wins is fine.
class HeadersTabView extends StatelessWidget {
  final String tabId;
  const HeadersTabView({super.key, required this.tabId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) => !stringMapEquality.equals(
        prev.tabs.byId(tabId)?.config.headers,
        next.tabs.byId(tabId)?.config.headers,
      ),
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();
        return KeyValueListEditor<Map<String, String>>(
          items: tab.config.headers,
          decode: (headers) => [for (final e in headers.entries) (e.key, e.value)],
          encode: (rows) => {
            for (final (key, value) in rows)
              if (key.isNotEmpty) key: value,
          },
          equals: stringMapEquality.equals,
          onChanged: (map) {
            final bloc = context.read<TabsBloc>();
            final current = bloc.state.tabs.byId(tabId);
            if (current == null) return;
            bloc.add(UpdateTab(current.copyWith(config: current.config.copyWith(headers: map))));
          },
        );
      },
    );
  }
}

/// JSON body editor with the floating beautify affordance.
class BodyTabView extends StatelessWidget {
  final CodeLineEditingController controller;
  const BodyTabView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;

    return Stack(
      children: [
        JsonCodeEditor(controller: controller),
        Positioned(
          top: 8,
          right: 8,
          child: context.appDecoration.wrapInteractive(
            child: IconButton(
              icon: Icon(Icons.auto_fix_high,
                  color: theme.colorScheme.secondary, size: layout.isCompact ? 20 : 24),
              tooltip: 'Beautify JSON',
              onPressed: () async {
                final prettified = await JsonUtils.prettify(controller.text);
                controller.text = prettified;
              },
            ),
          ),
        ),
      ],
    );
  }
}
