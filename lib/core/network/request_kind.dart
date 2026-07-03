/// The protocol a request speaks. Orthogonal to the HTTP method — a WebSocket,
/// SSE, or MCP request has no method. Persisted as an int discriminator (Hive
/// field 14 on the config model, default 0 = http) so existing records read as
/// HTTP.
enum RequestKind {
  http(0),
  webSocket(1),
  sse(2),
  mcp(3);

  const RequestKind(this.wire);

  final int wire;

  /// Short uppercase label for the kind badge (collections tree, etc.).
  String get label => switch (this) {
    RequestKind.http => 'HTTP',
    RequestKind.webSocket => 'WS',
    RequestKind.sse => 'SSE',
    RequestKind.mcp => 'MCP',
  };

  static RequestKind fromWire(int? value) {
    for (final k in RequestKind.values) {
      if (k.wire == value) return k;
    }
    return RequestKind.http;
  }
}
