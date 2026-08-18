// Platform-selected WebSocket connector: on dart:io platforms custom
// request headers ride the handshake (IOWebSocketChannel); the web stub
// ignores them (the browser WebSocket API cannot set headers — documented
// limitation). Conditional export, same pattern as git_service.dart.
export 'web_socket_connector_stub.dart'
    if (dart.library.io) 'web_socket_connector_io.dart'
    show connectWebSocketChannel;
