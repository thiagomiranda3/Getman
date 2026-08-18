import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/content_encoding.dart';
import 'package:getman/core/network/network_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.bytes, required this.headers, this.status = 200});
  final List<int> bytes;
  final Map<String, List<String>> headers;
  final int status;

  /// True once the request's CancelToken was cancelled (the declared-length
  /// early-out cancels to drop the connection; a bodyless response must not).
  bool sawCancel = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    unawaited(cancelFuture?.whenComplete(() => sawCancel = true));
    return ResponseBody.fromBytes(bytes, status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

typedef _Harness = ({NetworkService svc, _FakeAdapter adapter});

_Harness _harnessReturning(
  List<int> bytes,
  Map<String, List<String>> headers, {
  int status = 200,
  int maxResponseBytes = 50 * 1024 * 1024,
}) {
  final adapter = _FakeAdapter(bytes: bytes, headers: headers, status: status);
  final dio = Dio(BaseOptions(validateStatus: (_) => true))
    ..httpClientAdapter = adapter;
  return (
    svc: NetworkService(dio: dio, maxResponseBytes: maxResponseBytes),
    adapter: adapter,
  );
}

NetworkService serviceReturning(
  List<int> bytes,
  Map<String, List<String>> headers, {
  int maxResponseBytes = 50 * 1024 * 1024,
}) => _harnessReturning(bytes, headers, maxResponseBytes: maxResponseBytes).svc;

/// Lets the CancelToken's whenCancel microtask (the adapter's spy) run.
Future<void> _pumpCancelSpy() => Future<void>.delayed(Duration.zero);

void main() {
  test('textual response decodes to body, no bodyBytes', () async {
    final svc = serviceReturning(
      utf8.encode('{"a":1}'),
      {
        'content-type': ['application/json'],
      },
    );
    final r = await svc.request(url: 'https://x/y', method: 'GET');
    expect(r.body, '{"a":1}');
    expect(r.bodyBytes, isNull);
  });

  test('image response keeps bytes + placeholder body', () async {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    final svc = serviceReturning(png, {
      'content-type': ['image/png'],
    });
    final r = await svc.request(url: 'https://x/a.png', method: 'GET');
    expect(r.bodyBytes, png);
    expect(r.body, contains('image/png'));
  });

  test('content-length over cap → no bytes, too-large placeholder', () async {
    final svc = serviceReturning(
      List<int>.filled(100, 0),
      {
        'content-type': ['video/mp4'],
        'content-length': ['999999999'],
      },
      maxResponseBytes: 10,
    );
    final r = await svc.request(url: 'https://x/big.mp4', method: 'GET');
    expect(r.bodyBytes, isNull);
    expect(r.body.toLowerCase(), contains('too large'));
  });

  test(
    'stream exceeding cap (no content-length) → too-large placeholder',
    () async {
      final svc = serviceReturning(
        List<int>.filled(5000, 7),
        {
          'content-type': ['video/mp4'],
        },
        maxResponseBytes: 100,
      );
      final r = await svc.request(url: 'https://x/big.mp4', method: 'GET');
      expect(r.bodyBytes, isNull);
      expect(r.body.toLowerCase(), contains('too large'));
    },
  );

  test('empty body → empty string, no bytes', () async {
    final svc = serviceReturning(const [], {
      'content-type': ['image/png'],
    });
    final r = await svc.request(url: 'https://x/a.png', method: 'GET');
    expect(r.body, '');
    expect(r.bodyBytes, isNull);
  });

  group('bodyless responses ignore the declared Content-Length (F1)', () {
    // RFC 7230 §3.3.3: HEAD / 1xx / 204 / 304 responses carry no body, but
    // their Content-Length may echo the representation size — the too-large
    // early-out (placeholder + connection cancel) must not fire for them.
    const sixGb = '6442450944';

    test('HEAD with a 6 GB Content-Length → empty body, no placeholder, '
        'no cancel', () async {
      final h = _harnessReturning(
        const [],
        {
          'content-type': ['application/octet-stream'],
          'content-length': [sixGb],
        },
        maxResponseBytes: 10,
      );
      final r = await h.svc.request(
        url: 'https://mirror/big.iso',
        method: 'HEAD',
      );
      await _pumpCancelSpy();
      expect(r.statusCode, 200);
      expect(r.body, '');
      expect(r.bodyBytes, isNull);
      expect(h.adapter.sawCancel, isFalse);
    });

    test('control: GET with the same declared length still placeholders '
        'and cancels (proves the cancel spy works)', () async {
      final h = _harnessReturning(
        List<int>.filled(100, 0),
        {
          'content-type': ['application/octet-stream'],
          'content-length': [sixGb],
        },
        maxResponseBytes: 10,
      );
      final r = await h.svc.request(
        url: 'https://mirror/big.iso',
        method: 'GET',
      );
      await _pumpCancelSpy();
      expect(r.body.toLowerCase(), contains('too large'));
      expect(h.adapter.sawCancel, isTrue);
    });

    test('304 echoing the representation length → empty body, no placeholder, '
        'no cancel', () async {
      final h = _harnessReturning(
        const [],
        {
          'content-type': ['application/json'],
          'content-length': [sixGb],
        },
        status: 304,
        maxResponseBytes: 10,
      );
      final r = await h.svc.request(url: 'https://x/cached', method: 'GET');
      await _pumpCancelSpy();
      expect(r.statusCode, 304);
      expect(r.body, '');
      expect(h.adapter.sawCancel, isFalse);
    });

    test('204 with a stray over-cap Content-Length → empty body, '
        'no placeholder', () async {
      final h = _harnessReturning(
        const [],
        {
          'content-length': [sixGb],
        },
        status: 204,
        maxResponseBytes: 10,
      );
      final r = await h.svc.request(url: 'https://x/delete', method: 'DELETE');
      await _pumpCancelSpy();
      expect(r.statusCode, 204);
      expect(r.body, '');
      expect(h.adapter.sawCancel, isFalse);
    });
  });

  group('response Content-Encoding handling (F2)', () {
    test('deflate (zlib-wrapped) body decodes to text', () async {
      final svc = serviceReturning(zlib.encode(utf8.encode('{"ok":true}')), {
        'content-type': ['application/json'],
        'content-encoding': ['deflate'],
      });
      final r = await svc.request(url: 'https://x/y', method: 'GET');
      expect(r.body, '{"ok":true}');
      expect(r.bodyBytes, isNull);
    });

    test('raw-deflate (RFC 1951, no zlib wrapper) decodes via the '
        'fallback', () async {
      final raw = ZLibEncoder(raw: true).convert(utf8.encode('raw deflate'));
      final svc = serviceReturning(raw, {
        'content-type': ['text/plain'],
        'content-encoding': ['deflate'],
      });
      final r = await svc.request(url: 'https://x/y', method: 'GET');
      expect(r.body, 'raw deflate');
    });

    test('br body → unsupported placeholder, not mojibake', () async {
      // Arbitrary high bytes standing in for a brotli stream — the point is
      // they must never reach the utf8 decoder.
      final svc = serviceReturning(
        [0x8B, 0x03, 0x80, 0xC3, 0xA9, 0xFF],
        {
          'content-type': ['application/json'],
          'content-encoding': ['br'],
        },
      );
      final r = await svc.request(url: 'https://x/y', method: 'GET');
      expect(r.body, contains('content-encoding: br'));
      expect(r.body, contains('unsupported'));
      expect(r.body, contains('Accept-Encoding'));
      expect(r.bodyBytes, isNull);
      expect(r.body, isNot(contains('�')));
    });

    test('zstd body → unsupported placeholder too', () async {
      final svc = serviceReturning(
        [0x28, 0xB5, 0x2F, 0xFD, 1, 2, 3],
        {
          'content-type': ['text/html'],
          'content-encoding': ['zstd'],
        },
      );
      final r = await svc.request(url: 'https://x/y', method: 'GET');
      expect(r.body, contains('content-encoding: zstd'));
      expect(r.body, contains('unsupported'));
    });

    test('a gzip-TYPED payload (application/gzip .tar.gz with '
        'Content-Encoding: gzip) is never attempt-decoded a second time — '
        'the user gets the .gz bytes, not the silently-unwrapped inner '
        'archive', () async {
      // These bytes ARE the payload: the transfer encoding was already
      // removed by the platform; a second successful decode would corrupt
      // the download.
      final gzPayload = gzip.encode(utf8.encode('inner tar bytes'));
      final svc = serviceReturning(gzPayload, {
        'content-type': ['application/gzip'],
        'content-encoding': ['gzip'],
      });
      final r = await svc.request(url: 'https://x/f.tar.gz', method: 'GET');
      expect(r.bodyBytes, isNotNull);
      expect(r.bodyBytes, equals(gzPayload));
    });

    test('the native seam reports it does NOT decompress transparently — '
        'the br/zstd unsupported placeholder stays reachable on desktop '
        '(the web stub flips this so browsers keep their pre-decoded '
        'bytes)', () {
      expect(platformDecompressesTransparently, isFalse);
    });

    test("uppercase 'GZIP' (which dart:io's exact-match auto-decompress "
        'skips) is gzip-decoded case-insensitively', () async {
      final svc = serviceReturning(gzip.encode(utf8.encode('hello gzip')), {
        'content-type': ['text/plain'],
        'content-encoding': ['GZIP'],
      });
      final r = await svc.request(url: 'https://x/y', method: 'GET');
      expect(r.body, 'hello gzip');
      expect(r.bodyBytes, isNull);
    });

    test("lowercase 'gzip' with an already-decompressed body (the dart:io "
        'auto-decompress case) stays as-is — no double decode', () async {
      final svc = serviceReturning(utf8.encode('already plain'), {
        'content-type': ['text/plain'],
        'content-encoding': ['gzip'],
      });
      final r = await svc.request(url: 'https://x/y', method: 'GET');
      expect(r.body, 'already plain');
    });

    test('gzip body whose DECOMPRESSED size busts the cap → too-large '
        'placeholder (zip-bomb guard)', () async {
      final compressed = gzip.encode(List<int>.filled(5000, 0x61));
      expect(compressed.length, lessThan(200)); // wire size passes the cap
      final svc = serviceReturning(
        compressed,
        {
          'content-type': ['text/plain'],
          'content-encoding': ['gzip'],
        },
        maxResponseBytes: 200,
      );
      final r = await svc.request(url: 'https://x/y', method: 'GET');
      expect(r.body.toLowerCase(), contains('too large'));
      expect(r.bodyBytes, isNull);
    });

    test('an empty body with content-encoding: br (HEAD/304 echo) is NOT '
        'placeholdered', () async {
      final h = _harnessReturning(const [], {
        'content-type': ['application/json'],
        'content-encoding': ['br'],
      });
      final r = await h.svc.request(url: 'https://x/y', method: 'HEAD');
      expect(r.body, '');
    });
  });

  group('charset decoding (F3: single-byte Latin family → latin1)', () {
    // 0xE9 is "é" in ISO-8859-1/-15 and windows-1252, but an invalid lone
    // UTF-8 byte — the UTF-8 branch would render U+FFFD mojibake.
    test('iso-8859-1 charset decodes with latin1, not utf8', () async {
      final svc = serviceReturning(
        [0xE9],
        {
          'content-type': ['text/plain; charset=iso-8859-1'],
        },
      );
      final r = await svc.request(url: 'https://x/y', method: 'GET');
      expect(r.body, 'é');
    });

    test('windows-1252 charset decodes é via latin1', () async {
      final svc = serviceReturning(
        [0xE9],
        {
          'content-type': ['text/plain; charset=windows-1252'],
        },
      );
      final r = await svc.request(url: 'https://x/y', method: 'GET');
      expect(r.body, 'é');
    });

    test('cp1252 charset decodes é via latin1', () async {
      final svc = serviceReturning(
        [0xE9],
        {
          'content-type': ['text/plain; charset=cp1252'],
        },
      );
      final r = await svc.request(url: 'https://x/y', method: 'GET');
      expect(r.body, 'é');
    });

    test('iso-8859-15 charset decodes é via latin1', () async {
      final svc = serviceReturning(
        [0xE9],
        {
          'content-type': ['text/plain; charset=iso-8859-15'],
        },
      );
      final r = await svc.request(url: 'https://x/y', method: 'GET');
      expect(r.body, 'é');
    });
  });

  test('default (no charset) decodes as utf8', () async {
    final svc = serviceReturning(
      utf8.encode('café'),
      {
        'content-type': ['text/plain'],
      },
    );
    final r = await svc.request(url: 'https://x/y', method: 'GET');
    expect(r.body, 'café');
  });
}
