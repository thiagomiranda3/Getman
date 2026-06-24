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
  if (b == null || b.length < 2) return null;
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
  'application/xhtml+xml': 'html',
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
