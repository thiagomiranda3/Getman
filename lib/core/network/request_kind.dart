/// The protocol a request speaks. Orthogonal to the HTTP method — a WebSocket
/// or SSE request has no method. Persisted as an int discriminator (Hive field
/// 14 on the config model, default 0 = http) so existing records read as HTTP.
enum RequestKind {
  http(0),
  webSocket(1),
  sse(2)
  ;

  const RequestKind(this.wire);

  final int wire;

  static RequestKind fromWire(int? value) {
    for (final k in RequestKind.values) {
      if (k.wire == value) return k;
    }
    return RequestKind.http;
  }
}
