import 'package:equatable/equatable.dart';

/// An established MCP session: the negotiated protocol version, the server's
/// self-reported identity, and the transport session id (from the
/// `Mcp-Session-Id` response header). Pure data — no transport concerns.
class McpSession extends Equatable {
  const McpSession({
    required this.sessionId,
    required this.protocolVersion,
    required this.serverName,
    required this.serverVersion,
  });

  /// Builds a session from an `initialize` JSON-RPC result, with the transport
  /// [sessionId] supplied separately (it rides on the HTTP response header, not
  /// the JSON-RPC body). Missing fields default to empty strings.
  factory McpSession.fromInitializeResult(
    Map<String, dynamic> result, {
    String? sessionId,
  }) {
    final info = (result['serverInfo'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return McpSession(
      sessionId: sessionId ?? '',
      protocolVersion: (result['protocolVersion'] as String?) ?? '',
      serverName: (info['name'] as String?) ?? '',
      serverVersion: (info['version'] as String?) ?? '',
    );
  }

  final String sessionId;
  final String protocolVersion;
  final String serverName;
  final String serverVersion;

  @override
  List<Object?> get props =>
      [sessionId, protocolVersion, serverName, serverVersion];
}
