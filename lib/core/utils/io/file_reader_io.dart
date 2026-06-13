import 'dart:io';

/// Native implementation — reads the file at [path] synchronously.
List<int> readFileBytesSync(String path) => File(path).readAsBytesSync();
