// Post-connect MCP UI (tool picker, JSON arguments editor, CALL, result,
// session log); see class doc below. Tool/result text mutations are always
// scheduled via addPostFrameCallback, never inline in build(), so controller
// updates (which notifyListeners) never fire mid-build.

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/tab_variable_context_builder.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/mcp_argument_resolver.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/variable_code_autocomplete.dart';
import 'package:re_editor/re_editor.dart';

/// Post-connect MCP UI for one tab: tool list, the selected tool's schema +
/// JSON arguments editor + CALL, the last result, and a session log.
/// Connecting itself is driven by the URL-bar CONNECT button.
class McpPanel extends StatefulWidget {
  const McpPanel({required this.tabId, super.key});
  final String tabId;

  @override
  State<McpPanel> createState() => _McpPanelState();
}

class _McpPanelState extends State<McpPanel> {
  // The arguments editor is variable-aware: its span builder reads the live
  // variable context + token colours via closures at paint time, so an env or
  // theme change recolours `{{var}}` tokens on the next forceRepaint — the same
  // wiring the request body editor uses.
  late final CodeLineEditingController _args;
  final CodeLineEditingController _schema = createJsonCodeController();
  final CodeLineEditingController _result = createJsonCodeController();
  String? _argsError;
  String? _editingTool;
  String _lastResultText = '';

  LayeredVariableContext _argsVarContext = LayeredVariableContext.empty;
  Color _resolvedColor = Colors.transparent;
  Color _unresolvedColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    _args = createJsonCodeController(
      variablesProvider: () => _argsVarContext.allVariables,
      resolvedColor: () => _resolvedColor,
      unresolvedColor: () => _unresolvedColor,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Theme is available here (not in initState). Recolour `{{var}}` tokens
    // when the variable palette changes (dark/light or theme switch).
    final palette = context.appPalette;
    if (_resolvedColor != palette.variableResolved ||
        _unresolvedColor != palette.variableUnresolved) {
      _resolvedColor = palette.variableResolved;
      _unresolvedColor = palette.variableUnresolved;
      _args.forceRepaint();
    }
  }

  @override
  void dispose() {
    _args.dispose();
    _schema.dispose();
    _result.dispose();
    super.dispose();
  }

  /// Stores the latest layered variable context (env + collection + dynamic)
  /// for the args editor's span builder and repaints visible lines so an env or
  /// collection switch recolours tokens without waiting for a keystroke.
  void _syncArgsVarContext(LayeredVariableContext ctx) {
    if (_argsVarContext == ctx) return;
    _argsVarContext = ctx;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _args.forceRepaint();
    });
  }

  // Fix 2: _syncForTool is no longer called from within build(). It is
  // scheduled via addPostFrameCallback so controller.text mutations
  // (which call notifyListeners) never fire mid-build.
  void _syncForTool(McpTool? tool) {
    if (tool?.name == _editingTool) return;
    _editingTool = tool?.name;
    _args.text = '{}';
    _argsError = null;
    _schema.text = tool == null
        ? ''
        : tool.inputSchema.isEmpty
        ? '(no input schema)'
        : const JsonEncoder.withIndent('  ').convert(tool.inputSchema);
  }

  void _call(BuildContext context, String toolName) {
    final raw = _args.text.trim().isEmpty ? '{}' : _args.text;
    Map<String, dynamic>? parsed;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) parsed = decoded;
    } on FormatException {
      parsed = null;
    }
    if (parsed == null) {
      setState(() => _argsError = 'Arguments must be a JSON object');
      return;
    }
    setState(() => _argsError = null);
    // Resolve `{{var}}` against the same live context that highlights them.
    final resolved = resolveMcpArguments(parsed, _argsVarContext.allVariables);
    context.read<McpBloc>().add(
      McpToolCallRequested(
        tabId: widget.tabId,
        toolName: toolName,
        arguments: resolved,
      ),
    );
  }

  String _resultText(McpTabSession s) {
    final r = s.lastResult;
    if (r == null) return '';
    if (r.textBlocks.isNotEmpty) return r.textBlocks.join('\n');
    if (r.rawBlocks.isNotEmpty) {
      return const JsonEncoder.withIndent('  ').convert(r.rawBlocks);
    }
    return r.isError ? '(error, no content)' : '(no content)';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<McpBloc, McpState>(
      buildWhen: (p, n) =>
          p.sessionFor(widget.tabId) != n.sessionFor(widget.tabId),
      builder: (context, state) {
        final s = state.sessionFor(widget.tabId);
        final layout = context.appLayout;
        final typo = context.appTypography;
        final theme = Theme.of(context);

        if (s.status != McpConnectionStatus.connected) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(layout.pagePadding),
              child: Text(
                switch (s.status) {
                  McpConnectionStatus.connecting => 'Connecting…',
                  McpConnectionStatus.error =>
                    s.errorMessage ?? 'Connection error',
                  _ => 'Not connected — press CONNECT to list tools',
                },
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: s.status == McpConnectionStatus.error
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface,
                  fontWeight: typo.bodyWeight,
                ),
              ),
            ),
          );
        }

        final selected = s.tools.firstWhereOrNull(
          (t) => t.name == s.selectedTool,
        );
        // Schedule off-build: avoids notifyListeners mid-build when the
        // selected tool changes and the controller text needs updating.
        if (selected?.name != _editingTool) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _syncForTool(selected));
          });
        }

        // Push the latest result into its read-only editor off-build, for the
        // same reason — only when it actually changed.
        final resultText = _resultText(s);
        if (resultText != _lastResultText) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _result.text = resultText;
              _lastResultText = resultText;
            }
          });
        }

        return Padding(
          padding: EdgeInsets.all(layout.inputPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tools (${s.tools.length})',
                style: TextStyle(fontWeight: typo.titleWeight),
              ),
              SizedBox(height: layout.inputPaddingVertical),
              // Tool selection chips.
              Wrap(
                spacing: layout.inputPaddingVertical,
                runSpacing: layout.inputPaddingVertical,
                children: s.tools
                    .map(
                      (t) => ChoiceChip(
                        label: Text(t.name),
                        selected: t.name == s.selectedTool,
                        onSelected: (_) => context.read<McpBloc>().add(
                          McpToolSelected(
                            tabId: widget.tabId,
                            toolName: t.name,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              SizedBox(height: layout.inputPadding),
              if (selected != null)
                Expanded(
                  child: _ToolDetail(
                    tool: selected,
                    argsEditor: SizedBox(
                      height: layout.mcpEditorPaneHeight,
                      // Feeds live env/collection variables to the args editor's
                      // highlighter (and, via _syncArgsVarContext, to CALL-time
                      // resolution). Rebuilds only on env/collection change.
                      child: TabVariableContextBuilder(
                        tabId: widget.tabId,
                        builder: (context, ctx) {
                          _syncArgsVarContext(ctx);
                          // Wrap with the `{{` variable autocomplete dropdown,
                          // same as the request body editor.
                          return wrapBodyWithVariableAutocomplete(
                            contextProvider: () => ctx,
                            child: JsonCodeEditor(
                              controller: _args,
                              autofocus: false,
                            ),
                          );
                        },
                      ),
                    ),
                    schemaController: _schema,
                    resultController: _result,
                    argsError: _argsError,
                    calling: s.calling,
                    hasResult: resultText.isNotEmpty,
                    resultIsError: s.lastResult?.isError ?? false,
                    log: s.log,
                    onCall: () => _call(context, selected.name),
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: Text(
                      'Select a tool above',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ToolDetail extends StatelessWidget {
  const _ToolDetail({
    required this.tool,
    required this.argsEditor,
    required this.schemaController,
    required this.resultController,
    required this.argsError,
    required this.calling,
    required this.hasResult,
    required this.resultIsError,
    required this.log,
    required this.onCall,
  });

  final McpTool tool;
  final Widget argsEditor;
  final CodeLineEditingController schemaController;
  final CodeLineEditingController resultController;
  final String? argsError;
  final bool calling;
  final bool hasResult;
  final bool resultIsError;
  final List<String> log;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typo = context.appTypography;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tool.description.isNotEmpty) ...[
            Text(
              tool.description,
              style: TextStyle(fontWeight: typo.bodyWeight),
            ),
            SizedBox(height: layout.inputPaddingVertical),
          ],
          Text(
            'Input schema',
            style: TextStyle(fontWeight: typo.titleWeight),
          ),
          SizedBox(height: layout.inputPaddingVertical),
          SizedBox(
            height: layout.mcpEditorPaneHeight,
            child: JsonCodeEditor(
              controller: schemaController,
              readOnly: true,
              autofocus: false,
            ),
          ),
          SizedBox(height: layout.inputPadding),
          Text(
            'Arguments (JSON)',
            style: TextStyle(fontWeight: typo.titleWeight),
          ),
          SizedBox(height: layout.inputPaddingVertical),
          argsEditor,
          if (argsError != null) ...[
            SizedBox(height: layout.inputPaddingVertical),
            Text(
              argsError!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          SizedBox(height: layout.inputPadding),
          Align(
            alignment: Alignment.centerLeft,
            child: context.appDecoration.wrapInteractive(
              child: ElevatedButton(
                key: const ValueKey('mcp_call_button'),
                onPressed: calling ? null : onCall,
                child: Text(
                  calling ? 'CALLING…' : 'CALL',
                  style: TextStyle(fontWeight: typo.displayWeight),
                ),
              ),
            ),
          ),
          if (hasResult) ...[
            SizedBox(height: layout.inputPadding),
            Text(
              resultIsError ? 'Result (error)' : 'Result',
              style: TextStyle(
                fontWeight: typo.titleWeight,
                color: resultIsError ? theme.colorScheme.error : null,
              ),
            ),
            SizedBox(height: layout.inputPaddingVertical),
            SizedBox(
              height: layout.mcpEditorPaneHeight,
              child: JsonCodeEditor(
                key: const ValueKey('mcp_result_view'),
                controller: resultController,
                readOnly: true,
                autofocus: false,
              ),
            ),
          ],
          // Fix 1: collapsible session log, shown when log is non-empty.
          // Lives inside the SingleChildScrollView — no RenderFlex overflow.
          if (log.isNotEmpty) ...[
            SizedBox(height: layout.inputPaddingVertical),
            // ExpansionTile builds a ListTile header; a transparency Material
            // gives it its own ink surface so Flutter 3.44 doesn't assert when
            // the panel's themed surface (a colored DecoratedBox) is its
            // nearest background ancestor.
            Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                key: const ValueKey('mcp_session_log'),
                title: Text(
                  'Session log',
                  style: TextStyle(fontWeight: typo.titleWeight),
                ),
                children: [
                  for (final entry in log)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: layout.inputPaddingVertical / 2,
                          horizontal: layout.inputPadding,
                        ),
                        child: Text(
                          entry,
                          style: TextStyle(
                            fontFamily: typo.codeFontFamily,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
