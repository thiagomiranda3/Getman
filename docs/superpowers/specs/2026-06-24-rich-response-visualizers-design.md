# DL1 — Rich response visualizers (HTML / image / CSV / PDF + video & audio)

**Status:** Design approved (2026-06-24) — ready for implementation planning.
**Branch:** `feat/rich-response-visualizers` (off `dev`).
**Backlog item:** DL1 — "Rich response visualizers", extended with an embedded
video/audio player (mp4, mp3, and *any* video/audio format the player supports).

## Goal

When an API returns something other than JSON/text, render it usefully inside
the response panel instead of dumping (corrupted) text:

- **image** — png/jpg/gif/webp/bmp shown inline.
- **video / audio** — an embedded player that decodes virtually any format.
- **pdf** — inline document viewer.
- **csv** — parsed into a scrollable table.
- **html** — faithful preview (opened in the real browser) + source inline.
- **binary** (anything recognized-but-unviewable, e.g. zip) — a tidy card with
  type + size + **Save to file**, never garbled text.

Postman's response viewer is weak here; rich rendering is an on-strategy delight
differentiator.

## Locked decisions (from brainstorming)

1. **Live-render only — no binary persistence.** Media bytes live in memory for
   the current session. After an app restart, or for older entries in the
   response **time-travel history**, a binary response shows a "media not stored
   this session — re-send to view" placeholder. **No Hive schema change.** Fits
   the lightweight/local stance.
2. **media_kit for video/audio.** The only option that truly satisfies "any
   extension" (mp4/mkv/webm/mov, mp3/aac/flac/ogg, …) across macOS/Windows/Linux
   + web. Accepts a native libmpv dependency.
3. **HTML = open-in-browser, not an inline webview.** Desktop has no first-class
   webview; a real browser gives perfect fidelity with zero new deps (write bytes
   to a temp file via `path_provider`, launch via the existing `url_launcher`).
   Source stays viewable inline.
4. **PDF = `pdfx` inline** (native pdfium). Fallback if rejected later: treat PDF
   as the binary card (Save / open externally).
5. **CSV via the pure-Dart `csv` package** (tiny, no native code).
6. **~50 MB capture cap, enforced by streaming.** The body is read as a stream
   and accumulated up to the cap; if it exceeds the cap the request is cancelled
   and an "open externally" card is shown — so a giant video is never fully
   buffered into RAM. (`content-length`, when present, is an early-out so we
   don't even start.)

## Architecture

The mandatory change is at the **network layer**: responses must be captured as
**bytes**, not forced through a UTF-8 `String`. Everything else is pure-Dart
classification + a set of leaf viewer widgets that consume the captured bytes.

```
dio (ResponseType.stream)
        │  accumulate ≤ capBytes (else cancel → "too large" placeholder)
        ▼
NetworkService.request
   ├─ classify(contentType, url, sniffBytes)  ← lib/core/utils/response_media.dart (pure)
   ├─ textual  → utf8.decode → HttpResponseEntity.body (String, as today)
   └─ non-text → keep bytes → HttpResponseEntity.bodyBytes + placeholder body
        ▼
HttpResponseEntity { statusCode, body, bodyBytes?, headers, durationMs }
        ▼
ResponseBodyView  ← resolves ResponseMediaKind once per response
   ├─ textual → existing PRETTY/RAW/TREE toggle (UNCHANGED)
   └─ media   → viewers/  (PREVIEW / RAW toggle; RAW = binary card)
        ├─ ImageResponseView      (Image.memory)
        ├─ MediaResponseView      (media_kit; video + audio)
        ├─ PdfResponseView        (pdfx)
        ├─ CsvResponseView        (csv → table)
        ├─ HtmlResponseView       (source + "Open in browser")
        └─ BinaryResponseView     (type + size + Save)
```

### Component 1 — `lib/core/utils/response_media.dart` (pure Dart)

- `enum ResponseMediaKind { textual, image, pdf, html, csv, video, audio, binary }`
- `ResponseMediaKind classify({String? contentType, String? url, Uint8List? sniffBytes})`
  - Resolution order: **Content-Type** (lower-cased, stripped of `; charset=…`
    and other params) → **URL file-extension** fallback → **magic-byte sniff**
    (only when content-type is missing or `application/octet-stream`).
  - `textual` covers `application/json`, `text/*` (except `text/csv`/`text/html`),
    `application/xml`, `application/javascript`, `application/*+json`, etc. —
    i.e. exactly today's text path.
  - Magic-byte sniff: PDF `%PDF`, PNG `\x89PNG`, JPEG `\xFF\xD8`, GIF `GIF8`,
    WEBP `RIFF…WEBP`, etc. Conservative; unknown → `binary`.
- Helper `String? mediaExtension(String? contentType, String? url)` → a sensible
  file extension for Save-to-file and the media temp-file name.
- No Flutter import; thoroughly unit-tested.

### Component 2 — `HttpResponseEntity` + `NetworkService` (bytes capture)

`HttpResponseEntity` (`lib/core/network/http_response.dart`):
- Add `final Uint8List? bodyBytes;` (default null).
- **Equality:** `bodyBytes` is **excluded** from `props` (a list compare on
  multi-MB buffers every rebuild is unacceptable); instead include a cheap
  discriminator `bodyBytes?.length` in `props`. Two media responses of identical
  length+headers+placeholder comparing equal is acceptable (re-send replaces the
  whole entity anyway).
- `copyWithBody(String)` keeps clearing/keeping `bodyBytes` per its existing
  contract (the over-limit text placeholder swap is textual-only; it leaves
  `bodyBytes` null).

`NetworkService.request` (`lib/core/network/network_service.dart`):
- Request with `ResponseType.stream` (precedent: `realtime_service.dart`).
- **Early-out:** if the `content-length` header is present and exceeds
  `capBytes` (~50 MB), don't read the stream at all — set `bodyBytes = null`,
  `body =` a placeholder noting type + size + "too large to buffer", and bail.
- Otherwise **accumulate** the stream chunks into a `BytesBuilder`, tracking a
  running total; if it crosses `capBytes` mid-stream, cancel the request (cancel
  token) and fall back to the same "too large" placeholder. This is what makes
  the cap a real memory guard — a giant body is never fully buffered.
- Once the bytes are assembled (under cap), read `content-type` from headers and
  classify:
  - **textual:** `utf8.decode(bytes, allowMalformed: true)` → `body`; `bodyBytes`
    stays null. (Same raw string the UI prettifies today; JSON pretty/Tree
    unaffected.)
  - **non-text:** `bodyBytes = bytes`; `body =` human-readable placeholder, e.g.
    `[binary video/mp4 · 12.4 MB]`.
- `_stringifyBody` is removed/replaced by this branch. The previous
  `compute`-based JSON re-encode is no longer needed (textual bodies come back
  verbatim from the decoded bytes).
- Empty body → `body = ''`, `bodyBytes = null`, kind `textual` (unchanged).
- The cap-exceeded fallback still returns a normal `HttpResponseEntity` (real
  status/headers/duration) — it is **not** a `NetworkFailure`; the response just
  carries no renderable body.

### Component 3 — viewers (`lib/features/tabs/presentation/widgets/response/viewers/`)

Each is a small widget taking `Uint8List bytes` (+ content-type / suggested
filename where useful), themed via `context.app*`:

- `ImageResponseView` — `Image.memory(bytes)` centered in a scroll/zoom-friendly
  container; decode errors fall through to the binary card.
- `MediaResponseView` — owns a media_kit `Player` + `VideoController`; writes
  `bytes` to a temp file (`path_provider`) once, opens it, disposes both on
  unmount. Audio uses the same player with a compact transport (no video
  surface). Degrades to "playback unavailable on this platform — Save to file"
  if the player can't initialize (e.g. missing Linux libmpv).
- `PdfResponseView` — `pdfx` `PdfController` from `bytes`; paged/scroll view.
- `CsvResponseView` — `csv` package parse → a virtualized table; large CSVs cap
  rows with a "showing first N rows" note.
- `HtmlResponseView` — inline source (selectable text) + an **"OPEN IN BROWSER"**
  button: write bytes to a temp `.html` file, `url_launcher` opens it.
- `BinaryResponseView` — the fallback card: content-type, byte size, **Save to
  file** (correct extension from `mediaExtension`).

### Component 4 — `ResponseBodyView` integration

`ResponseBodyView` (`response_body_view.dart`):
- Compute `ResponseMediaKind` once when the response changes from
  `response.headers['content-type']` + the request URL (`tab.config.url`) +
  `response.bodyBytes` as the optional sniff input. **Headers are persisted**, so
  this classifies correctly on a restored tab even though `bodyBytes` is null —
  which is exactly what drives the live-only placeholder below.
- **`textual`** → the existing `_buildSmallMode` / `_buildLargeMode` paths,
  PRETTY/RAW/TREE — **left untouched**, including the >`kLargeResponseViewerChars`
  large-text handling.
- **media kinds** → a thin shell with a **PREVIEW / RAW** segmented toggle
  (matching the existing `_BodyModeToggle` style/keys):
  - PREVIEW → the matching viewer (or the null-bytes placeholder).
  - RAW → `BinaryResponseView` card (size + Save) — never garbled text.
- **Live-only placeholder:** when `response.bodyBytes == null` but the kind is a
  media kind (restored tab / older time-travel entry), show "Media not stored
  this session — re-send to view" with the type/size pulled from the placeholder
  `body`.

### Component 5 — Save-to-file for bytes

The current `saveJsonFileWithFeedback` is text-oriented. Add a sibling
`saveBytesFileWithFeedback(...)` in `core/utils/json_file_io.dart` (or a small
new `file_io` helper) for arbitrary bytes, picking the extension from
`mediaExtension`. Reuses the existing picker/snackbar plumbing.

## Persistence

**Unchanged.** Hive continues to store the text `body` (now a short placeholder
string for media responses) on `HttpRequestTabModel` and `StoredResponseModel`.
`bodyBytes` is never persisted. No `@HiveType`/`@HiveField` change, no
`build_runner` run, no typeId churn.

## Platform notes

- **macOS / Windows:** happy path; media_kit + pdfx bundle their native libs.
- **Linux:** media_kit needs libmpv at runtime — same class of bundling concern
  as the dropped GStreamer/AppImage item. `MediaResponseView` degrades gracefully
  ("playback unavailable — Save to file") when the player fails to initialize;
  Save and all other viewers still work. Bundling libmpv into the AppImage is
  **out of scope** for this spec (future packaging task if desired).
- **Web:** secondary / best-effort. Media uses a blob URL instead of a temp file;
  pdfx/image work from bytes. The build must not break — any viewer that can't
  run on web degrades to the binary card. Conditional imports where a viewer
  pulls `dart:io`.

## Testing

- **Unit** (`test/core/utils/response_media_test.dart`): `classify(...)` across
  content-types, URL extensions, the octet-stream sniff path, and charset-param
  stripping; `mediaExtension(...)`.
- **Unit** (`test/core/network/network_service_*_test.dart`): textual-vs-binary
  capture branch with a mocked dio adapter (returns a byte stream); the
  `content-length` early-out and the mid-stream accumulation cap both set the
  "too large" placeholder + null bytes (and the latter cancels); empty body
  unchanged; malformed UTF-8 in a textual body decodes without throwing.
- **Widget**: `ImageResponseView` renders from bytes; `CsvResponseView` builds a
  table from sample CSV (incl. quoted/escaped fields); `BinaryResponseView` shows
  size + Save; `ResponseBodyView` routes by kind and shows the null-bytes
  placeholder when `bodyBytes == null`.
- media_kit / pdfx actual playback/render are **not** unit-tested (native);
  we test routing, the placeholder, and the graceful-degradation path with fakes.

## Implementation phasing (for the plan)

Foundation first, cheapest wins next, heaviest deps last. Each phase is
independently shippable and leaves analyze/lint/tests green.

1. **Foundation:** `response_media.dart` classifier + `HttpResponseEntity.bodyBytes`
   + `NetworkService` bytes capture + the 50 MB guard + `ResponseBodyView` routing
   shell + `ImageResponseView` + `BinaryResponseView` + bytes Save. (Proves the
   whole pipeline with zero new native deps.)
2. **CSV + HTML:** `CsvResponseView` (`csv` pkg) + `HtmlResponseView`
   (open-in-browser).
3. **PDF:** `pdfx` + `PdfResponseView`.
4. **Video / audio:** media_kit + `MediaResponseView`, including the
   graceful-degradation path.

## Out of scope (explicit)

- Persisting media bytes across restarts / into history (locked: live-only).
- Streaming very large media from the original URL (the 50 MB guard punts to
  "open externally"); a future enhancement.
- Bundling libmpv into the Linux AppImage (separate packaging task).
- SVG rendering (would need `flutter_svg`); SVG falls to the binary card for now.
- Inline HTML rendering via a webview or `flutter_widget_from_html`.

## Wiki

The response-panel wiki page must gain a short "Rich response previews" section
(image/video/audio/pdf/csv/html viewers, the PREVIEW/RAW toggle, live-only
caveat) as part of this work — per the CLAUDE.md §7 keep-the-wiki-in-sync mandate.
