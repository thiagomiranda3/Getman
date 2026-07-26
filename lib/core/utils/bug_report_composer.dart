// Composes the C5 "COPY AS BUG REPORT" markdown bundle: resolved request
// heading + curl block (CodeGenService's curl emitter with secret env
// values masked as •••) + response status/duration/size line + headers
// block + body block truncated at 50 KB. Pure Dart (no Flutter) so
// masking/truncation/format are unit-testable; the button in
// response_body_controls.dart gathers the live variable chain and calls
// compose().
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/byte_format.dart';
import 'package:getman/core/utils/code_gen_service.dart';
import 'package:getman/core/utils/environment_resolver.dart';

/// Composes a markdown bug-report bundle from the on-screen
/// request/response pair. `{{vars}}` resolve through `variables` with any
/// key in `secretKeys` masked as [kSecretMask] BEFORE resolution — so a
/// secret-sourced value never reaches the output, wherever it is
/// interpolated (URL, headers, auth, body). Unknown names stay verbatim
/// (the resolver's contract).
class BugReportComposer {
  BugReportComposer._();

  /// Mask substituted for any variable whose key is flagged secret.
  static const String kSecretMask = '•••';

  /// Body cap (characters) before the truncation note kicks in — 50 KB.
  static const int kBugReportBodyMaxChars = 50 * 1024;

  static String compose({
    required HttpRequestConfigEntity config,
    required HttpResponseEntity response,
    Map<String, String> variables = const {},
    Set<String> secretKeys = const {},
  }) {
    // Mask BEFORE resolving: every {{var}} occurrence sourced from a secret
    // key resolves to the mask, not the real value.
    final masked = <String, String>{
      for (final e in variables.entries)
        e.key: secretKeys.contains(e.key) ? kSecretMask : e.value,
    };
    String resolve(String value) => EnvironmentResolver.resolve(value, masked);

    final curl = CodeGenService.generate(
      config,
      CodeGenTarget.curl,
      resolve: resolve,
    );
    final size = formatBytes(responseSizeBytes(response));
    final headerLines = [
      for (final e in response.headers.entries) '${e.key}: ${e.value}',
    ].join('\n');

    final b = StringBuffer()
      ..writeln('### ${config.method} ${resolve(config.url)}')
      ..writeln()
      ..writeln('```')
      ..writeln(curl)
      ..writeln('```')
      ..writeln()
      ..writeln(
        '**Response:** ${response.statusCode} · '
        '${response.durationMs} ms · $size',
      )
      ..writeln();
    if (headerLines.isNotEmpty) {
      b
        ..writeln('```')
        ..writeln(headerLines)
        ..writeln('```')
        ..writeln();
    }
    b.write(_bodyBlock(response.body));
    return b.toString();
  }

  static String _bodyBlock(String body) {
    if (body.isEmpty) return '_(empty body)_\n';
    final truncated = body.length > kBugReportBodyMaxChars;
    final shown = truncated ? body.substring(0, kBugReportBodyMaxChars) : body;
    final note = truncated
        ? '\n(truncated: full size ${body.length} chars)'
        : '';
    return '```\n$shown$note\n```\n';
  }
}
