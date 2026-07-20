// Web half of the file_reader.dart conditional export: there is no
// filesystem path to read from in the browser, so both entry points throw.

/// Web stub — there is no filesystem path to read from in the browser.
List<int> readFileBytesSync(String path) => throw UnsupportedError(
  'File-backed request bodies are not supported on web',
);

/// Web stub — file-backed request bodies are a desktop/mobile feature.
Future<List<int>> readFileBytes(String path) => throw UnsupportedError(
  'File-backed request bodies are not supported on web',
);
