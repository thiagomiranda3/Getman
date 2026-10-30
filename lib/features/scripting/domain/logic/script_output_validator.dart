// Validates the JSON-only guest boundary before proposals reach persistence or
// networking. Engine output is data, never authority to bypass phase limits.
import 'dart:convert';

import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/network/http_methods.dart';
import 'package:getman/features/scripting/domain/entities/script_error.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_log_entry.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/entities/script_patch.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/entities/script_request_patch.dart';
import 'package:getman/features/scripting/domain/entities/script_test_result.dart';

ScriptOutput decodeScriptOutput(
  String raw,
  ScriptInput input,
  ScriptLimits limits,
) {
  ScriptOutput failure(ScriptErrorKind kind, String message) => ScriptOutput(
    error: ScriptError(kind: kind, message: message, phase: input.phase),
  );
  if (utf8.encode(raw).length > limits.outputBytes) {
    return failure(
      ScriptErrorKind.outputTooLarge,
      'Script output exceeds limit',
    );
  }
  try {
    final data = _object(jsonDecode(raw));
    final temporary = _strings(data['temporaryVariables']);
    final env = _object(data['environmentPatch']);
    final environmentPatch = ScriptPatch(
      sets: _strings(env['sets']),
      unsets: _keys(env['unsets']),
    );
    if (input.environmentId == null && !environmentPatch.isEmpty) {
      throw const FormatException();
    }
    final patch = _object(data['requestPatch']);
    final requestPatch = ScriptRequestPatch(
      url: _optionalString(patch['url']),
      method: _optionalString(patch['method']),
      body: _optionalString(patch['body']),
      headerSets: _strings(patch['headerSets']),
      headerUnsets: _keys(patch['headerUnsets']),
    );
    if (input.phase == ScriptPhase.postResponse && !requestPatch.isEmpty) {
      throw const FormatException();
    }
    if (requestPatch.method != null &&
        !HttpMethods.all.contains(requestPatch.method)) {
      throw const FormatException();
    }
    if (requestPatch.body != null && input.config.bodyType != BodyType.raw) {
      throw const FormatException();
    }
    final headerNames = requestPatch.headerSets.keys
        .map((key) => key.toLowerCase())
        .toSet();
    if (headerNames.length != requestPatch.headerSets.length ||
        requestPatch.headerUnsets.any(
          (key) => headerNames.contains(key.toLowerCase()),
        )) {
      throw const FormatException();
    }
    final testsRaw = data['tests'];
    final logsRaw = data['logs'];
    if (testsRaw is! List ||
        logsRaw is! List ||
        testsRaw.length > limits.testCount ||
        logsRaw.length > limits.logEntries) {
      throw const FormatException();
    }
    final ids = <String>{};
    final tests = testsRaw.map((value) {
      final item = _object(value);
      if (item['id'] is! String ||
          item['name'] is! String ||
          item['passed'] is! bool ||
          !ids.add(item['id'] as String)) {
        throw const FormatException();
      }
      return ScriptTestResult(
        id: item['id'] as String,
        name: item['name'] as String,
        phase: input.phase,
        passed: item['passed'] as bool,
        message: _optionalString(item['message']),
      );
    }).toList();
    var logBytes = 0;
    final logs = logsRaw.map((value) {
      final item = _object(value);
      if (!const ['log', 'info', 'warn', 'error'].contains(item['level']) ||
          item['message'] is! String) {
        throw const FormatException();
      }
      final message = item['message'] as String;
      logBytes += utf8.encode(message).length;
      return ScriptLogEntry(
        level: item['level'] as String,
        message: message,
        phase: input.phase,
      );
    }).toList();
    if (logBytes > limits.logBytes) throw const FormatException();
    ScriptError? error;
    if (data['error'] != null) {
      final item = _object(data['error']);
      if (item['message'] is! String || item['kind'] is! String) {
        throw const FormatException();
      }
      final kind = ScriptErrorKind.values.byName(item['kind'] as String);
      error = ScriptError(
        kind: kind,
        message: item['message'] as String,
        phase: input.phase,
      );
    }
    return ScriptOutput(
      temporaryVariables: temporary,
      environmentPatch: environmentPatch,
      requestPatch: requestPatch,
      tests: tests,
      logs: logs,
      error: error,
      secretValues: _keys(data['secretValues'] ?? const <String>[]),
    );
  } on Object {
    return failure(ScriptErrorKind.runtime, 'Invalid script output');
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException();
  return value;
}

Map<String, String> _strings(Object? value) {
  final result = <String, String>{};
  for (final entry in _object(value).entries) {
    if (entry.value is! String) throw const FormatException();
    result[entry.key] = entry.value as String;
  }
  return result;
}

Set<String> _keys(Object? value) {
  if (value is! List || value.any((element) => element is! String)) {
    throw const FormatException();
  }
  return value.cast<String>().toSet();
}

String? _optionalString(Object? value) {
  if (value != null && value is! String) throw const FormatException();
  return value as String?;
}
