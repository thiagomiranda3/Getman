// Size limits and placeholder strings governing response-body memory/disk
// use: max bytes buffered from the network (kMaxRenderableResponseBytes),
// the 1 MiB Hive persistence cap and its placeholder, the large-viewer and
// syntax-highlighting thresholds, and the JSON-tree background-decode cutoff.

/// Largest response body we will buffer into memory to render. Beyond this the
/// stream is abandoned and the response carries no renderable body (an "open
/// externally" card is shown). Protects against pulling a huge video into RAM.
const int kMaxRenderableResponseBytes = 50 * 1024 * 1024; // 50 MiB

/// Response bodies larger than this are not persisted to disk (the in-memory
/// session keeps the full body). Serializing multi-MB strings into Hive runs
/// synchronously on the UI isolate and stalls every structural tab action.
const int kMaxPersistedResponseBodyChars = 1 << 20; // 1 MiB

/// Placeholder stored instead of an over-limit body.
const String kResponseBodyTooLargePlaceholder =
    '[response body over 1 MB was not persisted — re-send the request]';

/// Placeholder stored in a superseded time-travel entry when the user turned
/// "save large responses in history" off — distinct from
/// [kResponseBodyTooLargePlaceholder] because the cause (a setting) and the
/// threshold (the large-viewer size, not the 1 MiB persistence cap) differ.
const String kHistoryBodyNotKeptPlaceholder =
    '[large response body not kept in history — re-send the request]';

/// Whether [body] is one of the metadata-only body sentinels. Viewers use
/// this to render the sentinel as plain text (never prettified/highlighted)
/// and to exclude it from compare targets.
bool isResponseBodyPlaceholder(String? body) =>
    body == kResponseBodyTooLargePlaceholder ||
    body == kHistoryBodyNotKeptPlaceholder;

/// Bodies larger than this are rendered as plain text (no prettify, no
/// syntax highlighting) unless the user opts in — re_editor re-chunks and
/// highlights the whole document synchronously on the UI thread.
const int kLargeResponseViewerChars = 512 * 1024; // 512 KiB

/// In plain-text large mode, only this prefix is rendered until the user
/// asks for the full body.
const int kLargeResponsePreviewChars = 256 * 1024; // 256 KiB

/// JSON bodies at or below this size decode inline (sub-millisecond); larger
/// bodies decode in a background isolate via `compute()` so selecting TREE on a
/// big response never stalls the UI thread.
const int kTreeInlineDecodeLimit = 64 * 1024; // 64 KiB

/// Hard ceiling for highlighted/prettified rendering. Even when the user opts
/// into highlighting a large body (`alwaysPrettifyLargeResponses` or the
/// "PRETTIFY & SHOW" action), bodies over this size stay plain text — loading a
/// multi-MB string into re_editor rebuilds its line model synchronously on the
/// UI thread and freezes the app.
const int kMaxHighlightChars = 3 * 1024 * 1024; // 3 MiB

/// Whether a body of [chars] length may be loaded into the highlighted editor.
bool canHighlightBody(int chars) => chars <= kMaxHighlightChars;
