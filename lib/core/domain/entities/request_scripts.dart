// Request-owned JavaScript sources and per-stage enablement. No runtime state
// or local trust is stored here; shared by tabs, collections and history.
import 'package:equatable/equatable.dart';

class RequestScripts extends Equatable {
  const RequestScripts({
    this.apiVersion = 1,
    this.preRequest = '',
    this.postResponse = '',
    this.preRequestEnabled = true,
    this.postResponseEnabled = true,
  });
  final int apiVersion;
  final String preRequest;
  final String postResponse;
  final bool preRequestEnabled;
  final bool postResponseEnabled;
  bool get isEmpty => preRequest.isEmpty && postResponse.isEmpty;
  bool get hasEnabledScripts =>
      (preRequestEnabled && preRequest.trim().isNotEmpty) ||
      (postResponseEnabled && postResponse.trim().isNotEmpty);
  RequestScripts copyWith({
    int? apiVersion,
    String? preRequest,
    String? postResponse,
    bool? preRequestEnabled,
    bool? postResponseEnabled,
  }) => RequestScripts(
    apiVersion: apiVersion ?? this.apiVersion,
    preRequest: preRequest ?? this.preRequest,
    postResponse: postResponse ?? this.postResponse,
    preRequestEnabled: preRequestEnabled ?? this.preRequestEnabled,
    postResponseEnabled: postResponseEnabled ?? this.postResponseEnabled,
  );
  @override
  List<Object> get props => [
    apiVersion,
    preRequest,
    postResponse,
    preRequestEnabled,
    postResponseEnabled,
  ];
}
