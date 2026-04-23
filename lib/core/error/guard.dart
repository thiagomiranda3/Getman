import 'exceptions.dart';
import 'failures.dart';

/// Runs [op] and translates any [PersistenceException] into a
/// [PersistenceFailure]. Repositories use this at the data-layer boundary so
/// BLoCs only ever see `Failure` subtypes — see CLAUDE.md §4.7.
Future<T> guardPersistence<T>(Future<T> Function() op) async {
  try {
    return await op();
  } on PersistenceException catch (e) {
    throw PersistenceFailure(e.message);
  }
}
