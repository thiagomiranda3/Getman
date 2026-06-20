class PersistenceException implements Exception {
  PersistenceException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() =>
      'PersistenceException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Thrown when a file-backed request body (multipart file row / binary body)
/// can't be read at send time — e.g. the file was moved or deleted. Pure (no
/// dart:io) so it can cross the data→network boundary; the repository maps it
/// to a NetworkFailure so the user sees a real error response.
class FileBodyException implements Exception {
  FileBodyException(this.path, {this.cause});
  final String path;
  final Object? cause;

  @override
  String toString() =>
      'Could not read file: $path${cause != null ? ' ($cause)' : ''}';
}

/// Thrown when a GraphQL request's variables pane holds non-empty text that is
/// not valid JSON. Pure (no dart:io) so it can cross the data→network boundary;
/// the repository maps it to a status-0 NetworkFailure so the user sees a real
/// error response instead of an uncaught throw.
class GraphqlVariablesException implements Exception {
  GraphqlVariablesException(this.detail);
  final String detail;

  @override
  String toString() => 'GraphQL variables are not valid JSON: $detail';
}
