// Platform-selected WebSocket connector: on dart:io platforms custom
// request headers ride the handshake and the NetworkConfig's verify-SSL /
// proxy / mTLS / connect-timeout settings are honored via a custom
// HttpClient (IOWebSocketChannel); the web stub ignores both (the browser
// WebSocket API cannot set headers and the browser owns TLS — documented
// limitation). Conditional export, same pattern as git_service.dart.
export 'web_socket_connector_stub.dart'
    if (dart.library.io) 'web_socket_connector_io.dart'
    show connectWebSocketChannel;
