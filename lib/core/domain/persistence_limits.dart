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
