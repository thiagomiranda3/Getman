// Native Content-Encoding decoders for NetworkService's response path.
// dart:io auto-decompresses ONLY an exactly-'gzip' (lowercase) header value;
// 'GZIP', 'x-gzip', and 'deflate' bodies arrive as raw compressed bytes, so
// they are decoded here. Contract: return null on any failure and the caller
// keeps the bytes as-is — that null path is load-bearing, it is exactly how
// an already-decompressed-by-dart:io gzip body (which fails to decode a
// second time) avoids double decompression.

import 'dart:io';
import 'dart:typed_data';

/// Decodes [bytes] per the lowercased Content-Encoding token [encoding]
/// (`gzip` / `x-gzip` / `deflate`). Returns null for any other token or when
/// decoding fails — callers must treat null as "keep the bytes as-is".
///
/// `deflate` tries the RFC 1950 zlib wrapper first, then falls back to a raw
/// RFC 1951 stream (some servers — historically IIS — send raw deflate under
/// `Content-Encoding: deflate`).
Uint8List? decodeContentEncoding(Uint8List bytes, String encoding) {
  try {
    switch (encoding) {
      case 'gzip':
      case 'x-gzip':
        return Uint8List.fromList(gzip.decode(bytes));
      case 'deflate':
        try {
          return Uint8List.fromList(zlib.decode(bytes));
        } on Object catch (_) {
          return Uint8List.fromList(ZLibDecoder(raw: true).convert(bytes));
        }
      default:
        return null;
    }
  } on Object catch (_) {
    return null;
  }
}
