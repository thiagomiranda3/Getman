// The Failure hierarchy BLoCs are allowed to handle (never raw exceptions):
// PersistenceFailure for storage errors, and NetworkFailure with a typed
// NetworkFailureType enum + optional HTTP status code for send failures.

import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable implements Exception {
  const Failure(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

class PersistenceFailure extends Failure {
  const PersistenceFailure(super.message);
}

enum NetworkFailureType {
  connectionTimeout,
  connectionError,
  sendTimeout,
  receiveTimeout,
  cancelled,
  badResponse,
  badCertificate,
  unknown,
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {required this.type, this.statusCode});
  final NetworkFailureType type;
  final int? statusCode;

  @override
  List<Object?> get props => [message, type, statusCode];
}
