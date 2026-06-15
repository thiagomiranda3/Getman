import 'package:getman/core/domain/entities/assertion_result.dart';
import 'package:getman/core/domain/entities/extraction_result.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/json_path.dart';
import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:getman/features/chaining/domain/entities/extraction_rule.dart';
import 'package:getman/features/chaining/domain/logic/assertion_engine.dart';
import 'package:getman/features/chaining/domain/logic/extraction_engine.dart';

/// Inputs for one post-response rules pass. Plain immutable data — its fields
/// are value objects of primitives/strings/maps/enums, so it is sendable across
/// an isolate boundary (it is the argument to [runRules] under `compute`).
class RulesRunInput {
  const RulesRunInput({
    required this.extractionRules,
    required this.assertions,
    required this.response,
  });
  final List<ExtractionRule> extractionRules;
  final List<Assertion> assertions;
  final HttpResponseEntity response;
}

/// Captured values + assertion verdicts from one rules pass.
class RulesRunOutput {
  const RulesRunOutput({required this.extraction, required this.assertions});
  final List<ExtractionResult> extraction;
  final List<AssertionResult> assertions;
}

/// Decodes the response body **once** and runs both the extraction and
/// assertion engines against the shared decoded tree — instead of each engine
/// (and each jsonPath rule) re-decoding the body. Top-level + pure so it is a
/// valid `compute` entry point; the bloc runs it inline for small bodies and on
/// a background isolate for large ones.
RulesRunOutput runRules(RulesRunInput input) {
  final decoded = JsonPath.tryDecode(input.response.body);
  return RulesRunOutput(
    extraction: ExtractionEngine.runDecoded(
      input.extractionRules,
      input.response,
      decoded,
    ),
    assertions: AssertionEngine.runDecoded(
      input.assertions,
      input.response,
      decoded,
    ),
  );
}
