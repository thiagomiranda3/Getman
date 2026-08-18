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

  test('lone-CR line endings dispatch live events', () {
    final p = SseParser();
    // Regression: CR-only streams used to buffer everything until close and
    // then surface one garbled event via flush().
    expect(p.addChunk('data: a\r\rdata: b\r\r'), ['a']);
    // The chunk-final CR is held (it could be half a CRLF); the next chunk
    // resolves it as the blank line dispatching the second event.
    expect(p.addChunk('data: c\r\rdata: d'), ['b', 'c']);
    expect(p.flush(), ['d']);
  });

  test('CRLF split across chunks is one terminator, not CR + blank line', () {
    final p = SseParser();
    // The chunk-final CR is held: it may be the first half of a CRLF.
    expect(p.addChunk('data: a\r'), isEmpty);
    // A phantom blank line after the CR would have dispatched 'a' alone;
    // both lines must join into one event instead.
    expect(p.addChunk('\ndata: b\r\n\r\n'), ['a\nb']);
  });

  test('blank-line CRLF split across chunks dispatches once resolved', () {
    final p = SseParser();
    expect(p.addChunk('data: x\r\n\r'), isEmpty); // trailing CR held
    expect(p.addChunk('\n'), ['x']);
  });

  test('flush treats a held stream-final CR as a complete terminator', () {
    final p = SseParser();
    expect(p.addChunk('data: x\r\n\r'), isEmpty);
    expect(p.flush(), ['x']); // the held CR was the blank line's terminator
  });

  test('a colon-less line is a field with an empty value', () {
    final p = SseParser();
    // Bare `retry` is ignored like `retry: ...`; bare `data` contributes an
    // empty segment to the newline join (WHATWG: whole line = field name,
    // empty string = field value).
    expect(p.addChunk('retry\ndata\ndata: x\n\n'), ['\nx']);
  });

  test('data: with an empty value contributes an empty join segment', () {
    final p = SseParser();
    expect(p.addChunk('data:\ndata: b\n\n'), ['\nb']);
    expect(p.addChunk('data: a\ndata:\n\n'), ['a\n']);
  });

  test('an event whose only data line is empty dispatches an empty string', () {
    final p = SseParser();
    // WHATWG: the buffer holds '\n', the trailing LF is stripped at dispatch,
    // and a non-empty buffer means the (empty-data) event still fires.
    expect(p.addChunk('data:\n\n'), ['']);
  });

  test('overflowing the buffer cap emits a truncation marker and resets', () {
    final p = SseParser(maxBufferedChars: 32);
    // No terminator ever arrives — without the cap this buffers forever.
    expect(p.addChunk('x' * 40), [
      '[SSE event exceeded 32 B — stream truncated]',
    ]);
    // Buffers were dropped: the parser keeps working afterwards.
    expect(p.addChunk('data: after\n\n'), ['after']);
    expect(p.flush(), isEmpty);
  });

  test('buffer cap covers accumulated data lines, not just the carry', () {
    final p = SseParser(maxBufferedChars: 16);
    expect(p.addChunk('data: 0123456789\n'), isEmpty); // 10 chars buffered
    expect(p.addChunk('data: 0123456789\n'), [
      '[SSE event exceeded 16 B — stream truncated]',
    ]);
    expect(p.flush(), isEmpty);
  });

  test('a large chunk of many complete events does not trip the cap', () {
    final p = SseParser(maxBufferedChars: 16);
    // The chunk (27 chars) exceeds the cap, but only text still waiting on a
    // terminator/dispatch counts against it.
    expect(p.addChunk('data: a\n\ndata: b\n\ndata: c\n\n'), ['a', 'b', 'c']);
  });
}
