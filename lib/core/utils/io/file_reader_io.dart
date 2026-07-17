// Native (dart:io) half of the file_reader.dart conditional export: reads
// file bytes for binary/multipart request bodies on desktop/mobile.

import 'dart:io';

/// Native implementation — reads the file at [path] synchronously.
List<int> readFileBytesSync(String path) => File(path).readAsBytesSync();

/// Native implementation — reads the file at [path] off the calling event-loop
/// turn (the OS read happens on a background thread), so a large upload never
/// stalls the UI isolate during request assembly.
Future<List<int>> readFileBytes(String path) => File(path).readAsBytes();
