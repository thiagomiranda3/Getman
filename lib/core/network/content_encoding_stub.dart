// Web counterpart of content_encoding_io.dart: always returns null ("keep
// the bytes as-is"). Correct on web because the browser's fetch stack
// transparently decompresses any Content-Encoding it negotiated before dio
// ever sees the body — there is nothing left to decode.

import 'dart:typed_data';

/// On web the browser's fetch stack transparently decompresses ANY encoding
/// it negotiated (gzip/deflate/br/zstd) before dio sees the body — a
/// residual Content-Encoding header does NOT mean the bytes are compressed,
/// so the caller must keep them instead of showing an unsupported
/// placeholder.
const bool platformDecompressesTransparently = true;

/// Web no-op: the browser already decompressed the body, so this always
/// returns null and the caller keeps the received bytes unchanged.
Uint8List? decodeContentEncoding(Uint8List bytes, String encoding) => null;
