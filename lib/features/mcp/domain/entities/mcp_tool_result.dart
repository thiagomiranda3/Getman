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
    final raw = content
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
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
