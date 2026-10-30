// Platform-selected lazy script runtime factory.
export 'package:getman/features/scripting/data/runtime/quickjs_runtime_io.dart'
    if (dart.library.js_interop) 'package:getman/features/scripting/data/runtime/quickjs_runtime_web.dart';
