// dart:io WebSocket connector: the handshake rides a custom HttpClient
// built from the last-applied NetworkConfig (buildConfiguredHttpClient in
// dio_adapter_config_io.dart), so wss:// honors VERIFY SSL off, the proxy,
// the client certificate (mTLS), and the connect timeout exactly like
// https:// requests do — previously the default HttpClient made a
// self-signed dev server work over HTTPS but fail over WSS. Custom request
// headers ride the same upgrade request (the HEADERS tab's Authorization
// etc. reaches the server on desktop instead of being silently dropped).
// Selected by web_socket_connector.dart's conditional export.
import 'package:getman/core/network/dio_adapter_config_io.dart';
import 'package:getman/core/network/network_config.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a WebSocket, sending [headers] with the HTTP upgrade request and
/// honoring [config]'s verify-SSL / proxy / mTLS / connect-timeout settings
/// (connectTimeoutMs <= 0 means no timeout, matching the Dio convention).
WebSocketChannel connectWebSocketChannel(
  Uri uri,
  Map<String, String> headers,
  NetworkConfig config,
) {
  final connectTimeout = config.connectTimeoutMs > 0
      ? Duration(milliseconds: config.connectTimeoutMs)
      : null;
  return IOWebSocketChannel.connect(
    uri,
    headers: headers.isEmpty ? null : headers,
    connectTimeout: connectTimeout,
    customClient: buildConfiguredHttpClient(
      verifySsl: config.verifySsl,
      proxyUrl: config.proxyUrl,
      clientCertPath: config.clientCertPath,
      clientKeyPath: config.clientKeyPath,
      clientCertPassphrase: config.clientCertPassphrase,
      connectionTimeout: connectTimeout,
    ),
  );
}
