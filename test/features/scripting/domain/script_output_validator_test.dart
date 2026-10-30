import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/logic/script_output_validator.dart';

void main() {
  final input = ScriptInput(
    executionId: 'run',
    tabId: 'tab',
    source: '1;',
    phase: ScriptPhase.preRequest,
    config: const HttpRequestConfigEntity(id: 'request'),
  );
  Map<String, Object?> envelope() => {
    'temporaryVariables': <String, String>{},
    'environmentPatch': {'sets': <String, String>{}, 'unsets': <String>[]},
    'requestPatch': {
      'headerSets': <String, String>{},
      'headerUnsets': <String>[],
    },
    'tests': <Object>[],
    'logs': <Object>[],
    'error': null,
  };
  test('rejects foreign envelope shapes and non-string variables', () {
    for (final value in [
      null,
      <Object?>[],
      {
        'temporaryVariables': {'x': 42},
      },
      {
        ...envelope(),
        'temporaryVariables': {'x': 42},
      },
    ]) {
      expect(
        decodeScriptOutput(
          jsonEncode(value),
          input,
          const ScriptLimits(),
        ).error,
        isNotNull,
      );
    }
  });
  test('rejects post-request mutations and writes without environment', () {
    final request = envelope()
      ..['requestPatch'] = {
        'url': '/bad',
        'headerSets': <String, String>{},
        'headerUnsets': <String>[],
      };
    expect(
      decodeScriptOutput(
        jsonEncode(request),
        input.copyWith(phase: ScriptPhase.postResponse),
        const ScriptLimits(),
      ).error,
      isNotNull,
    );
    final env = envelope()
      ..['environmentPatch'] = {
        'sets': {'token': 'x'},
        'unsets': <String>[],
      };
    expect(
      decodeScriptOutput(jsonEncode(env), input, const ScriptLimits()).error,
      isNotNull,
    );
  });
  test('enforces byte quota before parsing output', () {
    final value = envelope()..['temporaryVariables'] = {'text': 'á' * 100};
    expect(
      decodeScriptOutput(
        jsonEncode(value),
        input,
        const ScriptLimits(outputBytes: 100),
      ).error?.kind,
      ScriptErrorKind.outputTooLarge,
    );
  });
  test('valid output preserves explicit empty body patch and null error', () {
    final value = envelope()
      ..['requestPatch'] = {
        'body': '',
        'headerSets': <String, String>{},
        'headerUnsets': <String>[],
      };
    final result = decodeScriptOutput(
      jsonEncode(value),
      input,
      const ScriptLimits(),
    );
    expect(result.error, isNull);
    expect(result.requestPatch.body, '');
  });
}
