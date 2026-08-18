// Result entity for an MCP `tools/call`; see class doc below.

import 'dart:convert';

import 'package:equatable/equatable.dart';

/// The result of a `tools/call`. [textBlocks] are the `type: "text"` content
/// items (the common case); [rawBlocks] preserves every content item verbatim
/// so non-text blocks (images, resources) can still be shown as raw JSON.
class McpToolResult extends Equatable {
  const McpToolResult({
    required this.isError,
    required this.textBlocks,
    required this.rawBlocks,
  });

  factory McpToolResult.fromJson(Map<String, dynamic> result) {
    final content = (result['content'] as List?) ?? const [];
    var raw = content
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    // 2025-06-18 spec (the version Getman negotiates): `content` is optional
    // when the tool declares an output schema — a result may carry only
    // `structuredContent`. Synthesize a pretty-printed `type: "text"` block
    // (feeding both textBlocks and rawBlocks below) so such a result renders
    // its data instead of "(no content)".
    final structured = result['structuredContent'];
    if (raw.isEmpty && structured is Map<dynamic, dynamic>) {
      raw = [
        {
          'type': 'text',
          'text': const JsonEncoder.withIndent('  ').convert(structured),
        },
      ];
    }
    final text = raw
        .where((m) => m['type'] == 'text')
        .map((m) => (m['text'] as String?) ?? '')
        .toList();
    return McpToolResult(
      isError: (result['isError'] as bool?) ?? false,
      textBlocks: text,
      rawBlocks: raw,
    );
  }

  final bool isError;
  final List<String> textBlocks;
  final List<Map<String, dynamic>> rawBlocks;

  @override
  List<Object?> get props => [isError, textBlocks, rawBlocks];
}
