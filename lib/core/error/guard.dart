// Repository-boundary helper translating a thrown PersistenceException into
// a PersistenceFailure — see docs/architecture/app-shell.md.

import 'package:getman/core/error/exceptions.dart';
import 'package:getman/core/error/failures.dart';

/// Runs [op] and translates any [PersistenceException] into a
/// [PersistenceFailure]. Repositories use this at the data-layer boundary so
/// BLoCs only ever see `Failure` subtypes — see docs/architecture/app-shell.md.
Future<T> guardPersistence<T>(Future<T> Function() op) async {
  try {
    return await op();
  } on PersistenceException catch (e) {
    throw PersistenceFailure(e.message);
  }
}
