// BODY tab of the request editor: body-type selector (none/raw/urlencoded/
// multipart/binary/graphql) and the per-type editors — raw JSON editor,
// dual-pane GraphQL QUERY+VARIABLES editor, binary file picker. Composed by
// RequestConfigSection and UnifiedRequestPanel.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/tab_variable_context_builder.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/core/utils/path_utils.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/code_find_panel.dart'
    show kFindPanelHeight;
import 'package:getman/features/tabs/presentation/widgets/form_data_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/variable_code_autocomplete.dart';
import 'package:re_editor/re_editor.dart';

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
        return _RawBodyEditor(tabId: tabId, controller: controller);
      case BodyType.urlencoded:
        return FormDataEditor(tabId: tabId, allowFiles: false);
      case BodyType.multipart:
        return FormDataEditor(tabId: tabId, allowFiles: true);
      case BodyType.binary:
        return _BinaryBodyPicker(tabId: tabId);
      case BodyType.graphql:
        return _GraphqlBodyEditor(
          tabId: tabId,
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
    // theme-derived `activeBg` brightness (docs/architecture/theming.md
    // exception) — not a themeable surface color.
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

class _RawBodyEditor extends StatefulWidget {
  const _RawBodyEditor({required this.tabId, required this.controller});
  final String tabId;
  final CodeLineEditingController controller;

  @override
  State<_RawBodyEditor> createState() => _RawBodyEditorState();
}

class _RawBodyEditorState extends State<_RawBodyEditor> {
  // Owned here (not left to CodeEditor's internal one) so the Beautify
  // overlay can observe find-mode state and drop below the open find panel —
  // otherwise it sits on top of the panel's close button.
  late CodeFindController _findController;

  @override
  void initState() {
    super.initState();
    _findController = CodeFindController(widget.controller);
  }

  @override
  void didUpdateWidget(covariant _RawBodyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _findController.dispose();
      _findController = CodeFindController(widget.controller);
    }
  }

  @override
  void dispose() {
    _findController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Stack(
      children: [
        // The variable context rebuilds on env/collection change, recreating
        // the prompts builder with the fresh context so env switches apply.
        // The Beautify overlay stays outside the autocomplete wrap.
        TabVariableContextBuilder(
          tabId: widget.tabId,
          builder: (context, varContext) => wrapBodyWithVariableAutocomplete(
            contextProvider: () => varContext,
            child: JsonCodeEditor(
              controller: widget.controller,
              findController: _findController,
            ),
          ),
        ),
        ValueListenableBuilder<CodeFindValue?>(
          valueListenable: _findController,
          builder: (context, findValue, child) => Positioned(
            // The find panel overlays the editor's top edge; clear it while
            // open so the button doesn't cover the panel's close button.
            top: 8 + (findValue == null ? 0 : kFindPanelHeight),
            right: 8,
            child: child!,
          ),
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
                final original = widget.controller.text;
                final prettified = await JsonUtils.prettify(original);
                // prettify runs in an isolate: the tab may have closed
                // (disposed controller) or the user may have kept typing
                // (their newer text must win) while it ran.
                if (!mounted || widget.controller.text != original) return;
                if (prettified != original) {
                  widget.controller.text = prettified;
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
    required this.tabId,
    required this.queryController,
    required this.variablesController,
  });
  final String tabId;
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
            child: _RawBodyEditor(
              tabId: tabId,
              controller: variablesController,
            ),
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
