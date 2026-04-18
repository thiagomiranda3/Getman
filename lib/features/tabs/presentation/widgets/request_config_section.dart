import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:re_editor/re_editor.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/core/theme/neo_brutalist_theme.dart';
import 'key_value_editor.dart';
import 'code_find_panel.dart';

class RequestConfigSection extends StatelessWidget {
  final String tabId;
  final CodeLineEditingController bodyController;
  const RequestConfigSection({super.key, required this.tabId, required this.bodyController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = theme.extension<LayoutExtension>()!;

    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        final tab = state.tabs.firstWhereOrNull((t) => t.tabId == tabId);
        if (tab == null) return const SizedBox.shrink();

        return DefaultTabController(
          length: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabBar(
                dividerColor: Colors.transparent,
                isScrollable: true,
                indicator: BoxDecoration(
                  color: theme.primaryColor,
                  border: Border(
                    top: BorderSide(color: theme.dividerColor, width: 3),
                    left: BorderSide(color: theme.dividerColor, width: 3),
                    right: BorderSide(color: theme.dividerColor, width: 3),
                  ),
                ),
                labelColor: theme.colorScheme.onSurface,
                unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                labelStyle: TextStyle(fontSize: layout.fontSizeNormal, fontWeight: FontWeight.w900),
                tabs: const [
                  Tab(text: 'PARAMS'),
                  Tab(text: 'HEADERS'),
                  Tab(text: 'BODY'),
                ],
              ),
              Expanded(
                child: Container(
                  decoration: NeoBrutalistTheme.brutalBox(context, offset: 0),
                  child: TabBarView(
                    children: [
                      KeyValueEditor(
                        items: tab.config.params,
                        onChanged: (map) {
                          context.read<TabsBloc>().add(UpdateTab(
                            tab.copyWith(config: tab.config.copyWith(params: map)),
                          ));
                        },
                      ),
                      KeyValueEditor(
                        items: tab.config.headers,
                        onChanged: (map) {
                          context.read<TabsBloc>().add(UpdateTab(
                            tab.copyWith(config: tab.config.copyWith(headers: map)),
                          ));
                        },
                      ),
                      _buildBodyEditor(context, theme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBodyEditor(BuildContext context, ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      child: CodeEditor(
        controller: bodyController,
        wordWrap: true,
        findBuilder: (context, controller, readOnly) => CodeFindPanel(controller: controller, readOnly: readOnly),
        style: CodeEditorStyle(
          fontSize: 13,
          fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
          backgroundColor: Colors.transparent,
          cursorColor: theme.primaryColor,
          selectionColor: theme.primaryColor.withValues(alpha: 0.3),
          cursorLineColor: theme.primaryColor.withValues(alpha: 0.1),
          codeTheme: CodeHighlightTheme(
            languages: {
              'json': CodeHighlightThemeMode(
                mode: langJson,
              ),
            },
            theme: theme.brightness == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme,
          ),
        ),
        indicatorBuilder: (context, controller, chunkController, notifier) {
          return DefaultCodeLineNumber(
            controller: controller,
            notifier: notifier,
          );
        },
      ),
    );
  }
}
