import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable implements Exception {
  final String message;
  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

class PersistenceFailure extends Failure {
  const PersistenceFailure(super.message);
}

enum NetworkFailureType {
  connection,
  sendTimeout,
  receiveTimeout,
  cancelled,
  badResponse,
  badCertificate,
  unknown,
}

class NetworkFailure extends Failure {
  final NetworkFailureType type;
  final int? statusCode;

  const NetworkFailure(super.message, {required this.type, this.statusCode});

  @override
  List<Object?> get props => [message, type, statusCode];
}
