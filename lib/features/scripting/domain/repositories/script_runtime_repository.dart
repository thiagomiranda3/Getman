// Script runtime boundary; implementations own workers, deadlines and disposal.
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';

abstract class ScriptRuntimeRepository {
  Future<ScriptOutput> execute(
    ScriptInput input, {
    required ScriptCancellation cancellation,
    ScriptLimits limits = const ScriptLimits(),
  });
  Future<void> close();
}
