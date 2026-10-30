// Atomic variable changes; input collections are copied so callers cannot
// mutate a pending commit. A key cannot be both set and removed.
import 'package:equatable/equatable.dart';

class ScriptPatch extends Equatable {
  ScriptPatch({
    Map<String, String> sets = const {},
    Set<String> unsets = const {},
  }) : sets = Map.unmodifiable(sets),
       unsets = Set.unmodifiable(unsets) {
    if (sets.keys.any(unsets.contains)) {
      throw ArgumentError('A variable cannot be both set and removed');
    }
  }
  final Map<String, String> sets;
  final Set<String> unsets;
  bool get isEmpty => sets.isEmpty && unsets.isEmpty;
  ScriptPatch copyWith({Map<String, String>? sets, Set<String>? unsets}) =>
      ScriptPatch(sets: sets ?? this.sets, unsets: unsets ?? this.unsets);
  @override
  List<Object> get props => [sets, unsets];
}
