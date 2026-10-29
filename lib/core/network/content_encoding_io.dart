// Native Content-Encoding decoders for NetworkService's response path.
// dart:io auto-decompresses ONLY an exactly-'gzip' (lowercase) header value;
// 'GZIP', 'x-gzip', and 'deflate' bodies arrive as raw compressed bytes, so
// they are decoded here in a worker isolate with a bounded output sink.
// Contract: null bytes on malformed input keeps the original bytes as-is;
// exceededLimit instead rejects expansion without retaining a partial body.
// The null path is load-bearing: it is exactly how
// an already-decompressed-by-dart:io gzip body (which fails to decode a
// second time) avoids double decompression.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Native platforms do NOT transparently decompress every negotiated
/// Content-Encoding (dart:io handles only exactly-lowercase 'gzip'), so an
/// unsupported residual encoding (br/zstd) really is undecodable here and
/// the caller must surface its placeholder.
const bool platformDecompressesTransparently = false;

/// Decodes [bytes] per the lowercased Content-Encoding token [encoding]
/// (`gzip` / `x-gzip` / `deflate`) outside the UI isolate. A null decoded byte
/// result means "keep the input" unless `exceededLimit` is true, in which
/// case callers must discard the response and show their too-large placeholder.
///
/// `deflate` tries the RFC 1950 zlib wrapper first, then falls back to a raw
/// RFC 1951 stream (some servers — historically IIS — send raw deflate under
/// `Content-Encoding: deflate`).
Future<({Uint8List? bytes, bool exceededLimit})> decodeContentEncoding(
  Uint8List bytes,
  String encoding, {
  required int maxOutputBytes,
}) => Isolate.run(() => _decode(bytes, encoding, maxOutputBytes));

({Uint8List? bytes, bool exceededLimit}) _decode(
  Uint8List bytes,
  String encoding,
  int maxOutputBytes,
) {
  try {
    Uint8List? decoded;
    switch (encoding) {
      case 'gzip':
      case 'x-gzip':
        decoded = _decodeBounded(bytes, gzip.decoder, maxOutputBytes);
      case 'deflate':
        try {
          decoded = _decodeBounded(bytes, zlib.decoder, maxOutputBytes);
        } on FormatException {
          // Only invalid format may retry as raw deflate. Overflow must
          // escape immediately, never become a retry or a successful null.
          decoded = _decodeBounded(
            bytes,
            ZLibDecoder(raw: true),
            maxOutputBytes,
          );
        }
    }
    return (bytes: decoded, exceededLimit: false);
  } on _OutputLimitExceeded {
    return (bytes: null, exceededLimit: true);
  } on FormatException {
    return (bytes: null, exceededLimit: false);
  }
}

Uint8List _decodeBounded(
  Uint8List bytes,
  ZLibDecoder decoder,
  int maxOutputBytes,
) {
  final output = _BoundedOutputSink(maxOutputBytes);
  final input = decoder.startChunkedConversion(output);
  try {
    // The SDK delivers native output blocks to the sink as it inflates.
    // Throwing from add stops inflation before later blocks are allocated.
    input.add(bytes);
  } finally {
    input.close();
  }
  return output.builder.takeBytes();
}

class _OutputLimitExceeded implements Exception {}

class _BoundedOutputSink extends ByteConversionSinkBase {
  _BoundedOutputSink(this.maxBytes);

  final int maxBytes;
  final BytesBuilder builder = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (chunk.length > maxBytes - builder.length) {
      throw _OutputLimitExceeded();
    }
    builder.add(chunk);
  }

  @override
  void close() {}
}
