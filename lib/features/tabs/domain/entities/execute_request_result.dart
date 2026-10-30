// Ephemeral execution outcome; never serialized into request persistence.
import 'package:equatable/equatable.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/scripting/domain/entities/script_error.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';

const _unchanged = Object();

enum ScriptExecutionPhase { idle, preRequest, network, postResponse }

class ExecuteRequestResult extends Equatable {
  const ExecuteRequestResult({
    this.response,
    this.preRequest,
    this.postResponse,
    this.error,
    this.cancelled = false,
    this.secretValues = const {},
  });
  const ExecuteRequestResult.cancelled()
    : response = null,
      preRequest = null,
      postResponse = null,
      error = null,
      cancelled = true,
      secretValues = const {};
  final HttpResponseEntity? response;
  final ScriptOutput? preRequest;
  final ScriptOutput? postResponse;
  final ScriptError? error;
  final bool cancelled;
  final Set<String> secretValues;
  ExecuteRequestResult copyWith({
    Object? response = _unchanged,
    Object? preRequest = _unchanged,
    Object? postResponse = _unchanged,
    Object? error = _unchanged,
    bool? cancelled,
    Set<String>? secretValues,
  }) => ExecuteRequestResult(
    response: identical(response, _unchanged)
        ? this.response
        : response as HttpResponseEntity?,
    preRequest: identical(preRequest, _unchanged)
        ? this.preRequest
        : preRequest as ScriptOutput?,
    postResponse: identical(postResponse, _unchanged)
        ? this.postResponse
        : postResponse as ScriptOutput?,
    error: identical(error, _unchanged) ? this.error : error as ScriptError?,
    cancelled: cancelled ?? this.cancelled,
    secretValues: Set.unmodifiable(secretValues ?? this.secretValues),
  );
  @override
  List<Object?> get props => [
    response,
    preRequest,
    postResponse,
    error,
    cancelled,
    secretValues,
  ];
}
