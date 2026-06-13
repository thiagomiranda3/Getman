import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/query_param_entity.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/key_value_list_editor.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/form_data_editor.dart';
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

/// Body editor: a body-type selector over conditional sub-editors. RAW keeps
/// the JSON editor + beautify affordance; urlencoded/multipart use
/// [FormDataEditor]; binary picks a file. The selector + sub-editor are shared
/// by both the split-pane and unified phone layouts.
class BodyTabView extends StatelessWidget {
  final String tabId;
  final CodeLineEditingController controller;
  const BodyTabView({super.key, required this.tabId, required this.controller});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) =>
          prev.tabs.byId(tabId)?.config.bodyType != next.tabs.byId(tabId)?.config.bodyType,
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
    }
  }
}

class _BodyTypeSelector extends StatelessWidget {
  final String tabId;
  final BodyType active;
  const _BodyTypeSelector({required this.tabId, required this.active});

  static const Map<BodyType, String> _labels = {
    BodyType.none: 'NONE',
    BodyType.raw: 'RAW',
    BodyType.urlencoded: 'FORM',
    BodyType.multipart: 'MULTIPART',
    BodyType.binary: 'BINARY',
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
            _BodyTypeChip(
              label: _labels[type]!,
              active: type == active,
              onTap: () {
                final bloc = context.read<TabsBloc>();
                final tab = bloc.state.tabs.byId(tabId);
                if (tab == null || tab.config.bodyType == type) return;
                bloc.add(UpdateTab(tab.copyWith(config: tab.config.copyWith(bodyType: type))));
              },
            ),
        ],
      ),
    );
  }
}

class _BodyTypeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _BodyTypeChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final activeBg = context.appPalette.selectorActive;
    final onActive = ThemeData.estimateBrightnessForColor(activeBg) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return context.appDecoration.wrapInteractive(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: layout.badgePaddingHorizontal + 4,
          vertical: layout.badgePaddingVertical + 4,
        ),
        decoration: BoxDecoration(
          color: active ? activeBg : Colors.transparent,
          border: Border.all(color: theme.dividerColor, width: layout.borderThin),
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
  final CodeLineEditingController controller;
  const _RawBodyEditor({required this.controller});

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
  final String tabId;
  const _BinaryBodyPicker({required this.tabId});

  Future<void> _pick(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    if (picked.path == null) {
      if (context.mounted) {
        showAppSnackBar(context, 'Binary bodies need the desktop or mobile app.');
      }
      return;
    }
    if (!context.mounted) return;
    final bloc = context.read<TabsBloc>();
    final tab = bloc.state.tabs.byId(tabId);
    if (tab == null) return;
    bloc.add(UpdateTab(tab.copyWith(config: tab.config.copyWith(bodyFilePath: picked.path))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) =>
          prev.tabs.byId(tabId)?.config.bodyFilePath != next.tabs.byId(tabId)?.config.bodyFilePath,
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        if (tab == null) return const SizedBox.shrink();
        final path = tab.config.bodyFilePath;
        final name = path?.split(RegExp(r'[/\\]')).last;
        return Center(
          child: Padding(
            padding: EdgeInsets.all(layout.pagePadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insert_drive_file_outlined,
                    size: layout.isCompact ? 40 : 56, color: theme.colorScheme.secondary),
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
