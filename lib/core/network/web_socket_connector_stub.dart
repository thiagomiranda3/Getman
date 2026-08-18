// Web build's WebSocket connector: the browser WebSocket API cannot set
// custom request headers, so they are ignored — auth on web must use a
// query param or subprotocol (documented limitation). Selected by
// web_socket_connector.dart's conditional export.
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a WebSocket. [headers] is accepted for signature parity with the
/// io variant but cannot be sent from a browser.
WebSocketChannel connectWebSocketChannel(
  Uri uri,
  Map<String, String> headers,
) => WebSocketChannel.connect(uri);
