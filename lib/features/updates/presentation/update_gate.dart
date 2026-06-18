// Resolves to the real `updat`-driven gate on native platforms and to a no-op
// stub on web (where `dart:io` / `updat` are unavailable).
export 'update_gate_stub.dart' if (dart.library.io) 'update_gate_io.dart';
