// Indexes large response text into bounded layout chunks, preferring newline
// boundaries and never splitting UTF-16 surrogate pairs or CRLF sequences.
// Runs through compute() in LargeResponseTextView; offsets avoid retaining a
// second full copy of the response. This is a layout bound, not a body limit.

/// Maximum UTF-16 code units sent to one text layout (including long JSON
/// strings and minified bodies with no newlines).
const int kResponseTextChunkChars = 4096;

/// Exclusive chunk ends; concatenating the corresponding substrings exactly
/// reconstructs [text]. Newlines are preferred so pretty JSON keeps its lines.
List<int> responseTextChunkEnds(String text) {
  final ends = <int>[];
  var start = 0;
  while (start < text.length) {
    var end = (start + kResponseTextChunkChars).clamp(0, text.length);
    if (end < text.length) {
      // Scan only this chunk, never all the preceding text on a minified body.
      for (var i = end - 1; i >= start; i--) {
        if (text.codeUnitAt(i) == 10) {
          end = i + 1;
          break;
        }
      }
      final last = text.codeUnitAt(end - 1);
      if ((last >= 0xD800 && last <= 0xDBFF) ||
          (last == 13 && text.codeUnitAt(end) == 10)) {
        end--;
      }
    }
    ends.add(end);
    start = end;
  }
  return ends;
}
