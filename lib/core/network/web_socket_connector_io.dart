// dart:io WebSocket connector: custom request headers ride the handshake
// via IOWebSocketChannel — the HEADERS tab's Authorization etc. reaches the
// server on desktop instead of being silently dropped. Selected by
// web_socket_connector.dart's conditional export.
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a WebSocket, sending [headers] with the HTTP upgrade request.
/// An empty map keeps the cross-platform default connector.
WebSocketChannel connectWebSocketChannel(
  Uri uri,
  Map<String, String> headers,
) => headers.isEmpty
    ? WebSocketChannel.connect(uri)
    : IOWebSocketChannel.connect(uri, headers: headers);
