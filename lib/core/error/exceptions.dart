class PersistenceException implements Exception {
  final String message;
  final Object? cause;

  PersistenceException(this.message, {this.cause});

  @override
  String toString() => 'PersistenceException: $message${cause != null ? ' ($cause)' : ''}';
}
