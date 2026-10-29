// Pure-domain contract for a global, local JSON property-name dictionary.
// Implementations serialize increments and expose immutable ranked snapshots.
import 'package:getman/features/tabs/domain/entities/body_field_entry.dart';

abstract class BodyFieldDictionaryRepository {
  List<BodyFieldEntry> get entries;

  Future<void> recordUsage(Map<String, int> increments);
}
