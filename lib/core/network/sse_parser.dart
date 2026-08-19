// SseParser: incremental Server-Sent-Events parser. Feed it raw decoded
// text chunks via addChunk; it buffers partial lines/data across chunk
// boundaries and returns each event's `data` payload once a blank line
// dispatches it. Call flush() on stream end to recover a final event that
// never got its trailing blank line. Per the WHATWG spec: CRLF, lone CR,
// and LF all terminate lines (a chunk-final CR stays buffered so a CRLF
// split across chunks is one terminator, not CR + a phantom blank line);
// a colon-less line is a field with an empty value; an empty `data:`
// value still contributes a segment to the newline join. `event:`/`id:`/
// `retry:` fields and comment lines are ignored in this v1. Buffered text
// is capped at kSseMaxBufferedChars — overflow drops the buffers and
// returns a bracketed truncation marker as the event text.

import 'package:flutter/foundation.dart';
import 'package:getman/core/utils/byte_format.dart';

/// Hard cap on the text buffered while an event is still incomplete (the
/// partial line carry + the accumulated `data:` payload), in UTF-16 code
/// units. A server that never sends a line terminator — or a maliciously
/// huge event — would otherwise grow the buffers (and the per-chunk line
/// rescan) without bound. 4 MiB comfortably exceeds any SSE payload this
/// client renders while keeping the rescan cost per chunk bounded.
const int kSseMaxBufferedChars = 4 * 1024 * 1024;

/// Incremental parser for Server-Sent Events. Feed it raw chunks; it returns
/// the `data` payload of each completed event (dispatched on a blank line).
/// `event:` / `id:` / `retry:` / comment lines are ignored in this v1.
class SseParser {
  /// `maxBufferedChars` shrinks the overflow cap so tests can exercise it
  /// without multi-MiB fixtures; production callers use the default.
  SseParser({@visibleForTesting this._maxBufferedChars = kSseMaxBufferedChars});

  final int _maxBufferedChars;
  final StringBuffer _data = StringBuffer();

  /// Whether any `data` field was seen for the pending event. Tracked
  /// separately from `_data.isNotEmpty` so an empty-valued `data:` line still
  /// registers (it contributes an empty segment to the newline join, and an
  /// event whose only data line is empty dispatches an empty string).
  bool _hasData = false;
  String _carry = '';

  static const int _cr = 0x0D; // '\r'
  static const int _lf = 0x0A; // '\n'

  /// Adds a decoded text [chunk], returning any events completed by it.
  List<String> addChunk(String chunk) {
    final events = <String>[];
    _carry += chunk;
    var start = 0;
    var i = 0;
    while (i < _carry.length) {
      final code = _carry.codeUnitAt(i);
      if (code == _lf) {
        _consumeLine(_carry.substring(start, i), events);
        i += 1;
        start = i;
      } else if (code == _cr) {
        // A chunk-final CR may be the first half of a CRLF — keep it in the
        // carry so the LF opening the next chunk doesn't read as a phantom
        // blank line.
        if (i + 1 == _carry.length) break;
        _consumeLine(_carry.substring(start, i), events);
        i += _carry.codeUnitAt(i + 1) == _lf ? 2 : 1;
        start = i;
      } else {
        i += 1;
      }
    }
    _carry = _carry.substring(start);
    // Cap AFTER consuming complete lines: only text still waiting on a
    // terminator/dispatch counts, so a large chunk of small events is fine.
    if (_carry.length + _data.length > _maxBufferedChars) {
      _carry = '';
      _data.clear();
      _hasData = false;
      events.add(
        '[SSE event exceeded ${formatBytes(_maxBufferedChars)} — '
        'stream truncated]',
      );
    }
    return events;
  }

  /// Flushes any buffered event when the stream ends without a trailing blank
  /// line. Call once on the stream's `onDone`. A server that closes right after
  /// `data:` would otherwise lose its last event.
  List<String> flush() {
    final events = <String>[];
    if (_carry.isNotEmpty) {
      // At stream end a held trailing CR is a complete terminator (there is
      // no next chunk whose LF could pair with it), so strip it — the text
      // before it (possibly none: a blank line) is the final line.
      final line = _carry.endsWith('\r')
          ? _carry.substring(0, _carry.length - 1)
          : _carry;
      _consumeLine(line, events);
      _carry = '';
    }
    if (_hasData) {
      events.add(_data.toString());
      _data.clear();
      _hasData = false;
    }
    return events;
  }

  void _consumeLine(String line, List<String> events) {
    if (line.isEmpty) {
      if (_hasData) {
        events.add(_data.toString());
        _data.clear();
        _hasData = false;
      }
      return;
    }
    // Per spec, a colon-less line is a field name with an empty value, and a
    // leading-colon comment parses as an empty field name (ignored below).
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'data') {
      if (_hasData) _data.write('\n');
      _data.write(value);
      _hasData = true;
    }
    // Other field lines (event:/id:/retry:) and comments are ignored.
  }
}
