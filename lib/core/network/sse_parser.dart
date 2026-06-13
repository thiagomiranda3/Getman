/// Incremental parser for Server-Sent Events. Feed it raw chunks; it returns
/// the `data` payload of each completed event (dispatched on a blank line).
/// `event:` / `id:` / `retry:` / comment lines are ignored in this v1.
class SseParser {
  final StringBuffer _data = StringBuffer();
  String _carry = '';

  /// Adds a decoded text [chunk], returning any events completed by it.
  List<String> addChunk(String chunk) {
    final events = <String>[];
    _carry += chunk;
    final parts = _carry.split('\n');
    // The last element has no trailing newline yet — keep it for the next chunk.
    _carry = parts.removeLast();
    for (final raw in parts) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty) {
        if (_data.isNotEmpty) {
          events.add(_data.toString());
          _data.clear();
        }
      } else if (line.startsWith('data:')) {
        var value = line.substring(5);
        if (value.startsWith(' ')) value = value.substring(1);
        if (_data.isNotEmpty) _data.write('\n');
        _data.write(value);
      }
      // Other field lines (event:/id:/retry:) and comments (:) are ignored.
    }
    return events;
  }
}
