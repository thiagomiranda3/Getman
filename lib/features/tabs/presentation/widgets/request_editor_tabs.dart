import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/bulk_kv_editor.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/ui/widgets/variable_hover_popover.dart';
import 'package:getman/core/utils/bulk_kv_codec.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/core/utils/path_utils.dart';
import 'package:getman/features/environments/domain/logic/active_environment_helper.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/environments/presentation/bloc/environments_state.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/form_data_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/request_config_section.dart'
    show RequestConfigSection;
import 'package:getman/features/tabs/presentation/widgets/unified_request_panel.dart'
    show UnifiedRequestPanel;
import 'package:re_editor/re_editor.dart';

/// The three request-editor tab bodies (PARAMS / HEADERS / BODY), shared by
/// the split-pane [RequestConfigSection] and the phone [UnifiedRequestPanel]
/// so both layouts stay behaviorally identical.

/// Recomputes the active-environment [VariableHoverContext] and rebuilds when
/// the environment set or the active-environment id changes, so value-field
/// hover popovers always reflect the current environment.
class _VariableContextBuilder extends StatelessWidget {
  const _VariableContextBuilder({required this.builder});

  final Widget Function(BuildContext, VariableHoverContext) builder;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, n) =>
          p.settings.activeEnvironmentId != n.settings.activeEnvironmentId,
      builder: (context, settingsState) {
        return BlocBuilder<EnvironmentsBloc, EnvironmentsState>(
          buildWhen: (p, n) => p.environments != n.environments,
          builder: (context, envState) {
            final env = ActiveEnvironmentHelper.activeEnvironment(
              envState.environments,
              settingsState.settings.activeEnvironmentId,
            );
            return builder(
              context,
              VariableHoverContext(
                variables: env?.variables ?? const {},
                secretKeys: env?.secretKeys ?? const {},
                environmentName: env?.name,
              ),
            );
          },
        );
      },
    );
  }
}

/// Small header above the params/headers editor body offering the row⇄bulk
/// toggle. [bulk] is the current mode; [onToggle] flips it. The icon/label
/// describe the action the tap performs (Postman convention).
class _BulkModeToggle extends StatelessWidget {
  const _BulkModeToggle({required this.bulk, required this.onToggle});

  final bool bulk;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final theme = Theme.of(context);
    // In bulk mode the action returns to rows; in row mode it goes to bulk.
    final label = bulk ? 'Edit as rows' : 'Bulk edit';
    final icon = bulk ? Icons.view_list_outlined : Icons.notes_outlined;

    return Align(
      alignment: Alignment.centerRight,
      child: context.appDecoration.wrapInteractive(
        onTap: onToggle,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.badgePaddingHorizontal,
            vertical: layout.badgePaddingVertical,
          ),
          child: Tooltip(
            message: label,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: layout.smallIconSize,
                  color: theme.colorScheme.secondary,
                ),
                SizedBox(width: layout.tabSpacing),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    fontWeight: typography.titleWeight,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
            _BulkModeToggle(
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
                      onChanged: (text) =>
                          emit(encode(BulkKvCodec.parse(text))),
                    )
                  : _VariableContextBuilder(
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
            _BulkModeToggle(
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
                      onChanged: (text) =>
                          emit(encode(BulkKvCodec.parse(text))),
                    )
                  : _VariableContextBuilder(
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

/// Body editor: a body-type selector over conditional sub-editors. RAW keeps
/// the JSON editor + beautify affordance; urlencoded/multipart use
/// [FormDataEditor]; binary picks a file. The selector + sub-editor are shared
/// by both the split-pane and unified phone layouts.
class BodyTabView extends StatelessWidget {
  const BodyTabView({
    required this.tabId,
    required this.controller,
    required this.variablesController,
    super.key,
  });
  final String tabId;
  final CodeLineEditingController controller;
  final CodeLineEditingController variablesController;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) =>
          prev.tabs.byId(tabId)?.config.bodyType !=
          next.tabs.byId(tabId)?.config.bodyType,
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();
        final bodyType = tab.config.bodyType;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BodyTypeSelector(tabId: tabId, active: bodyType),
            Expanded(child: _editorFor(context, bodyType)),
          ],
        );
      },
    );
  }

  Widget _editorFor(BuildContext context, BodyType type) {
    switch (type) {
      case BodyType.none:
        return const _EmptyBodyHint();
      case BodyType.raw:
        return _RawBodyEditor(controller: controller);
      case BodyType.urlencoded:
        return FormDataEditor(tabId: tabId, allowFiles: false);
      case BodyType.multipart:
        return FormDataEditor(tabId: tabId, allowFiles: true);
      case BodyType.binary:
        return _BinaryBodyPicker(tabId: tabId);
      case BodyType.graphql:
        return _GraphqlBodyEditor(
          queryController: controller,
          variablesController: variablesController,
        );
    }
  }
}

class _BodyTypeSelector extends StatelessWidget {
  const _BodyTypeSelector({required this.tabId, required this.active});
  final String tabId;
  final BodyType active;

  static const Map<BodyType, String> _labels = {
    BodyType.none: 'NONE',
    BodyType.raw: 'RAW',
    BodyType.urlencoded: 'FORM',
    BodyType.multipart: 'MULTIPART',
    BodyType.binary: 'BINARY',
    BodyType.graphql: 'GRAPHQL',
  };

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: layout.pagePadding,
        vertical: layout.isCompact ? 6 : 10,
      ),
      child: Wrap(
        spacing: layout.tabSpacing,
        runSpacing: layout.tabSpacing,
        children: [
          for (final type in BodyType.values)
            if (_labels.containsKey(type))
              _BodyTypeChip(
                key: ValueKey('bodytype_${_labels[type]!}'),
                label: _labels[type]!,
                active: type == active,
                onTap: () {
                  final bloc = context.read<TabsBloc>();
                  final tab = bloc.state.tabs.byId(tabId);
                  if (tab == null || tab.config.bodyType == type) return;
                  bloc.add(
                    UpdateTab(
                      tab.copyWith(config: tab.config.copyWith(bodyType: type)),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _BodyTypeChip extends StatelessWidget {
  const _BodyTypeChip({
    required this.label,
    required this.active,
    required this.onTap,
    super.key,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final activeBg = context.appPalette.selectorActive;
    final activeIsDark =
        ThemeData.estimateBrightnessForColor(activeBg) == Brightness.dark;
    // Deliberate contrast: a readable foreground picked from the dynamic,
    // theme-derived `activeBg` brightness (CLAUDE.md §4.8 exception) — not a
    // themeable surface color.
    // ignore: avoid_hardcoded_brand_colors
    final onActive = activeIsDark ? Colors.white : Colors.black;
    return context.appDecoration.wrapInteractive(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: layout.badgePaddingHorizontal + 4,
          vertical: layout.badgePaddingVertical + 4,
        ),
        decoration: BoxDecoration(
          color: active ? activeBg : Colors.transparent,
          border: Border.all(
            color: theme.dividerColor,
            width: layout.borderThin,
          ),
          borderRadius: BorderRadius.circular(context.appShape.buttonRadius),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: layout.fontSizeSmall,
            fontWeight: context.appTypography.displayWeight,
            color: active ? onActive : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _RawBodyEditor extends StatelessWidget {
  const _RawBodyEditor({required this.controller});
  final CodeLineEditingController controller;

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
              icon: Icon(
                Icons.auto_fix_high,
                color: theme.colorScheme.secondary,
                size: layout.isCompact ? 20 : 24,
              ),
              tooltip: 'Beautify JSON',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final original = controller.text;
                final prettified = await JsonUtils.prettify(original);
                if (prettified != original) {
                  controller.text = prettified;
                  showAppSnackBarVia(messenger, 'JSON formatted');
                } else {
                  showAppSnackBarVia(
                    messenger,
                    'Already formatted or not valid JSON',
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Dual-pane GraphQL editor: QUERY on top (reuses the body controller bound to
/// `config.body`), VARIABLES (JSON) below (its own controller + beautify, since
/// variables are JSON).
class _GraphqlBodyEditor extends StatelessWidget {
  const _GraphqlBodyEditor({
    required this.queryController,
    required this.variablesController,
  });
  final CodeLineEditingController queryController;
  final CodeLineEditingController variablesController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: _GraphqlPane(
            label: 'QUERY',
            child: JsonCodeEditor(controller: queryController),
          ),
        ),
        Expanded(
          flex: 2,
          child: _GraphqlPane(
            label: 'VARIABLES (JSON)',
            child: _RawBodyEditor(controller: variablesController),
          ),
        ),
      ],
    );
  }
}

class _GraphqlPane extends StatelessWidget {
  const _GraphqlPane({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.pagePadding,
            vertical: layout.isCompact ? 4 : 6,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.displayWeight,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _EmptyBodyHint extends StatelessWidget {
  const _EmptyBodyHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Center(
      child: Text(
        'THIS REQUEST HAS NO BODY',
        style: TextStyle(
          fontSize: layout.fontSizeTitle,
          fontWeight: context.appTypography.displayWeight,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _BinaryBodyPicker extends StatelessWidget {
  const _BinaryBodyPicker({required this.tabId});
  final String tabId;

  Future<void> _pick(BuildContext context) async {
    final result = await FilePicker.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    if (picked.path == null) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          'Binary bodies need the desktop or mobile app.',
        );
      }
      return;
    }
    if (!context.mounted) return;
    final bloc = context.read<TabsBloc>();
    final tab = bloc.state.tabs.byId(tabId);
    if (tab == null) return;
    bloc.add(
      UpdateTab(
        tab.copyWith(config: tab.config.copyWith(bodyFilePath: picked.path)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) =>
          prev.tabs.byId(tabId)?.config.bodyFilePath !=
          next.tabs.byId(tabId)?.config.bodyFilePath,
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();
        final path = tab.config.bodyFilePath;
        final name = path == null ? null : PathUtils.basename(path);
        return Center(
          child: Padding(
            padding: EdgeInsets.all(layout.pagePadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  size: layout.isCompact ? 40 : 56,
                  color: theme.colorScheme.secondary,
                ),
                SizedBox(height: layout.sectionSpacing),
                Text(
                  name ?? 'NO FILE SELECTED',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: layout.fontSizeNormal,
                    fontWeight: context.appTypography.titleWeight,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: layout.sectionSpacing),
                ElevatedButton(
                  onPressed: () => _pick(context),
                  child: Text(name == null ? 'CHOOSE FILE' : 'CHANGE FILE'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
