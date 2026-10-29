// Conditional-import seam for decodeContentEncoding — NetworkService's
// response-side Content-Encoding handling (gzip/deflate self-decompression
// when the platform didn't do it). Resolves to content_encoding_io.dart
// natively (bounded gzip/zlib decoding in an isolate) or the web stub
// (null bytes — the browser's fetch stack already decompressed), so
// `dart:io` never reaches the web build.
import 'dart:typed_data';

export 'content_encoding_stub.dart'
    if (dart.library.io) 'content_encoding_io.dart'
    show decodeContentEncoding, platformDecompressesTransparently;

/// Asynchronous platform decoder boundary used by NetworkService.
typedef ContentEncodingDecoder =
    Future<({Uint8List? bytes, bool exceededLimit})> Function(
      Uint8List bytes,
      String encoding, {
      required int maxOutputBytes,
    });
