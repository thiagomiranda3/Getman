import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'code_find_panel.dart';

class ResponseBodyView extends StatefulWidget {
  final String tabId;
  final CodeLineEditingController responseController;
  const ResponseBodyView({super.key, required this.tabId, required this.responseController});

  @override
  State<ResponseBodyView> createState() => _ResponseBodyViewState();
}

class _ResponseBodyViewState extends State<ResponseBodyView> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _updateBody();
  }

  Future<void> _updateBody() async {
    if (mounted) setState(() => _isLoading = true);
    final tabsBloc = context.read<TabsBloc>();
    final tab = tabsBloc.state.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
    final prettified = await JsonUtils.prettify(tab?.responseBody);
    if (mounted) {
      widget.responseController.text = prettified;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) {
        final prevTab = prev.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
        final nextTab = next.tabs.firstWhereOrNull((t) => t.tabId == widget.tabId);
        return prevTab?.responseBody != nextTab?.responseBody;
      },
      listener: (context, state) {
        _updateBody();
      },
      child: Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.surface,
        child: _isLoading 
          ? const Center(child: RepaintBoundary(child: CircularProgressIndicator()))
          : CodeEditor(
              controller: widget.responseController,
              readOnly: true,
              wordWrap: true,
              findBuilder: (context, controller, readOnly) => CodeFindPanel(controller: controller, readOnly: readOnly),
              style: CodeEditorStyle(
                fontSize: 13,
                fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
                backgroundColor: Colors.transparent,
                cursorColor: Theme.of(context).primaryColor,
                selectionColor: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                cursorLineColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                codeTheme: CodeHighlightTheme(
                  languages: {
                    'json': CodeHighlightThemeMode(
                      mode: langJson,
                    ),
                  },
                  theme: Theme.of(context).brightness == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme,
                ),
              ),
              indicatorBuilder: (context, controller, chunkController, notifier) {
                return DefaultCodeLineNumber(
                  controller: controller,
                  notifier: notifier,
                );
              },
            ),
      ),
    );
  }
}
