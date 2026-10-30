import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final builder = CBuilder.library(
      name: 'getman_quickjs',
      assetName: 'getman_quickjs.dart',
      sources: [
        'src/bridge.c',
        'src/quickjs.c',
        'src/libregexp.c',
        'src/libunicode.c',
        'src/dtoa.c',
      ],
      // QuickJS-NG and bridge cancellation both require C11 atomics. Match
      // upstream CMake's MSVC opt-in, including clang-cl's MSVC frontend.
      std: 'c11',
      flags: [
        if (input.config.code.targetOS == OS.windows)
          '/experimental:c11atomics',
      ],
      defines: {
        if (input.config.code.targetOS != OS.windows) '_GNU_SOURCE': null,
      },
    );
    await builder.run(input: input, output: output);
  });
}
