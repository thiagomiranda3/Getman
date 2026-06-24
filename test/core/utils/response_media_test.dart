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
      expect(
        classifyResponseMedia(contentType: 'application/json'),
        ResponseMediaKind.textual,
      );
      expect(
        classifyResponseMedia(contentType: 'text/plain'),
        ResponseMediaKind.textual,
      );
      expect(
        classifyResponseMedia(contentType: 'application/xml'),
        ResponseMediaKind.textual,
      );
    });
    test('image/video/audio/pdf/csv/html', () {
      expect(
        classifyResponseMedia(contentType: 'image/png'),
        ResponseMediaKind.image,
      );
      expect(
        classifyResponseMedia(contentType: 'video/mp4'),
        ResponseMediaKind.video,
      );
      expect(
        classifyResponseMedia(contentType: 'audio/mpeg'),
        ResponseMediaKind.audio,
      );
      expect(
        classifyResponseMedia(contentType: 'application/pdf'),
        ResponseMediaKind.pdf,
      );
      expect(
        classifyResponseMedia(contentType: 'text/csv'),
        ResponseMediaKind.csv,
      );
      expect(
        classifyResponseMedia(contentType: 'text/html'),
        ResponseMediaKind.html,
      );
    });
    test('known binary type → binary', () {
      expect(
        classifyResponseMedia(contentType: 'application/zip'),
        ResponseMediaKind.binary,
      );
    });
  });

  group('classifyResponseMedia fallbacks', () {
    test('octet-stream with no hints → textual (do not corrupt JSON)', () {
      expect(
        classifyResponseMedia(contentType: 'application/octet-stream'),
        ResponseMediaKind.textual,
      );
    });
    test('octet-stream falls through to URL extension', () {
      expect(
        classifyResponseMedia(
          contentType: 'application/octet-stream',
          url: 'https://x/y.mp4',
        ),
        ResponseMediaKind.video,
      );
    });
    test('no content-type → URL extension', () {
      expect(
        classifyResponseMedia(url: 'https://x/a.png'),
        ResponseMediaKind.image,
      );
    });
    test('magic bytes detect PDF / PNG / ZIP when no other hint', () {
      expect(
        classifyResponseMedia(
          sniffBytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
        ),
        ResponseMediaKind.pdf,
      );
      expect(
        classifyResponseMedia(
          sniffBytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
        ),
        ResponseMediaKind.image,
      );
      expect(
        classifyResponseMedia(
          sniffBytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]),
        ),
        ResponseMediaKind.binary,
      );
    });
    test('magic bytes detect short signatures (JPEG 3-byte, GZIP 2-byte)', () {
      // JPEG header is 3 bytes: [0xFF, 0xD8, 0xFF]
      expect(
        classifyResponseMedia(
          sniffBytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]),
        ),
        ResponseMediaKind.image,
      );
      // GZIP header is 2 bytes: [0x1F, 0x8B]
      expect(
        classifyResponseMedia(
          sniffBytes: Uint8List.fromList([0x1F, 0x8B]),
        ),
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
    test('xhtml+xml returns html extension', () {
      expect(
        mediaExtension(contentType: 'application/xhtml+xml'),
        'html',
      );
    });
  });
}
