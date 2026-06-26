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
