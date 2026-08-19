// RealtimeService: opens WebSocket (web_socket_channel) and SSE (a
// streaming Dio GET, parsed by SseParser) connections and returns a
// RealtimeConnection session-log stream, consumed by RealtimeBloc. The
// WebSocket factory is injectable (webSocketFactory) so teardown is
// unit-testable with a fake channel; applyConfig mirrors
// NetworkService.applyConfig (timeouts mutate BaseOptions in place BEFORE
// the adapter early-return; the adapter is rebuilt only on an
// adapter-relevant config change). WebSocket connects receive the
// last-applied NetworkConfig so wss:// honors verify-SSL/proxy/mTLS/
// connect-timeout like https:// does — seeded from the config the injected
// Dio was built with (buildSseDio records it), since DI constructs the Dio
// and the settings listener only fires on changes. SSE surfaces a non-2xx
// connect as an `HTTP <code>` error frame instead of silently streaming
// the error body, and renders a binary WS frame as a
// `[binary frame · N bytes]` placeholder. A WS close surfaces the
// channel's closeCode/closeReason as `Disconnected (<code>): <reason>` —
// ERROR direction for abnormal codes (anything but 1000/1005) so the log
// colors the drop as a failure. Text frames (WS and SSE alike) over
// kRealtimeMaxFrameTextChars are truncated with a size marker so one huge
// frame can't pin memory (the bloc's frame cap bounds count, not bytes).

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:getman/core/network/dio_adapter_config.dart';
import 'package:getman/core/network/network_config.dart';
import 'package:getman/core/network/realtime_frame.dart';
import 'package:getman/core/network/sse_parser.dart';
import 'package:getman/core/network/web_socket_connector.dart';
import 'package:getman/core/utils/byte_format.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Hard cap on a single session-log frame's text, in UTF-16 code units.
/// RealtimeBloc caps the log's frame COUNT, not its bytes — one 200 MB text
/// frame would otherwise sit in bloc state verbatim, pinning memory and
/// janking every log rebuild. 256 KiB keeps any payload a human would read
/// intact while bounding the worst case. (SseParser's own
/// [kSseMaxBufferedChars] caps multi-chunk events, but a complete event
/// arriving in a single chunk dispatches uncapped — this is the display
/// bound for both transports.)
const int kRealtimeMaxFrameTextChars = 256 * 1024;

/// Truncates frame [text] over [kRealtimeMaxFrameTextChars] to a prefix plus
/// an `… [+N truncated]` marker; text at or under the cap passes unchanged.
/// The omitted count is UTF-16 code units humanized as bytes — same display
/// convention as SseParser's overflow marker.
String _truncateFrameText(String text) {
  if (text.length <= kRealtimeMaxFrameTextChars) return text;
  var end = kRealtimeMaxFrameTextChars;
  // Don't split a surrogate pair at the cut point (0xD800–0xDBFF is a high
  // surrogate — its low half would render as U+FFFD).
  if ((text.codeUnitAt(end - 1) & 0xFC00) == 0xD800) end -= 1;
  return '${text.substring(0, end)}… '
      '[+${formatBytes(text.length - end)} truncated]';
}

/// A live realtime connection (WebSocket or SSE). [frames] is the session log
/// stream; [send] is a no-op for read-only SSE. Always [close] to release it.
abstract class RealtimeConnection {
  Stream<RealtimeFrame> get frames;
  void send(String message);
  Future<void> close();
}

/// Opens WebSocket / SSE connections.
///
/// WebSocket uses `web_socket_channel`. On dart:io platforms custom request
/// headers ride the handshake (see `web_socket_connector_io.dart`); the
/// browser WebSocket API cannot set them, so auth on web must use a query
/// param or subprotocol — documented limitation. SSE streams a Dio response;
/// on web the XHR adapter may buffer rather than stream incrementally.
class RealtimeService {
  RealtimeService({
    Dio? dio,
    WebSocketChannel Function(
      Uri uri,
      Map<String, String> headers,
      NetworkConfig config,
    )?
    webSocketFactory,
  }) : _dio = dio ?? buildSseDio(NetworkConfig.defaults),
       _webSocketFactory = webSocketFactory ?? connectWebSocketChannel {
    _wsConnectConfig = _configUsedToBuild[_dio] ?? NetworkConfig.defaults;
  }
  final Dio _dio;
  final WebSocketChannel Function(
    Uri uri,
    Map<String, String> headers,
    NetworkConfig config,
  )
  _webSocketFactory;

  /// Adapter-relevant config of the last [applyConfig] that rebuilt the
  /// adapter; null until the first swap.
  NetworkConfig? _adapterConfig;

  /// The config every [connectWebSocket] handshake honors (verify-SSL /
  /// proxy / mTLS / connect timeout on dart:io platforms). Updated by EVERY
  /// [applyConfig] — before its adapter early-return, so a timeout-only edit
  /// still lands here.
  NetworkConfig _wsConnectConfig = NetworkConfig.defaults;

  /// Config each [buildSseDio] Dio was built with. DI constructs the Dio (not
  /// this service) and NetworkSettingsListener only fires on CHANGES, so
  /// without this a fresh launch would open WebSockets with
  /// [NetworkConfig.defaults] until the first network-settings edit — the
  /// constructor recovers the boot config from the injected Dio instead.
  static final Expando<NetworkConfig> _configUsedToBuild =
      Expando<NetworkConfig>();

  // SSE is a long-lived stream — no receive timeout, or it would be killed.
  // Otherwise wired like NetworkService.buildDio: the same verify-SSL/proxy/
  // mTLS adapter and (optional) cookie jar interceptor, so a self-signed dev
  // server or session-cookie auth that works for normal requests also works
  // for SSE (H2).
  static Dio buildSseDio(
    NetworkConfig config, [
    Interceptor? cookieInterceptor,
  ]) {
    final dio = Dio(
      BaseOptions(
        // Direct mapping like NetworkService.buildDio — 0 means disabled via
        // dio's own `> Duration.zero` gate.
        connectTimeout: Duration(milliseconds: config.connectTimeoutMs),
        validateStatus: (_) => true,
        responseType: ResponseType.stream,
      ),
    );
    configureHttpAdapter(
      dio,
      verifySsl: config.verifySsl,
      proxyUrl: config.proxyUrl,
      clientCertPath: config.clientCertPath,
      clientKeyPath: config.clientKeyPath,
      clientCertPassphrase: config.clientCertPassphrase,
    );
    if (cookieInterceptor != null) dio.interceptors.add(cookieInterceptor);
    _configUsedToBuild[dio] = config;
    return dio;
  }

  /// Re-applies [config] to the live SSE client without rebuilding it —
  /// mirrors NetworkService.applyConfig: the connect timeout mutates
  /// [BaseOptions] in place (receive stays unlimited — SSE is a long-lived
  /// stream) and the WS connect config updates, both BEFORE the adapter
  /// early-return; only an adapter-relevant change (SSL/proxy/client cert)
  /// swaps the adapter. Interceptors (e.g. the cookie jar) are preserved.
  void applyConfig(NetworkConfig config) {
    _wsConnectConfig = config;
    _dio.options.connectTimeout = Duration(
      milliseconds: config.connectTimeoutMs,
    );
    // Rebuilding the adapter drops its socket pool, so skip the swap when no
    // adapter-relevant field changed (mirrors NetworkService.applyConfig).
    if (_adapterConfig != null && _adapterConfig!.sameAdapterConfig(config)) {
      return;
    }
    _adapterConfig = config;
    final old = _dio.httpClientAdapter;
    configureHttpAdapter(
      _dio,
      verifySsl: config.verifySsl,
      proxyUrl: config.proxyUrl,
      clientCertPath: config.clientCertPath,
      clientKeyPath: config.clientKeyPath,
      clientCertPassphrase: config.clientCertPassphrase,
    );
    // Web stub leaves the adapter untouched (no-op); only close on a real swap.
    if (!identical(_dio.httpClientAdapter, old)) old.close();
  }

  RealtimeConnection connectWebSocket(
    String url, {
    Map<String, String> headers = const {},
  }) => _WebSocketConnection(
    _webSocketFactory(Uri.parse(url), headers, _wsConnectConfig),
    url,
  );

  RealtimeConnection connectSse(
    String url, {
    Map<String, String> headers = const {},
  }) => _SseConnection(_dio, url, headers);
}

class _WebSocketConnection implements RealtimeConnection {
  _WebSocketConnection(this._channel, String url) {
    // Deferred: inside the constructor the broadcast controller has no
    // listener yet (the bloc subscribes right after this returns) and
    // broadcast streams don't buffer — a synchronous emit is silently lost.
    scheduleMicrotask(() => _emit(RealtimeFrame.open('Connecting to $url')));
    _sub = _channel.stream.listen(
      (msg) => _emit(RealtimeFrame.incoming(_describe(msg))),
      onError: (Object e) => _emit(RealtimeFrame.error(e.toString())),
      onDone: () => _emit(_closeFrame()),
    );
  }
  final WebSocketChannel _channel;
  final _controller = StreamController<RealtimeFrame>.broadcast();
  StreamSubscription<dynamic>? _sub;

  void _emit(RealtimeFrame f) {
    if (!_controller.isClosed) _controller.add(f);
  }

  /// Builds the terminal frame from the channel's close code/reason, so a
  /// 1008 "auth token expired" reads differently from a clean 1000. Abnormal
  /// codes (anything but 1000 normal-closure / 1005 no-status) use the ERROR
  /// direction so the log colors the drop as a failure — RealtimeBloc derives
  /// `connected: false` from close and error frames alike.
  RealtimeFrame _closeFrame() {
    final code = _channel.closeCode;
    if (code == null) return RealtimeFrame.close();
    final reason = _channel.closeReason;
    final text = reason == null || reason.isEmpty
        ? 'Disconnected ($code)'
        : 'Disconnected ($code): $reason';
    final abnormal =
        code != ws_status.normalClosure && code != ws_status.noStatusReceived;
    return abnormal ? RealtimeFrame.error(text) : RealtimeFrame.close(text);
  }

  // Binary frames (protobuf, deflate, ...) arrive as a byte list; rendering
  // `msg.toString()` dumps `[72, 101, ...]` — megabytes of noise for a large
  // frame. Show a compact placeholder instead. Text frames get the shared
  // display cap — the frame-count cap in the bloc doesn't bound bytes.
  static String _describe(dynamic msg) => msg is List<int>
      ? '[binary frame · ${msg.length} bytes]'
      : _truncateFrameText(msg.toString());

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
    // Deferred for the same reason as _WebSocketConnection's open frame.
    scheduleMicrotask(() => _emit(RealtimeFrame.open('Streaming $url')));
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
            // The SSE spec fails the connection on a non-2xx status — without
            // this, a 404/401/500 streams whatever body arrives (or nothing)
            // and looks like a clean connect/disconnect (H1). The status is
            // read off `ResponseBody` (not the outer `Response`, which for a
            // `ResponseType.stream` request only mirrors it after dio's own
            // internal transform) so it is reliable for both the real client
            // and hand-built test fakes.
            final status = body.statusCode;
            if (status < 200 || status >= 300) {
              final reason = body.statusMessage ?? response.statusMessage;
              _emit(
                RealtimeFrame.error(
                  reason == null || reason.isEmpty
                      ? 'HTTP $status'
                      : 'HTTP $status $reason',
                ),
              );
              _emit(RealtimeFrame.close());
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
            // Events get the shared display cap: SseParser's own buffer cap
            // only bounds text still awaiting a terminator — a complete
            // event arriving in one chunk dispatches at full size.
            _sub = decoded.listen(
              (text) {
                for (final event in _parser.addChunk(text)) {
                  _emit(RealtimeFrame.incoming(_truncateFrameText(event)));
                }
              },
              onError: (Object e) => _emit(RealtimeFrame.error(e.toString())),
              onDone: () {
                for (final event in _parser.flush()) {
                  _emit(RealtimeFrame.incoming(_truncateFrameText(event)));
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
