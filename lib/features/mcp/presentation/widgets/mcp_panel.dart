import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_event.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
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
  final CodeLineEditingController _args = createJsonCodeController();
  final CodeLineEditingController _schema = createJsonCodeController();
  String? _argsError;
  String? _editingTool;

  @override
  void dispose() {
    _args.dispose();
    _schema.dispose();
    super.dispose();
  }

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
    context.read<McpBloc>().add(
      McpToolCallRequested(
        tabId: widget.tabId,
        toolName: toolName,
        arguments: parsed,
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
        _syncForTool(selected);

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
                    argsController: _args,
                    schemaController: _schema,
                    argsError: _argsError,
                    calling: s.calling,
                    resultText: _resultText(s),
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
    required this.argsController,
    required this.schemaController,
    required this.argsError,
    required this.calling,
    required this.resultText,
    required this.onCall,
  });

  final McpTool tool;
  final CodeLineEditingController argsController;
  final CodeLineEditingController schemaController;
  final String? argsError;
  final bool calling;
  final String resultText;
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
            height: 160,
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
          SizedBox(
            height: 160,
            child: JsonCodeEditor(
              controller: argsController,
              autofocus: false,
            ),
          ),
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
          if (resultText.isNotEmpty) ...[
            SizedBox(height: layout.inputPadding),
            Text('Result', style: TextStyle(fontWeight: typo.titleWeight)),
            SizedBox(height: layout.inputPaddingVertical),
            SelectableText(resultText),
          ],
        ],
      ),
    );
  }
}
