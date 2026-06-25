import 'package:equatable/equatable.dart';

/// A tool advertised by an MCP server via `tools/list`. [inputSchema] is the
/// tool's raw JSON Schema (kept verbatim; not modeled further in v1).
class McpTool extends Equatable {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  factory McpTool.fromJson(Map<String, dynamic> json) => McpTool(
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        inputSchema:
            (json['inputSchema'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{},
      );

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  @override
  List<Object?> get props => [name, description, inputSchema];
}
