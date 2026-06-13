// Reads a file's bytes from a filesystem path. Backed by `dart:io` on native
// platforms and a throwing stub on web (where filesystem paths don't exist —
// file-backed request bodies are a desktop/mobile feature). Resolved via a
// conditional import so `dart:io` never leaks into the web build.
export 'file_reader_stub.dart' if (dart.library.io) 'file_reader_io.dart';
