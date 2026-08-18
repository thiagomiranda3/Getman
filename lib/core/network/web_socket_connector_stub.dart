// Web build's WebSocket connector: the browser WebSocket API cannot set
// custom request headers and the browser owns TLS/proxying/client certs,
// so both [headers] and [config] are ignored — auth on web must use a
// query param or subprotocol (documented limitation). Selected by
// web_socket_connector.dart's conditional export.
import 'package:getman/core/network/network_config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a WebSocket. [headers] and [config] are accepted for signature
/// parity with the io variant but cannot be applied from a browser.
WebSocketChannel connectWebSocketChannel(
  Uri uri,
  Map<String, String> headers,
  NetworkConfig config,
) => WebSocketChannel.connect(uri);
