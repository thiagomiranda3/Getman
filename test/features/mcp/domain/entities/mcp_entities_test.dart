import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/mcp/domain/entities/mcp_session.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool.dart';
import 'package:getman/features/mcp/domain/entities/mcp_tool_result.dart';

void main() {
  group('McpSession.fromInitializeResult', () {
    test('reads server info + protocol version, sessionId from header', () {
      final s = McpSession.fromInitializeResult(
        const {
          'protocolVersion': '2025-06-18',
          'serverInfo': {'name': 'demo', 'version': '1.2.3'},
        },
        sessionId: 'abc-123',
      );
      expect(s.sessionId, 'abc-123');
      expect(s.protocolVersion, '2025-06-18');
      expect(s.serverName, 'demo');
      expect(s.serverVersion, '1.2.3');
    });

    test('tolerates missing fields with safe defaults', () {
      final s = McpSession.fromInitializeResult(const {});
      expect(s.sessionId, '');
      expect(s.serverName, '');
      expect(s.protocolVersion, '');
    });
  });

  group('McpTool.fromJson', () {
    test('parses name, description, and raw input schema', () {
      final t = McpTool.fromJson(const {
        'name': 'add',
        'description': 'Adds numbers',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'a': {'type': 'number'},
          },
        },
      });
      expect(t.name, 'add');
      expect(t.description, 'Adds numbers');
      expect(t.inputSchema['type'], 'object');
    });

    test('defaults description to empty and schema to empty map', () {
      final t = McpTool.fromJson(const {'name': 'noop'});
      expect(t.description, '');
      expect(t.inputSchema, isEmpty);
    });
  });

  group('McpToolResult.fromJson', () {
    test('collects text blocks and isError flag', () {
      final r = McpToolResult.fromJson(const {
        'isError': true,
        'content': [
          {'type': 'text', 'text': 'boom'},
          {'type': 'text', 'text': 'second'},
        ],
      });
      expect(r.isError, isTrue);
      expect(r.textBlocks, ['boom', 'second']);
    });

    test('keeps non-text blocks as raw maps and defaults isError to false', () {
      final r = McpToolResult.fromJson(const {
        'content': [
          {'type': 'image', 'data': 'xxx', 'mimeType': 'image/png'},
        ],
      });
      expect(r.isError, isFalse);
      expect(r.textBlocks, isEmpty);
      expect(r.rawBlocks.single['type'], 'image');
    });
  });
}
