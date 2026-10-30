// Typed native-assets bindings. A control is owned until worker completion.
import 'dart:ffi';
import 'package:ffi/ffi.dart';

// Host-only ownership diagnostics; no JavaScript capability is exposed.
@Native<Int Function()>(symbol: 'gm_live_controls')
external int liveControls();
@Native<Int Function()>(symbol: 'gm_live_runtimes')
external int liveRuntimes();

@Native<Pointer<Void> Function()>(symbol: 'gm_control_new')
external Pointer<Void> controlNew();
@Native<Void Function(Pointer<Void>)>(symbol: 'gm_cancel')
external void cancel(Pointer<Void> control);
@Native<Void Function(Pointer<Void>)>(symbol: 'gm_control_free')
external void controlFree(Pointer<Void> control);
@Native<Int Function(Pointer<Void>)>(symbol: 'gm_status')
external int status(Pointer<Void> control);
@Native<Pointer<Utf8> Function(Pointer<Void>)>(symbol: 'gm_message')
external Pointer<Utf8> message(Pointer<Void> control);
@Native<Pointer<Utf8> Function(Pointer<Void>)>(symbol: 'gm_diagnostics')
external Pointer<Utf8> diagnostics(Pointer<Void> control);
@Native<
  Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Int, Int64, Int)
>(symbol: 'gm_eval')
external void evaluate(
  Pointer<Void> control,
  Pointer<Utf8> source,
  Pointer<Utf8> filename,
  int timeout,
  int memory,
  int outputLimit,
);

(int, String, String) evaluateAddress(
  int address,
  String source,
  String filename,
  int timeout,
  int memory,
  int outputLimit,
) {
  final pointer = Pointer<Void>.fromAddress(address);
  final code = source.toNativeUtf8();
  final name = filename.toNativeUtf8();
  try {
    evaluate(pointer, code, name, timeout, memory, outputLimit);
    return (
      status(pointer),
      message(pointer).toDartString(),
      diagnostics(pointer).toDartString(),
    );
  } finally {
    calloc
      ..free(code)
      ..free(name);
  }
}
