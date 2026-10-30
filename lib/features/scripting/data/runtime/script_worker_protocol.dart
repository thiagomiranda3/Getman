// JSON-only snapshots exchanged with the QuickJS guest on either platform.
import 'dart:convert';

import 'package:getman/core/network/http_methods.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';

String encodeScriptInput(ScriptInput input, ScriptLimits limits) => jsonEncode({
  'executionId': input.executionId,
  'phase': input.phase.name,
  'environmentId': input.environmentId,
  'secretKeys': input.secretKeys.toList(),
  'environment': input.environmentVariables,
  'collection': input.collectionVariables,
  'temporary': input.temporaryVariables,
  'request': {
    'url': input.config.url,
    'method': input.config.method,
    'body': input.config.body,
    'bodyType': input.config.bodyType.name,
    'headers': input.config.enabledHeaders,
  },
  'response': input.response == null
      ? null
      : {
          'status': input.response!.status,
          'durationMs': input.response!.durationMs,
          'text': input.response!.text,
          'headers': input.response!.headers,
        },
  'methods': HttpMethods.all,
  'limits': {
    'logEntries': limits.logEntries,
    'logBytes': limits.logBytes,
    'testCount': limits.testCount,
    'outputBytes': limits.outputBytes,
  },
});

// Bootstrap-caught errors travel in a successful engine envelope, so normalize
// their source location just like uncaught engine diagnostics in both adapters.
ScriptOutput normalizeScriptDiagnostics(ScriptOutput output, int lineOffset) {
  final error = output.error;
  if (error == null) return output;
  final match = RegExp(
    r'getman-[^:]+:(\d+)(?::(\d+))?',
  ).firstMatch(error.message);
  if (match == null) return output;
  final line = int.parse(match.group(1)!) - lineOffset;
  return output.copyWith(
    error: error.copyWith(
      line: line > 0 ? line : null,
      column: match.group(2) == null ? null : int.parse(match.group(2)!),
    ),
  );
}
