// Conditional-import seam for decodeContentEncoding — NetworkService's
// response-side Content-Encoding handling (gzip/deflate self-decompression
// when the platform didn't do it). Resolves to content_encoding_io.dart
// natively (dart:io gzip/zlib codecs) or content_encoding_stub.dart on web
// (always null — the browser's fetch stack already decompressed), so
// `dart:io` never reaches the web build.
export 'content_encoding_stub.dart'
    if (dart.library.io) 'content_encoding_io.dart'
    show decodeContentEncoding;
