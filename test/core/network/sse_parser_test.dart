import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/network/sse_parser.dart';

void main() {
  test('dispatches a data event on a blank line', () {
    final p = SseParser();
    expect(p.addChunk('data: hello\n\n'), ['hello']);
  });

  test('joins multiple data lines within one event', () {
    final p = SseParser();
    expect(p.addChunk('data: line1\ndata: line2\n\n'), ['line1\nline2']);
  });

  test('handles events split across chunks', () {
    final p = SseParser();
    expect(p.addChunk('data: par'), isEmpty);
    expect(
      p.addChunk('tial\n'),
      isEmpty,
    ); // line complete, event not dispatched yet
    expect(p.addChunk('\n'), ['partial']);
  });

  test('ignores event/id/comment lines', () {
    final p = SseParser();
    expect(p.addChunk(': comment\nevent: ping\nid: 1\ndata: payload\n\n'), [
      'payload',
    ]);
  });

  test('tolerates CRLF line endings', () {
    final p = SseParser();
    expect(p.addChunk('data: x\r\n\r\n'), ['x']);
  });

  test('multiple events in one chunk', () {
    final p = SseParser();
    expect(p.addChunk('data: a\n\ndata: b\n\n'), ['a', 'b']);
  });

  test('flush emits a final event that never got a trailing blank line', () {
    final p = SseParser();
    expect(
      p.addChunk('data: last\n'),
      isEmpty,
    ); // line complete, no blank line yet
    expect(p.flush(), ['last']);
  });

  test('flush folds a trailing data line with no newline at all', () {
    final p = SseParser();
    expect(
      p.addChunk('data: tail'),
      isEmpty,
    ); // no newline -> buffered in carry
    expect(p.flush(), ['tail']);
  });

  test('flush returns nothing when there is no buffered data', () {
    final p = SseParser();
    expect(p.addChunk('data: done\n\n'), ['done']);
    expect(p.flush(), isEmpty);
  });
}
