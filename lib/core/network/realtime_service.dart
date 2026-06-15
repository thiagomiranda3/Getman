import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/sse_parser.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A live realtime connection (WebSocket or SSE). [frames] is the session log
/// stream; [send] is a no-op for read-only SSE. Always [close] to release it.
abstract class RealtimeConnection {
  Stream<RealtimeFrame> get frames;
  void send(String message);
  Future<void> close();
}

/// Opens WebSocket / SSE connections.
///
/// WebSocket uses `web_socket_channel` (cross-platform). Custom request headers
/// are not supported on the browser WebSocket API, so auth on web must use a
/// query param or subprotocol — documented limitation. SSE streams a Dio
/// response; on web the XHR adapter may buffer rather than stream
/// incrementally.
class RealtimeService {
  RealtimeService({
    Dio? dio,
    WebSocketChannel Function(Uri uri)? webSocketFactory,
  }) : _dio = dio ?? _buildSseDio(),
       _webSocketFactory = webSocketFactory ?? WebSocketChannel.connect;
  final Dio _dio;
  final WebSocketChannel Function(Uri uri) _webSocketFactory;

  // SSE is a long-lived stream — no receive timeout, or it would be killed.
  static Dio _buildSseDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      validateStatus: (_) => true,
      responseType: ResponseType.stream,
    ),
  );

  RealtimeConnection connectWebSocket(String url) =>
      _WebSocketConnection(_webSocketFactory(Uri.parse(url)), url);

  RealtimeConnection connectSse(
    String url, {
    Map<String, String> headers = const {},
  }) => _SseConnection(_dio, url, headers);
}

class _WebSocketConnection implements RealtimeConnection {
  _WebSocketConnection(this._channel, String url) {
    _emit(RealtimeFrame.open('Connecting to $url'));
    _sub = _channel.stream.listen(
      (msg) => _emit(RealtimeFrame.incoming(msg.toString())),
      onError: (Object e) => _emit(RealtimeFrame.error(e.toString())),
      onDone: () => _emit(RealtimeFrame.close()),
    );
  }
  final WebSocketChannel _channel;
  final _controller = StreamController<RealtimeFrame>.broadcast();
  StreamSubscription<dynamic>? _sub;

  void _emit(RealtimeFrame f) {
    if (!_controller.isClosed) _controller.add(f);
  }

  @override
  Stream<RealtimeFrame> get frames => _controller.stream;

  @override
  void send(String message) {
    _channel.sink.add(message);
    _emit(RealtimeFrame.outgoing(message));
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _channel.sink.close();
    if (!_controller.isClosed) await _controller.close();
  }
}

class _SseConnection implements RealtimeConnection {
  _SseConnection(Dio dio, String url, Map<String, String> headers) {
    _emit(RealtimeFrame.open('Streaming $url'));
    unawaited(
      dio
          .get<ResponseBody>(
            url,
            options: Options(
              responseType: ResponseType.stream,
              headers: {...headers, 'Accept': 'text/event-stream'},
            ),
            cancelToken: _cancel,
          )
          .then((response) {
            final body = response.data;
            if (body == null) {
              _emit(RealtimeFrame.error('No response body'));
              return;
            }
            // Decode through a single streaming UTF-8 decoder so a multi-byte
            // code point split across two network chunks buffers across the
            // boundary instead of being corrupted into U+FFFD on each side.
            // `bind` accepts the covariant Stream<Uint8List>; `.transform`
            // would not type-check.
            final decoded = const Utf8Decoder(
              allowMalformed: true,
            ).bind(body.stream);
            _sub = decoded.listen(
              (text) {
                for (final event in _parser.addChunk(text)) {
                  _emit(RealtimeFrame.incoming(event));
                }
              },
              onError: (Object e) => _emit(RealtimeFrame.error(e.toString())),
              onDone: () {
                for (final event in _parser.flush()) {
                  _emit(RealtimeFrame.incoming(event));
                }
                _emit(RealtimeFrame.close());
              },
            );
          })
          .catchError((Object e) {
            if (e is DioException && CancelToken.isCancel(e)) return;
            _emit(RealtimeFrame.error(e.toString()));
          }),
    );
  }
  final _controller = StreamController<RealtimeFrame>.broadcast();
  final SseParser _parser = SseParser();
  final CancelToken _cancel = CancelToken();
  StreamSubscription<dynamic>? _sub;

  void _emit(RealtimeFrame f) {
    if (!_controller.isClosed) _controller.add(f);
  }

  @override
  Stream<RealtimeFrame> get frames => _controller.stream;

  @override
  void send(String message) {
    /* SSE is read-only */
  }

  @override
  Future<void> close() async {
    if (!_cancel.isCancelled) _cancel.cancel();
    await _sub?.cancel();
    if (!_controller.isClosed) await _controller.close();
  }
}
