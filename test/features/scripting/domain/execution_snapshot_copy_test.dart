import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/scripting/domain/entities/script_error.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/tabs/domain/entities/execute_request_result.dart';
import 'package:getman/features/tabs/domain/entities/script_variable_snapshot.dart';

void main() {
  test('snapshot copy explicitly clears environment and snapshots secrets', () {
    final original = ScriptVariableSnapshot(
      environmentId: 'env',
      environmentVariables: const {'token': 'x'},
      secretKeys: const {'token'},
    );
    final keys = {'next'};
    final copied = original.copyWith(environmentId: null, secretKeys: keys);
    keys.clear();
    expect(copied.environmentId, isNull);
    expect(copied.environmentVariables, {'token': 'x'});
    expect(copied.secretKeys, {'next'});
    expect(original.copyWith(), original);
  });
  test('result copy preserves diagnostics and can clear error explicitly', () {
    const result = ExecuteRequestResult(
      error: ScriptError(
        kind: ScriptErrorKind.runtime,
        message: 'bad',
        phase: ScriptPhase.preRequest,
      ),
      secretValues: {'secret'},
    );
    expect(result.copyWith(), result);
    final copied = result.copyWith(error: null, cancelled: true);
    expect(copied.error, isNull);
    expect(copied.cancelled, isTrue);
    expect(copied.secretValues, {'secret'});
  });
}
