import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/request_kind.dart';

void main() {
  group('RequestKind', () {
    test('mcp has wire value 3', () {
      expect(RequestKind.mcp.wire, 3);
    });

    test('fromWire(3) resolves to mcp', () {
      expect(RequestKind.fromWire(3), RequestKind.mcp);
    });

    test('unknown wire falls back to http', () {
      expect(RequestKind.fromWire(99), RequestKind.http);
      expect(RequestKind.fromWire(null), RequestKind.http);
    });

    test('label returns the short protocol badge text', () {
      expect(RequestKind.http.label, 'HTTP');
      expect(RequestKind.webSocket.label, 'WS');
      expect(RequestKind.sse.label, 'SSE');
      expect(RequestKind.mcp.label, 'MCP');
    });
  });
}
