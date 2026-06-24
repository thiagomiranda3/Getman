# Rich Response Visualizers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render non-text API responses (image / video / audio / pdf / csv / html / binary) usefully in the response panel instead of dumping corrupted text.

**Architecture:** Capture response bodies as **bytes** (streamed, capped). A pure-Dart classifier maps content-type/URL/magic-bytes to a `ResponseMediaKind`. `ResponseBodyView` dispatches: textual → the existing PRETTY/RAW/TREE path (untouched); media kinds → a per-kind leaf viewer. Media bytes are **live-only** (never persisted) — restored/time-travel responses show a "not stored" placeholder.

**Tech Stack:** Flutter + dio (streaming capture), media_kit (video/audio), pdfx (pdf), csv (parse), built-in `Image.memory` (image), `url_launcher` + `path_provider` (html open-in-browser, media temp files).

## Global Constraints

- Flutter is invoked as `fvm flutter …` / `fvm dart …` — never bare `flutter`.
- Done-bar (run after every task): `fvm flutter analyze` (0 issues) AND `fvm dart run custom_lint` (0 issues) AND `fvm dart run bloc_tools:bloc lint lib` (0 issues) AND `fvm dart format lib test` clean AND `fvm flutter test` 100% green.
- `analyze` can false-pass on generic-variance issues — `fvm flutter test` (CFE) is the real compile check.
- All imports are `package:getman/...` (no relative imports). Imports ordered (`directives_ordering`).
- No hardcoded sizes/colors/radii/weights/paddings in widgets — read `context.appLayout` / `appPalette` / `appShape` / `appTypography` / `appDecoration`. `Colors.black/white/red` are banned outside `lib/core/theme/` (custom_lint enforces).
- Snackbars go through `showAppSnackBar(context, msg)` — never inline `SnackBar`.
- Debug logs: non-bloc layers use `debugPrint`; never `print`.
- **No Hive change.** `bodyBytes` is never persisted; do NOT touch any `@HiveType`/`@HiveField` or run `build_runner`.
- **Media bytes are live-only** — keep them in memory only; persistence stores the placeholder text `body` exactly as today.
- Adding a dependency: run `fvm flutter pub add <pkg>` then `fvm flutter pub get`; if it forces `analyzer` past 8.4 or breaks `custom_lint`/`bloc_lint`, STOP and report (the analysis stack is pinned to analyzer 8.4).
- Spec: `docs/superpowers/specs/2026-06-24-rich-response-visualizers-design.md`.

---

# Phase 1 — Foundation (no new deps)

### Task 1: Content-type classifier (pure Dart)

**Files:**
- Create: `lib/core/utils/response_media.dart`
- Test: `test/core/utils/response_media_test.dart`

**Interfaces:**
- Produces:
  - `enum ResponseMediaKind { textual, image, pdf, html, csv, video, audio, binary }`
  - `String? contentTypeOf(Map<String, String> headers)` — case-insensitive `content-type`, params stripped, lower-cased.
  - `ResponseMediaKind classifyResponseMedia({String? contentType, String? url, Uint8List? sniffBytes})`
  - `String mediaExtension({String? contentType, String? url})` — a file extension (no dot) for save/temp-file naming; defaults `'bin'`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/response_media.dart';

void main() {
  group('contentTypeOf', () {
    test('reads case-insensitively and strips params', () {
      expect(
        contentTypeOf({'Content-Type': 'application/JSON; charset=utf-8'}),
        'application/json',
      );
    });
    test('returns null when absent', () {
      expect(contentTypeOf({'x': 'y'}), isNull);
    });
  });

  group('classifyResponseMedia by content-type', () {
    test('json/text/xml → textual', () {
      expect(classifyResponseMedia(contentType: 'application/json'),
          ResponseMediaKind.textual);
      expect(classifyResponseMedia(contentType: 'text/plain'),
          ResponseMediaKind.textual);
      expect(classifyResponseMedia(contentType: 'application/xml'),
          ResponseMediaKind.textual);
    });
    test('image/video/audio/pdf/csv/html', () {
      expect(classifyResponseMedia(contentType: 'image/png'),
          ResponseMediaKind.image);
      expect(classifyResponseMedia(contentType: 'video/mp4'),
          ResponseMediaKind.video);
      expect(classifyResponseMedia(contentType: 'audio/mpeg'),
          ResponseMediaKind.audio);
      expect(classifyResponseMedia(contentType: 'application/pdf'),
          ResponseMediaKind.pdf);
      expect(classifyResponseMedia(contentType: 'text/csv'),
          ResponseMediaKind.csv);
      expect(classifyResponseMedia(contentType: 'text/html'),
          ResponseMediaKind.html);
    });
    test('known binary type → binary', () {
      expect(classifyResponseMedia(contentType: 'application/zip'),
          ResponseMediaKind.binary);
    });
  });

  group('classifyResponseMedia fallbacks', () {
    test('octet-stream with no hints → textual (do not corrupt JSON)', () {
      expect(classifyResponseMedia(contentType: 'application/octet-stream'),
          ResponseMediaKind.textual);
    });
    test('octet-stream falls through to URL extension', () {
      expect(
        classifyResponseMedia(
            contentType: 'application/octet-stream', url: 'https://x/y.mp4'),
        ResponseMediaKind.video,
      );
    });
    test('no content-type → URL extension', () {
      expect(classifyResponseMedia(url: 'https://x/a.png'),
          ResponseMediaKind.image);
    });
    test('magic bytes detect PDF / PNG / ZIP when no other hint', () {
      expect(
        classifyResponseMedia(
            sniffBytes: Uint8List.fromList('%PDF-1.7'.codeUnits)),
        ResponseMediaKind.pdf,
      );
      expect(
        classifyResponseMedia(
            sniffBytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])),
        ResponseMediaKind.image,
      );
      expect(
        classifyResponseMedia(
            sniffBytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04])),
        ResponseMediaKind.binary,
      );
    });
    test('nothing matches → textual', () {
      expect(classifyResponseMedia(), ResponseMediaKind.textual);
    });
  });

  group('mediaExtension', () {
    test('from content-type', () {
      expect(mediaExtension(contentType: 'image/png'), 'png');
      expect(mediaExtension(contentType: 'video/mp4'), 'mp4');
    });
    test('from URL when content-type unknown', () {
      expect(mediaExtension(url: 'https://x/clip.webm'), 'webm');
    });
    test('defaults to bin', () {
      expect(mediaExtension(), 'bin');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/core/utils/response_media_test.dart`
Expected: FAIL — `response_media.dart` / symbols not defined.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/utils/response_media.dart
import 'dart:typed_data';

/// How a response body should be rendered. `textual` is the existing
/// JSON/text/xml path; the rest get a dedicated viewer.
enum ResponseMediaKind { textual, image, pdf, html, csv, video, audio, binary }

/// Case-insensitive `content-type` header value, parameters (`; charset=…`)
/// stripped, lower-cased. Null when absent.
String? contentTypeOf(Map<String, String> headers) {
  for (final e in headers.entries) {
    if (e.key.toLowerCase() == 'content-type') {
      return e.value.split(';').first.trim().toLowerCase();
    }
  }
  return null;
}

/// Classifies a response. Resolution order: content-type → URL extension →
/// magic bytes → default `textual`. The conservative default means an API that
/// returns JSON without a proper content-type is still treated as text (we only
/// switch to bytes when something positively indicates media/binary).
ResponseMediaKind classifyResponseMedia({
  String? contentType,
  String? url,
  Uint8List? sniffBytes,
}) {
  final ct = contentType?.split(';').first.trim().toLowerCase();
  final byCt = _kindFromContentType(ct);
  if (byCt != null) return byCt;

  final byExt = _kindFromExtension(_extensionOf(url));
  if (byExt != null) return byExt;

  final byMagic = _kindFromMagic(sniffBytes);
  if (byMagic != null) return byMagic;

  return ResponseMediaKind.textual;
}

/// A file extension (no leading dot) for save / temp-file naming.
String mediaExtension({String? contentType, String? url}) {
  final ct = contentType?.split(';').first.trim().toLowerCase();
  final fromCt = _extFromContentType[ct];
  if (fromCt != null) return fromCt;
  final fromUrl = _extensionOf(url);
  if (fromUrl != null && fromUrl.isNotEmpty) return fromUrl;
  return 'bin';
}

ResponseMediaKind? _kindFromContentType(String? ct) {
  if (ct == null || ct.isEmpty) return null;
  if (ct == 'application/octet-stream') return null; // ambiguous → fall through
  if (ct == 'text/csv' || ct == 'application/csv') return ResponseMediaKind.csv;
  if (ct == 'text/html' || ct == 'application/xhtml+xml') {
    return ResponseMediaKind.html;
  }
  if (ct == 'application/pdf') return ResponseMediaKind.pdf;
  if (ct.startsWith('image/')) return ResponseMediaKind.image;
  if (ct.startsWith('video/')) return ResponseMediaKind.video;
  if (ct.startsWith('audio/')) return ResponseMediaKind.audio;
  if (_textualContentTypes.contains(ct) ||
      ct.startsWith('text/') ||
      ct.endsWith('+json') ||
      ct.endsWith('+xml')) {
    return ResponseMediaKind.textual;
  }
  if (_binaryContentTypes.contains(ct)) return ResponseMediaKind.binary;
  return null;
}

ResponseMediaKind? _kindFromExtension(String? ext) {
  if (ext == null) return null;
  return _kindByExt[ext];
}

ResponseMediaKind? _kindFromMagic(Uint8List? b) {
  if (b == null || b.length < 4) return null;
  bool starts(List<int> sig) {
    if (b.length < sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[i] != sig[i]) return false;
    }
    return true;
  }

  if (starts('%PDF'.codeUnits)) return ResponseMediaKind.pdf;
  if (starts([0x89, 0x50, 0x4E, 0x47])) return ResponseMediaKind.image; // PNG
  if (starts([0xFF, 0xD8, 0xFF])) return ResponseMediaKind.image; // JPEG
  if (starts('GIF8'.codeUnits)) return ResponseMediaKind.image; // GIF
  if (starts([0x42, 0x4D])) return ResponseMediaKind.image; // BMP
  if (starts([0x50, 0x4B, 0x03, 0x04])) return ResponseMediaKind.binary; // ZIP
  if (starts([0x1F, 0x8B])) return ResponseMediaKind.binary; // GZIP
  return null;
}

String? _extensionOf(String? url) {
  if (url == null) return null;
  final noQuery = url.split('?').first.split('#').first;
  final lastSeg = noQuery.split('/').last;
  final dot = lastSeg.lastIndexOf('.');
  if (dot < 0 || dot == lastSeg.length - 1) return null;
  return lastSeg.substring(dot + 1).toLowerCase();
}

const _textualContentTypes = {
  'application/json',
  'application/xml',
  'application/javascript',
  'application/x-www-form-urlencoded',
};

const _binaryContentTypes = {
  'application/zip',
  'application/gzip',
  'application/x-gzip',
  'application/x-tar',
  'application/octet-stream-binary',
};

const _kindByExt = <String, ResponseMediaKind>{
  'png': ResponseMediaKind.image,
  'jpg': ResponseMediaKind.image,
  'jpeg': ResponseMediaKind.image,
  'gif': ResponseMediaKind.image,
  'webp': ResponseMediaKind.image,
  'bmp': ResponseMediaKind.image,
  'pdf': ResponseMediaKind.pdf,
  'csv': ResponseMediaKind.csv,
  'html': ResponseMediaKind.html,
  'htm': ResponseMediaKind.html,
  'mp4': ResponseMediaKind.video,
  'mkv': ResponseMediaKind.video,
  'webm': ResponseMediaKind.video,
  'mov': ResponseMediaKind.video,
  'avi': ResponseMediaKind.video,
  'm4v': ResponseMediaKind.video,
  'mp3': ResponseMediaKind.audio,
  'wav': ResponseMediaKind.audio,
  'ogg': ResponseMediaKind.audio,
  'flac': ResponseMediaKind.audio,
  'aac': ResponseMediaKind.audio,
  'm4a': ResponseMediaKind.audio,
  'zip': ResponseMediaKind.binary,
  'gz': ResponseMediaKind.binary,
  'tar': ResponseMediaKind.binary,
};

const _extFromContentType = <String, String>{
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/bmp': 'bmp',
  'application/pdf': 'pdf',
  'text/csv': 'csv',
  'application/csv': 'csv',
  'text/html': 'html',
  'video/mp4': 'mp4',
  'video/webm': 'webm',
  'video/quicktime': 'mov',
  'video/x-matroska': 'mkv',
  'audio/mpeg': 'mp3',
  'audio/wav': 'wav',
  'audio/ogg': 'ogg',
  'audio/flac': 'flac',
  'audio/aac': 'aac',
  'application/zip': 'zip',
  'application/gzip': 'gz',
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/core/utils/response_media_test.dart`
Expected: PASS.

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test
git add lib/core/utils/response_media.dart test/core/utils/response_media_test.dart
git commit -m "feat(response): add response-media content-type classifier"
```

---

### Task 2: `HttpResponseEntity.bodyBytes` + size helper

**Files:**
- Modify: `lib/core/network/http_response.dart`
- Modify: `lib/core/utils/byte_format.dart:7-15` (`responseSizeBytes`)
- Test: `test/core/network/http_response_test.dart` (create)
- Test: `test/core/utils/byte_format_test.dart` (create if absent; else append)

**Interfaces:**
- Consumes: nothing.
- Produces: `HttpResponseEntity({..., Uint8List? bodyBytes})` with `bodyBytes` getter; `copyWithBody` preserves `bodyBytes`. `responseSizeBytes` prefers `bodyBytes!.length` when present.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/network/http_response_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_response.dart';

void main() {
  HttpResponseEntity make({Uint8List? bytes}) => HttpResponseEntity(
        statusCode: 200,
        body: 'x',
        headers: const {},
        durationMs: 1,
        bodyBytes: bytes,
      );

  test('bodyBytes defaults to null', () {
    expect(
      const HttpResponseEntity(
        statusCode: 200,
        body: '',
        headers: {},
        durationMs: 0,
      ).bodyBytes,
      isNull,
    );
  });

  test('equality uses bodyBytes length, not identity', () {
    final a = make(bytes: Uint8List.fromList([1, 2, 3]));
    final b = make(bytes: Uint8List.fromList([9, 9, 9]));
    final c = make(bytes: Uint8List.fromList([1, 2]));
    expect(a, equals(b)); // same length → equal
    expect(a, isNot(equals(c))); // different length → not equal
  });

  test('copyWithBody preserves bodyBytes', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final r = make(bytes: bytes).copyWithBody('placeholder');
    expect(r.body, 'placeholder');
    expect(r.bodyBytes, bytes);
  });
}
```

```dart
// test/core/utils/byte_format_test.dart  (append if file exists)
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/byte_format.dart';

void main() {
  test('responseSizeBytes prefers bodyBytes length', () {
    final r = HttpResponseEntity(
      statusCode: 200,
      body: '[binary]',
      headers: const {},
      durationMs: 1,
      bodyBytes: Uint8List(1234),
    );
    expect(responseSizeBytes(r), 1234);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/core/network/http_response_test.dart test/core/utils/byte_format_test.dart`
Expected: FAIL — `bodyBytes` not defined.

- [ ] **Step 3: Implement**

Replace `lib/core/network/http_response.dart` with:

```dart
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

class HttpResponseEntity extends Equatable {
  const HttpResponseEntity({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.durationMs,
    this.bodyBytes,
  });
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final int durationMs;

  /// Raw bytes for a non-textual (media/binary) response. Held **in memory
  /// only** — never persisted to Hive — so it is null on a restored tab or an
  /// older time-travel history entry. Null for textual responses.
  final Uint8List? bodyBytes;

  /// Returns a copy with [body] replaced, keeping status/headers/duration/bytes
  /// — used when an over-limit text body is swapped for a placeholder before
  /// persisting. Media bytes ride along (they are dropped at the model layer).
  HttpResponseEntity copyWithBody(String body) => HttpResponseEntity(
        statusCode: statusCode,
        body: body,
        headers: headers,
        durationMs: durationMs,
        bodyBytes: bodyBytes,
      );

  // bodyBytes itself is excluded from props — a list compare on multi-MB
  // buffers every rebuild is unacceptable. Its length is a cheap discriminator.
  @override
  List<Object?> get props => [
        statusCode,
        body,
        headers,
        durationMs,
        bodyBytes?.length,
      ];
}
```

In `lib/core/utils/byte_format.dart`, change `responseSizeBytes` to prefer bytes:

```dart
int responseSizeBytes(HttpResponseEntity response) {
  final bytes = response.bodyBytes;
  if (bytes != null) return bytes.length;
  for (final e in response.headers.entries) {
    if (e.key.toLowerCase() == 'content-length') {
      final n = int.tryParse(e.value.trim());
      if (n != null) return n;
    }
  }
  return utf8.encode(response.body).length;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `fvm flutter test test/core/network/http_response_test.dart test/core/utils/byte_format_test.dart`
Expected: PASS.

- [ ] **Step 5: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test
git add lib/core/network/http_response.dart lib/core/utils/byte_format.dart test/core/network/http_response_test.dart test/core/utils/byte_format_test.dart
git commit -m "feat(response): add bodyBytes to HttpResponseEntity (live-only)"
```

---

### Task 3: Streaming bytes capture + cap in `NetworkService`

**Files:**
- Modify: `lib/core/network/network_service.dart`
- Modify: `lib/core/domain/persistence_limits.dart` (add the cap constant)
- Test: `test/core/network/network_service_capture_test.dart` (create)

**Interfaces:**
- Consumes: `classifyResponseMedia`, `contentTypeOf`, `mediaExtension` (Task 1); `formatBytes` (`byte_format.dart`); `HttpResponseEntity.bodyBytes` (Task 2).
- Produces: `NetworkService({required Dio dio, int maxResponseBytes})` (default `kMaxRenderableResponseBytes`); `request(...)` now streams, caps, classifies, and either decodes to `body` (textual) or keeps `bodyBytes` (media/binary).

- [ ] **Step 1: Add the cap constant** to `lib/core/domain/persistence_limits.dart`:

```dart
/// Largest response body we will buffer into memory to render. Beyond this the
/// stream is abandoned and the response carries no renderable body (an "open
/// externally" card is shown). Protects against pulling a huge video into RAM.
const int kMaxRenderableResponseBytes = 50 * 1024 * 1024; // 50 MiB
```

- [ ] **Step 2: Write the failing test**

```dart
// test/core/network/network_service_capture_test.dart
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/network_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.bytes, required this.headers});
  final List<int> bytes;
  final Map<String, List<String>> headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromBytes(bytes, 200, headers: headers);

  @override
  void close({bool force = false}) {}
}

NetworkService serviceReturning(
  List<int> bytes,
  Map<String, List<String>> headers, {
  int maxResponseBytes = 50 * 1024 * 1024,
}) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  dio.httpClientAdapter = _FakeAdapter(bytes: bytes, headers: headers);
  return NetworkService(dio: dio, maxResponseBytes: maxResponseBytes);
}

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

  test('stream exceeding cap (no content-length) → too-large placeholder',
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
  });

  test('empty body → empty string, no bytes', () async {
    final svc = serviceReturning(const [], {
      'content-type': ['image/png'],
    });
    final r = await svc.request(url: 'https://x/a.png', method: 'GET');
    expect(r.body, '');
    expect(r.bodyBytes, isNull);
  });
}
```

(Add `import 'dart:convert';` at the top of the test.)

- [ ] **Step 3: Run to verify it fails**

Run: `fvm flutter test test/core/network/network_service_capture_test.dart`
Expected: FAIL — `maxResponseBytes` named param missing / body not decoded as expected.

- [ ] **Step 4: Implement** — edit `lib/core/network/network_service.dart`:

Add imports:
```dart
import 'dart:typed_data';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/utils/byte_format.dart';
import 'package:getman/core/utils/response_media.dart';
```
Remove the now-unused `String _jsonEncode(...)` top-level helper.

Change the constructor + field:
```dart
  NetworkService({required Dio dio, int maxResponseBytes = kMaxRenderableResponseBytes})
      : _dio = dio,
        _maxResponseBytes = maxResponseBytes;
  final Dio _dio;
  final int _maxResponseBytes;
```

In `buildDio`, change `responseType: ResponseType.plain` to `responseType: ResponseType.stream`. Update the adjacent comment to explain streaming + capping.

Replace the body of `request(...)` between the `try {` and the `} on DioException` with:

```dart
      final response = await _dio.request<ResponseBody>(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );
      final headersMap =
          response.headers.map.map((k, v) => MapEntry(k, v.join(', ')));
      final status = response.statusCode ?? 0;

      // Early-out: declared length already over the cap → don't read at all.
      final declared =
          int.tryParse(response.headers.value('content-length') ?? '');
      if (declared != null && declared > _maxResponseBytes) {
        cancelToken.cancel();
        stopwatch.stop();
        return HttpResponseEntity(
          statusCode: status,
          body: _tooLargePlaceholder(headersMap, url, declared),
          headers: headersMap,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }

      final stream = response.data?.stream;
      final builder = BytesBuilder(copy: false);
      var overflow = false;
      if (stream != null) {
        await for (final chunk in stream) {
          builder.add(chunk);
          if (builder.length > _maxResponseBytes) {
            overflow = true;
            cancelToken.cancel();
            break;
          }
        }
      }
      stopwatch.stop();

      if (overflow) {
        return HttpResponseEntity(
          statusCode: status,
          body: _tooLargePlaceholder(headersMap, url, builder.length),
          headers: headersMap,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }

      final bytes = builder.takeBytes();
      final contentType = contentTypeOf(headersMap);
      final kind = bytes.isEmpty
          ? ResponseMediaKind.textual
          : classifyResponseMedia(
              contentType: contentType, url: url, sniffBytes: bytes);

      if (kind == ResponseMediaKind.textual) {
        return HttpResponseEntity(
          statusCode: status,
          body: bytes.isEmpty ? '' : utf8.decode(bytes, allowMalformed: true),
          headers: headersMap,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }
      return HttpResponseEntity(
        statusCode: status,
        body: _mediaPlaceholder(contentType, kind, bytes.length),
        headers: headersMap,
        durationMs: stopwatch.elapsedMilliseconds,
        bodyBytes: bytes,
      );
```

Replace `_stringifyBody` with these helpers:

```dart
  String _mediaPlaceholder(String? contentType, ResponseMediaKind kind, int n) {
    final label = contentType ?? kind.name;
    return '[$label · ${formatBytes(n)} — open the PREVIEW tab to view]';
  }

  String _tooLargePlaceholder(
    Map<String, String> headers,
    String url,
    int size,
  ) {
    final ct = contentTypeOf(headers) ?? 'binary';
    return '[$ct · ${formatBytes(size)} — too large to buffer; open externally]';
  }
```

Note: dio's stream is `Stream<Uint8List>`, so `builder.add(chunk)` and the cancel-on-overflow path compile without casts.

- [ ] **Step 5: Run to verify it passes**

Run: `fvm flutter test test/core/network/network_service_capture_test.dart test/core/network/network_service_test.dart`
Expected: PASS (both files).

- [ ] **Step 6: Full suite (capture change touches the send path)**

Run: `fvm flutter test`
Expected: PASS. If any send/response test asserted on a previously-`plain` body shape, fix the assertion to match the decoded-bytes body (identical string for textual responses).

- [ ] **Step 7: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test
git add lib/core/network/network_service.dart lib/core/domain/persistence_limits.dart test/core/network/network_service_capture_test.dart
git commit -m "feat(response): stream + cap response capture, keep bytes for media"
```

---

### Task 4: Body-view routing + media shell + bytes save helper

**Files:**
- Modify: `lib/features/tabs/presentation/widgets/response/response_body_view.dart`
- Create: `lib/features/tabs/presentation/widgets/response/viewers/response_media_panel.dart`
- Modify: `lib/core/utils/json_file_io.dart` (add `saveBytesFileWithFeedback`)
- Test: `test/features/tabs/presentation/widgets/response/response_media_routing_test.dart` (create)

**Interfaces:**
- Consumes: `classifyResponseMedia`, `contentTypeOf` (Task 1); `HttpResponseEntity.bodyBytes` (Task 2).
- Produces:
  - `ResponseMediaPanel({required String tabId})` — StatefulWidget; reads the tab's response, classifies, shows a `PREVIEW`/`RAW` toggle. PREVIEW → the matching viewer or a null-bytes placeholder (keys: `media_preview_image`, `media_preview_placeholder`, etc.); RAW → `BinaryResponseView` (Task 5). For Phase-1 it renders `ImageResponseView` for image and `BinaryResponseView` otherwise (later phases add viewers here).
  - `Future<void> saveBytesFileWithFeedback(BuildContext context, {required Uint8List bytes, required String fileName, required String dialogTitle, List<String> allowedExtensions})`.
- The existing textual logic is extracted verbatim into a private `_TextualResponseBody` StatefulWidget (same fields/behavior); `ResponseBodyView` becomes a thin dispatcher.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/tabs/presentation/widgets/response/response_media_routing_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/response_media_panel.dart';
// Helper imports: reuse the project's existing response-section test harness
// (pumpResponseWith...) — see response_body_view_compare_test.dart for the
// established BlocProvider+theme pump pattern and copy it here.

void main() {
  testWidgets('image response routes to image preview', (tester) async {
    // Pump a tab whose response has content-type image/png + a tiny valid PNG
    // in bodyBytes, using the existing response test harness.
    // EXPECT: find.byKey(const ValueKey('media_preview_image')) is present.
  }, skip: true); // un-skip after wiring the shared harness below

  testWidgets('media with null bytes shows not-stored placeholder',
      (tester) async {
    // Pump a tab whose response has content-type video/mp4 but bodyBytes == null
    // (restored). EXPECT: find.byKey(const ValueKey('media_preview_placeholder')).
  }, skip: true);
}
```

> NOTE TO IMPLEMENTER: open `test/features/tabs/presentation/widgets/response/response_body_view_compare_test.dart`, copy its setup (how it builds a `TabsBloc`/`SettingsBloc`/themed `MaterialApp` and pumps a tab with a response), and use it to fill in these two tests — then remove `skip: true`. The two assertions above are the contract; the harness is boilerplate, not new design.

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/response/response_media_routing_test.dart`
Expected: FAIL — `response_media_panel.dart` does not exist.

- [ ] **Step 3: Extract the textual view.** In `response_body_view.dart`, rename the existing `class ResponseBodyView` widget's State logic into a new private widget `class _TextualResponseBody extends StatefulWidget` with the SAME two fields (`tabId`, `responseController`) and move the entire current `_ResponseBodyViewState` body into `_TextualResponseBodyState` unchanged. Do not alter its internals.

- [ ] **Step 4: Make `ResponseBodyView` a dispatcher:**

```dart
class ResponseBodyView extends StatelessWidget {
  const ResponseBodyView({
    required this.tabId,
    required this.responseController,
    super.key,
  });
  final String tabId;
  final CodeLineEditingController responseController;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (prev, next) {
        final p = prev.tabs.byId(tabId)?.response;
        final n = next.tabs.byId(tabId)?.response;
        return p?.body != n?.body ||
            p?.bodyBytes?.length != n?.bodyBytes?.length ||
            contentTypeOf(p?.headers ?? const {}) !=
                contentTypeOf(n?.headers ?? const {});
      },
      builder: (context, state) {
        final tab = state.tabs.byId(tabId);
        final resp = tab?.response;
        final kind = classifyResponseMedia(
          contentType: contentTypeOf(resp?.headers ?? const {}),
          url: tab?.config.url,
          sniffBytes: resp?.bodyBytes,
        );
        if (resp != null && kind != ResponseMediaKind.textual) {
          return ResponseMediaPanel(tabId: tabId);
        }
        return _TextualResponseBody(
          tabId: tabId,
          responseController: responseController,
        );
      },
    );
  }
}
```

Add imports for `classifyResponseMedia`/`contentTypeOf`/`ResponseMediaKind` and `response_media_panel.dart`.

- [ ] **Step 5: Create `ResponseMediaPanel`** (`viewers/response_media_panel.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/response_media.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/binary_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/image_response_view.dart';

enum _MediaTab { preview, raw }

/// Renders a non-textual response: a PREVIEW/RAW toggle over the matching
/// viewer. RAW is always the binary card (size + Save); PREVIEW is the
/// kind-specific viewer, or a "not stored this session" placeholder when the
/// live bytes are gone (restored tab / older time-travel entry).
class ResponseMediaPanel extends StatefulWidget {
  const ResponseMediaPanel({required this.tabId, super.key});
  final String tabId;

  @override
  State<ResponseMediaPanel> createState() => _ResponseMediaPanelState();
}

class _ResponseMediaPanelState extends State<ResponseMediaPanel> {
  _MediaTab _tab = _MediaTab.preview;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (p, n) {
        final pr = p.tabs.byId(widget.tabId)?.response;
        final nr = n.tabs.byId(widget.tabId)?.response;
        return pr?.bodyBytes?.length != nr?.bodyBytes?.length ||
            pr?.body != nr?.body;
      },
      builder: (context, state) {
        final tab = state.tabs.byId(widget.tabId);
        final resp = tab?.response;
        if (resp == null) return const SizedBox.shrink();
        final contentType = contentTypeOf(resp.headers);
        final kind = classifyResponseMedia(
          contentType: contentType,
          url: tab?.config.url,
          sniffBytes: resp.bodyBytes,
        );
        final bytes = resp.bodyBytes;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toggle(context),
            Expanded(
              child: _tab == _MediaTab.raw || bytes == null
                  ? (bytes == null && _tab == _MediaTab.preview
                      ? _notStored(context, resp.body)
                      : BinaryResponseView(
                          bytes: bytes,
                          contentType: contentType,
                          url: tab?.config.url,
                          placeholderBody: resp.body,
                        ))
                  : _viewer(context, kind, bytes, contentType, tab?.config.url),
            ),
          ],
        );
      },
    );
  }

  Widget _viewer(
    BuildContext context,
    ResponseMediaKind kind,
    Uint8List bytes,
    String? contentType,
    String? url,
  ) {
    switch (kind) {
      case ResponseMediaKind.image:
        return ImageResponseView(
          key: const ValueKey('media_preview_image'),
          bytes: bytes,
        );
      // Phase 2/3/4 add: csv, html, pdf, video, audio cases here.
      default:
        return BinaryResponseView(
          bytes: bytes,
          contentType: contentType,
          url: url,
          placeholderBody: '',
        );
    }
  }

  Widget _notStored(BuildContext context, String placeholder) {
    final layout = context.appLayout;
    return Center(
      key: const ValueKey('media_preview_placeholder'),
      child: Padding(
        padding: EdgeInsets.all(layout.pagePadding),
        child: Text(
          'Media not stored this session — re-send to view.\n$placeholder',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget _toggle(BuildContext context) {
    final layout = context.appLayout;
    Widget seg(String label, _MediaTab t) {
      final active = _tab == t;
      final bg = context.appPalette.selectorActive;
      return GestureDetector(
        onTap: () => setState(() => _tab = t),
        child: Container(
          key: ValueKey('media_toggle_$label'),
          margin: EdgeInsets.all(layout.tabSpacing),
          padding: EdgeInsets.symmetric(
            horizontal: layout.badgePaddingHorizontal + 4,
            vertical: layout.badgePaddingVertical + 2,
          ),
          decoration: BoxDecoration(
            color: active ? bg : Colors.transparent,
            border: Border.all(
              color: Theme.of(context).dividerColor,
              width: layout.borderThin,
            ),
            borderRadius: BorderRadius.circular(context.appShape.buttonRadius),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.displayWeight,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
      child: Wrap(children: [seg('PREVIEW', _MediaTab.preview), seg('RAW', _MediaTab.raw)]),
    );
  }
}
```

(Add `import 'dart:typed_data';` at the top.)

- [ ] **Step 6: Add `saveBytesFileWithFeedback`** to `lib/core/utils/json_file_io.dart`:

```dart
/// Prompts for a destination and writes raw [bytes] there, reporting via
/// snackbar. Mirrors saveTextFileWithFeedback but for binary content.
Future<void> saveBytesFileWithFeedback(
  BuildContext context, {
  required Uint8List bytes,
  required String fileName,
  required String dialogTitle,
  List<String> allowedExtensions = const ['bin'],
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final path = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );
    if (path == null) return;
    if (!kIsWeb) {
      await File(path).writeAsBytes(bytes);
    }
    messenger?.showSnackBar(SnackBar(content: Text('Saved to $path')));
  } on Object catch (e) {
    debugPrint('Save failed: $e');
    messenger?.showSnackBar(SnackBar(content: Text('Save failed: $e')));
  }
}
```

(Add `import 'dart:typed_data';` to `json_file_io.dart`.)

- [ ] **Step 7: Fill in + un-skip the two routing tests** (Task 4 Step 1) using the copied harness; run:

Run: `fvm flutter test test/features/tabs/presentation/widgets/response/response_media_routing_test.dart`
Expected: PASS. (`ImageResponseView` + `BinaryResponseView` come from Task 5 — implement Task 5 first if you hit a missing-import compile error, or stub them minimally and let Task 5 complete them. Recommended order: do Task 5's widgets before un-skipping here.)

- [ ] **Step 8: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test
git add lib/features/tabs/presentation/widgets/response/ lib/core/utils/json_file_io.dart test/features/tabs/presentation/widgets/response/response_media_routing_test.dart
git commit -m "feat(response): route media responses to a PREVIEW/RAW panel"
```

---

### Task 5: Image viewer + binary card

**Files:**
- Create: `lib/features/tabs/presentation/widgets/response/viewers/image_response_view.dart`
- Create: `lib/features/tabs/presentation/widgets/response/viewers/binary_response_view.dart`
- Test: `test/features/tabs/presentation/widgets/response/image_binary_viewers_test.dart` (create)

**Interfaces:**
- Consumes: `mediaExtension`, `formatBytes`, `saveBytesFileWithFeedback`.
- Produces:
  - `ImageResponseView({required Uint8List bytes})` — `Image.memory` centered + interactive scroll; on decode error shows a small "cannot decode image" note.
  - `BinaryResponseView({required Uint8List? bytes, String? contentType, String? url, required String placeholderBody})` — card with content-type, size, and a Save button (disabled/hidden when bytes null).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/tabs/presentation/widgets/response/image_binary_viewers_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/binary_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/image_response_view.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: resolveTheme('classic')(Brightness.light, false), home: Scaffold(body: child));

void main() {
  testWidgets('ImageResponseView builds an Image widget', (tester) async {
    // 1x1 transparent PNG.
    final png = Uint8List.fromList(<int>[
      0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,
      0x49,0x48,0x44,0x52,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
      0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,0x89,0x00,0x00,0x00,
      0x0A,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
      0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,
      0x45,0x4E,0x44,0xAE,0x42,0x60,0x82,
    ]);
    await tester.pumpWidget(_host(ImageResponseView(bytes: png)));
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('BinaryResponseView shows type + size + Save', (tester) async {
    await tester.pumpWidget(_host(BinaryResponseView(
      bytes: Uint8List(2048),
      contentType: 'application/zip',
      url: 'https://x/a.zip',
      placeholderBody: '',
    )));
    expect(find.textContaining('application/zip'), findsOneWidget);
    expect(find.textContaining('2.0 KB'), findsOneWidget);
    expect(find.byKey(const ValueKey('binary_save_button')), findsOneWidget);
  });

  testWidgets('BinaryResponseView with null bytes hides Save', (tester) async {
    await tester.pumpWidget(_host(const BinaryResponseView(
      bytes: null, contentType: 'application/zip', url: null, placeholderBody: 'x',
    )));
    expect(find.byKey(const ValueKey('binary_save_button')), findsNothing);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/tabs/presentation/widgets/response/image_binary_viewers_test.dart`
Expected: FAIL — viewers don't exist.

- [ ] **Step 3: Implement `ImageResponseView`:**

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Renders an image response from raw bytes, pannable/zoomable on a themed
/// surface. Falls back to a short note if the bytes don't decode.
class ImageResponseView extends StatelessWidget {
  const ImageResponseView({required this.bytes, super.key});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return ColoredBox(
      color: context.appPalette.codeBackground,
      child: Padding(
        padding: EdgeInsets.all(layout.pagePadding),
        child: InteractiveViewer(
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => Text(
                'Cannot decode image',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement `BinaryResponseView`:**

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/byte_format.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/core/utils/response_media.dart';

/// Fallback card for a binary/unviewable response (or the RAW tab of any media
/// response): content-type, size, and Save-to-file. Save is hidden when the
/// live bytes are gone.
class BinaryResponseView extends StatelessWidget {
  const BinaryResponseView({
    required this.bytes,
    required this.contentType,
    required this.url,
    required this.placeholderBody,
    super.key,
  });
  final Uint8List? bytes;
  final String? contentType;
  final String? url;
  final String placeholderBody;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final data = bytes;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(layout.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              contentType ?? 'binary',
              style: TextStyle(fontWeight: typography.titleWeight),
            ),
            SizedBox(height: layout.tabSpacing),
            if (data != null)
              Text('${formatBytes(data.length)} · ${data.length} bytes')
            else
              Text(
                placeholderBody.isEmpty
                    ? 'Not stored this session — re-send to view.'
                    : placeholderBody,
                textAlign: TextAlign.center,
              ),
            if (data != null) ...[
              SizedBox(height: layout.pagePadding),
              ElevatedButton.icon(
                key: const ValueKey('binary_save_button'),
                icon: const Icon(Icons.download),
                label: const Text('SAVE TO FILE'),
                onPressed: () => saveBytesFileWithFeedback(
                  context,
                  bytes: data,
                  fileName:
                      'response.${mediaExtension(contentType: contentType, url: url)}',
                  dialogTitle: 'Save response',
                  allowedExtensions: [
                    mediaExtension(contentType: contentType, url: url),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `fvm flutter test test/features/tabs/presentation/widgets/response/image_binary_viewers_test.dart`
Expected: PASS. Then run the Task 4 routing test (un-skipped) — also PASS.

- [ ] **Step 6: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test
git add lib/features/tabs/presentation/widgets/response/viewers/ test/features/tabs/presentation/widgets/response/image_binary_viewers_test.dart
git commit -m "feat(response): image viewer + binary save card"
```

**Phase 1 gate:** `fvm flutter test` fully green; sending an image/binary URL renders inline; JSON/text responses behave exactly as before.

---

# Phase 2 — CSV + HTML

### Task 6: CSV table viewer

**Files:**
- Modify: `pubspec.yaml` (add `csv`)
- Create: `lib/features/tabs/presentation/widgets/response/viewers/csv_response_view.dart`
- Modify: `response_media_panel.dart` (route `csv`)
- Test: `test/features/tabs/presentation/widgets/response/csv_response_view_test.dart`

**Interfaces:**
- Produces: `CsvResponseView({required Uint8List bytes})` — decodes UTF-8, parses with the `csv` package, renders a scrollable `DataTable` (first row = header), caps at 500 rows with a "showing first N of M" note.

- [ ] **Step 1: Add dep** — `fvm flutter pub add csv` then `fvm flutter pub get`. Confirm analyzer stays at 8.4 (Global Constraints).

- [ ] **Step 2: Write the failing test**

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/csv_response_view.dart';

void main() {
  testWidgets('renders header + rows incl. quoted commas', (tester) async {
    final csv = Uint8List.fromList(
        'name,note\n"Doe, John",hi\nJane,"a,b"'.codeUnits);
    await tester.pumpWidget(MaterialApp(
      theme: resolveTheme('classic')(Brightness.light, false),
      home: Scaffold(body: CsvResponseView(bytes: csv)),
    ));
    expect(find.text('name'), findsOneWidget);
    expect(find.text('Doe, John'), findsOneWidget);
    expect(find.text('a,b'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run to verify it fails** — `fvm flutter test .../csv_response_view_test.dart` → FAIL.

- [ ] **Step 4: Implement:**

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Renders a CSV response as a scrollable table (first row = header).
class CsvResponseView extends StatelessWidget {
  const CsvResponseView({required this.bytes, super.key});
  final Uint8List bytes;

  static const _maxRows = 500;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final rows = const CsvToListConverter(shouldParseNumbers: false)
        .convert(utf8.decode(bytes, allowMalformed: true));
    if (rows.isEmpty) {
      return const Center(child: Text('Empty CSV'));
    }
    final header = rows.first;
    final body = rows.skip(1).take(_maxRows).toList();
    final truncated = rows.length - 1 > _maxRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (truncated)
          Padding(
            padding: EdgeInsets.all(layout.tabSpacing),
            child: Text('Showing first $_maxRows of ${rows.length - 1} rows'),
          ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final h in header)
                    DataColumn(label: Text('$h')),
                ],
                rows: [
                  for (final r in body)
                    DataRow(
                      cells: [
                        for (var i = 0; i < header.length; i++)
                          DataCell(Text(i < r.length ? '${r[i]}' : '')),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Route it** — in `response_media_panel.dart` `_viewer`, add before `default`:

```dart
      case ResponseMediaKind.csv:
        return CsvResponseView(key: const ValueKey('media_preview_csv'), bytes: bytes);
```
(import `csv_response_view.dart`.)

- [ ] **Step 6: Run** — `fvm flutter test .../csv_response_view_test.dart` → PASS.

- [ ] **Step 7: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test
git add pubspec.yaml pubspec.lock lib/features/tabs/presentation/widgets/response/viewers/csv_response_view.dart lib/features/tabs/presentation/widgets/response/viewers/response_media_panel.dart test/features/tabs/presentation/widgets/response/csv_response_view_test.dart
git commit -m "feat(response): CSV table viewer"
```

---

### Task 7: HTML viewer (source + open-in-browser)

**Files:**
- Create: `lib/features/tabs/presentation/widgets/response/viewers/html_response_view.dart`
- Modify: `response_media_panel.dart` (route `html`)
- Test: `test/features/tabs/presentation/widgets/response/html_response_view_test.dart`

**Interfaces:**
- Consumes: `url_launcher` (already a dep), `path_provider` (already a dep), `mediaExtension`.
- Produces: `HtmlResponseView({required Uint8List bytes})` — shows the HTML **source** (selectable) + an `OPEN IN BROWSER` button (key `html_open_in_browser`) that writes the bytes to a temp `.html` file and launches it. Web: the button writes nothing (guarded) — show source only.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/html_response_view.dart';

void main() {
  testWidgets('shows source + open-in-browser button', (tester) async {
    final html = Uint8List.fromList('<h1>Hello</h1>'.codeUnits);
    await tester.pumpWidget(MaterialApp(
      theme: resolveTheme('classic')(Brightness.light, false),
      home: Scaffold(body: HtmlResponseView(bytes: html)),
    ));
    expect(find.textContaining('<h1>Hello</h1>'), findsOneWidget);
    expect(find.byKey(const ValueKey('html_open_in_browser')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Implement:**

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows an HTML response as source plus an "open in the real browser" action
/// (faithful preview, no embedded webview). Source stays inspectable.
class HtmlResponseView extends StatelessWidget {
  const HtmlResponseView({required this.bytes, super.key});
  final Uint8List bytes;

  Future<void> _openInBrowser(BuildContext context) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/getman_response_${DateTime.now().millisecondsSinceEpoch}.html',
      );
      await file.writeAsBytes(bytes);
      await launchUrl(file.uri);
    } on Object catch (e) {
      if (context.mounted) showAppSnackBar(context, 'Could not open: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!kIsWeb)
          Padding(
            padding: EdgeInsets.all(layout.tabSpacing),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                key: const ValueKey('html_open_in_browser'),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('OPEN IN BROWSER'),
                onPressed: () => _openInBrowser(context),
              ),
            ),
          ),
        Expanded(
          child: ColoredBox(
            color: context.appPalette.codeBackground,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(layout.pagePadding),
              child: SelectableText(
                utf8.decode(bytes, allowMalformed: true),
                style: TextStyle(
                  fontFamily: typography.codeFontFamily,
                  fontSize: layout.fontSizeCode,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

(Add `import 'dart:convert';`. On web, `dart:io` `File` is unavailable — gate the whole button with `!kIsWeb` as shown, and since the import of `dart:io` would still break web compile, guard with a conditional import: create `html_response_view_io.dart` (real `_openInBrowser`) + `html_response_view_stub.dart` (no-op) exported via a conditional `export`, mirroring the `update_gate.dart` pattern in the codebase. If the simpler `!kIsWeb` guard compiles for the project's web target in CI, prefer it; otherwise use the conditional-import split.)

- [ ] **Step 4: Route it** — in `response_media_panel.dart` `_viewer`, add:

```dart
      case ResponseMediaKind.html:
        return HtmlResponseView(key: const ValueKey('media_preview_html'), bytes: bytes);
```

- [ ] **Step 5: Run** → PASS.

- [ ] **Step 6: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test
git add lib/features/tabs/presentation/widgets/response/viewers/ test/features/tabs/presentation/widgets/response/html_response_view_test.dart
git commit -m "feat(response): HTML source + open-in-browser viewer"
```

---

# Phase 3 — PDF

### Task 8: PDF viewer (`pdfx`)

**Files:**
- Modify: `pubspec.yaml` (add `pdfx`)
- Create: `lib/features/tabs/presentation/widgets/response/viewers/pdf_response_view.dart`
- Modify: `response_media_panel.dart` (route `pdf`)
- Test: `test/features/tabs/presentation/widgets/response/pdf_response_view_test.dart` (smoke — construct only)

**Interfaces:**
- Produces: `PdfResponseView({required Uint8List bytes})` — `pdfx` `PdfViewPinch` over `PdfDocument.openData(bytes)`; disposes the controller; on error falls back to a short note.

- [ ] **Step 1: Add dep** — `fvm flutter pub add pdfx` then `fvm flutter pub get`. Confirm analyzer stays at 8.4; if `pdfx` breaks the web build, gate via a conditional import like `update_gate.dart`.

- [ ] **Step 2: Write the smoke test** (no real render — just that it constructs without throwing on a minimal PDF; pdfx render needs native pdfium so keep it a construction smoke):

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/pdf_response_view.dart';

void main() {
  testWidgets('constructs without throwing', (tester) async {
    final pdf = Uint8List.fromList('%PDF-1.4\n%%EOF'.codeUnits);
    await tester.pumpWidget(MaterialApp(
      theme: resolveTheme('classic')(Brightness.light, false),
      home: Scaffold(body: PdfResponseView(bytes: pdf)),
    ));
    expect(find.byType(PdfResponseView), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run to verify it fails** → FAIL.

- [ ] **Step 4: Implement:**

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:pdfx/pdfx.dart';

/// Renders a PDF response inline via pdfx (native pdfium).
class PdfResponseView extends StatefulWidget {
  const PdfResponseView({required this.bytes, super.key});
  final Uint8List bytes;

  @override
  State<PdfResponseView> createState() => _PdfResponseViewState();
}

class _PdfResponseViewState extends State<PdfResponseView> {
  late final PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openData(widget.bytes),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.appPalette.codeBackground,
      child: PdfViewPinch(
        controller: _controller,
        onDocumentError: (error) {},
        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, error) =>
              Center(child: Text('Cannot render PDF: $error')),
        ),
      ),
    );
  }
}
```

(If the installed `pdfx` API differs slightly — class names like `PdfControllerPinch`/`PdfViewPinch` are stable in 2.x — adapt to the resolved version's signatures; keep `PdfDocument.openData(bytes)` as the byte entry point.)

- [ ] **Step 5: Route it** — in `_viewer`: `case ResponseMediaKind.pdf: return PdfResponseView(key: const ValueKey('media_preview_pdf'), bytes: bytes);`

- [ ] **Step 6: Run** → PASS. Then `fvm flutter test` full suite.

- [ ] **Step 7: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart format lib test
git add pubspec.yaml pubspec.lock lib/features/tabs/presentation/widgets/response/viewers/ test/features/tabs/presentation/widgets/response/pdf_response_view_test.dart
git commit -m "feat(response): inline PDF viewer (pdfx)"
```

---

# Phase 4 — Video / Audio (media_kit)

### Task 9: Media player viewer

**Files:**
- Modify: `pubspec.yaml` (add `media_kit`, `media_kit_video`, `media_kit_libs_video`)
- Modify: `lib/main.dart` (call `MediaKit.ensureInitialized()`)
- Create: `lib/features/tabs/presentation/widgets/response/viewers/media_response_view.dart`
- Modify: `response_media_panel.dart` (route `video` + `audio`)
- Test: `test/features/tabs/presentation/widgets/response/media_response_view_test.dart` (routing/placeholder smoke)

**Interfaces:**
- Consumes: `path_provider` (temp file), `mediaExtension`.
- Produces: `MediaResponseView({required Uint8List bytes, required bool isVideo, String? contentType, String? url})` — writes bytes to a temp file, plays via media_kit; video shows the `Video` widget, audio shows a compact transport. On web (`kIsWeb`) or init failure, shows a graceful "open externally / save" fallback (reuse `BinaryResponseView`).

- [ ] **Step 1: Add deps** — `fvm flutter pub add media_kit media_kit_video media_kit_libs_video` then `fvm flutter pub get`. Confirm analyzer stays at 8.4. On macOS, run `fvm flutter build macos --debug` once to confirm native libs link.

- [ ] **Step 2: Initialize** — in `lib/main.dart`, after `WidgetsFlutterBinding.ensureInitialized()` add:

```dart
  MediaKit.ensureInitialized();
```
(import `package:media_kit/media_kit.dart`.)

- [ ] **Step 3: Write the smoke test** (web fallback path, no native playback):

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/media_response_view.dart';

void main() {
  testWidgets('constructs and shows controls/fallback', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: resolveTheme('classic')(Brightness.light, false),
      home: Scaffold(
        body: MediaResponseView(
          bytes: Uint8List.fromList([0, 1, 2, 3]),
          isVideo: false,
          contentType: 'audio/mpeg',
          url: 'https://x/a.mp3',
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(MediaResponseView), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run to verify it fails** → FAIL.

- [ ] **Step 5: Implement:**

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/response_media.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/binary_response_view.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

/// Plays a video/audio response via media_kit. Bytes are written to a temp file
/// and opened. On web or init failure, degrades to the binary save card.
class MediaResponseView extends StatefulWidget {
  const MediaResponseView({
    required this.bytes,
    required this.isVideo,
    required this.contentType,
    required this.url,
    super.key,
  });
  final Uint8List bytes;
  final bool isVideo;
  final String? contentType;
  final String? url;

  @override
  State<MediaResponseView> createState() => _MediaResponseViewState();
}

class _MediaResponseViewState extends State<MediaResponseView> {
  Player? _player;
  VideoController? _videoController;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _start();
    } else {
      _failed = true; // web: fall back to save card (no temp file)
    }
  }

  Future<void> _start() async {
    try {
      final dir = await getTemporaryDirectory();
      final ext = mediaExtension(contentType: widget.contentType, url: widget.url);
      final file = File(
        '${dir.path}/getman_media_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await file.writeAsBytes(widget.bytes);
      final player = Player();
      final vc = widget.isVideo ? VideoController(player) : null;
      await player.open(Media(file.uri.toString()), play: false);
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _videoController = vc;
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    if (_failed || player == null) {
      if (_failed) {
        return BinaryResponseView(
          bytes: widget.bytes,
          contentType: widget.contentType,
          url: widget.url,
          placeholderBody: '',
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.isVideo && _videoController != null) {
      return Video(controller: _videoController!);
    }
    return _AudioTransport(player: player);
  }
}

/// Minimal play/pause + seek bar for audio.
class _AudioTransport extends StatelessWidget {
  const _AudioTransport({required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Padding(
      padding: EdgeInsets.all(layout.pagePadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          StreamBuilder<bool>(
            stream: player.stream.playing,
            initialData: false,
            builder: (context, snap) {
              final playing = snap.data ?? false;
              return IconButton(
                key: const ValueKey('audio_play_pause'),
                iconSize: layout.iconSizeLarge,
                icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                onPressed: player.playOrPause,
              );
            },
          ),
          StreamBuilder<Duration>(
            stream: player.stream.position,
            initialData: Duration.zero,
            builder: (context, posSnap) {
              return StreamBuilder<Duration>(
                stream: player.stream.duration,
                initialData: Duration.zero,
                builder: (context, durSnap) {
                  final dur = durSnap.data ?? Duration.zero;
                  final pos = posSnap.data ?? Duration.zero;
                  final max = dur.inMilliseconds == 0 ? 1.0 : dur.inMilliseconds.toDouble();
                  return Slider(
                    value: pos.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                    max: max,
                    onChanged: (v) =>
                        player.seek(Duration(milliseconds: v.toInt())),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
```

(If `context.appLayout` lacks `iconSizeLarge`, use an existing size field or add one to `AppLayout` across all theme builders per Global Constraints — check `lib/core/theme/extensions/` first and reuse an existing icon size.)

- [ ] **Step 6: Route it** — in `_viewer`:

```dart
      case ResponseMediaKind.video:
        return MediaResponseView(
          key: const ValueKey('media_preview_video'),
          bytes: bytes, isVideo: true, contentType: contentType, url: url,
        );
      case ResponseMediaKind.audio:
        return MediaResponseView(
          key: const ValueKey('media_preview_audio'),
          bytes: bytes, isVideo: false, contentType: contentType, url: url,
        );
```

- [ ] **Step 7: Run** — `fvm flutter test .../media_response_view_test.dart` → PASS. Then full `fvm flutter test`.

- [ ] **Step 8: Manual verification** — `fvm flutter run -d macos`; send a request to a public mp4 and mp3 URL (e.g. a sample-videos / file-examples link), confirm inline playback; send an image, a PDF, a CSV, and an HTML URL; confirm each viewer. Confirm a JSON endpoint still shows PRETTY/RAW/TREE unchanged.

- [ ] **Step 9: Done-bar + commit**

```bash
fvm flutter analyze && fvm dart run custom_lint && fvm dart run bloc_tools:bloc lint lib && fvm dart format lib test
git add pubspec.yaml pubspec.lock lib/main.dart lib/features/tabs/presentation/widgets/response/viewers/ test/features/tabs/presentation/widgets/response/media_response_view_test.dart
git commit -m "feat(response): embedded video/audio player (media_kit)"
```

---

# Phase 5 — Docs

### Task 10: Wiki sync

**Files:** the `Getman.wiki.git` repo (separate clone).

- [ ] **Step 1:** Clone `https://github.com/thiagomiranda3/Getman.wiki.git`.
- [ ] **Step 2:** On the response-panel page, add a "Rich response previews" section: lists the supported viewers (image, video, audio, PDF, CSV table, HTML preview/open-in-browser, binary save card), the PREVIEW/RAW toggle, and the **live-only** caveat (media not stored across restart — re-send to view). Use verbatim UI labels (`PREVIEW`, `RAW`, `OPEN IN BROWSER`, `SAVE TO FILE`).
- [ ] **Step 3:** Commit + push (`master`).

---

## Self-Review (completed by author)

**Spec coverage:**
- Classifier (spec §Component 1) → Task 1 ✔
- Bytes capture + entity (§Component 2) → Tasks 2–3 ✔ (streaming cap = Task 3)
- Viewers (§Component 3): image/binary → Task 5; csv → Task 6; html → Task 7; pdf → Task 8; video/audio → Task 9 ✔
- Body-view routing (§Component 4) → Task 4 ✔ (incl. live-only placeholder)
- Bytes save (§Component 5) → Task 4 ✔
- Persistence unchanged (§Persistence) → no Hive task; constraint stated ✔
- Platform/web/Linux degradation (§Platform notes) → Tasks 7/8/9 guards + Task 9 fallback ✔
- Testing (§Testing) → per-task tests ✔
- Phasing (§Implementation phasing) → Phases 1–4 match ✔
- Wiki (§Wiki) → Task 10 ✔

**Placeholder scan:** No TBD/TODO. The only deferred detail is the two routing tests' shared pump harness (Task 4) — explicitly directed to copy the existing `response_body_view_compare_test.dart` harness, with the exact assertions given.

**Type consistency:** `classifyResponseMedia`, `contentTypeOf`, `mediaExtension`, `ResponseMediaKind`, `HttpResponseEntity.bodyBytes`, `BinaryResponseView(bytes/contentType/url/placeholderBody)`, `ImageResponseView(bytes)`, `MediaResponseView(bytes/isVideo/contentType/url)` — names match across all tasks and the `_viewer` switch.
