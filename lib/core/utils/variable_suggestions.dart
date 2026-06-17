import 'package:getman/core/utils/variable_resolution_helper.dart';

/// One row in the variable autocomplete menu: the [name] to insert plus its
/// [classification] (kind/value/source) for the preview. Pure Dart.
class VariableSuggestion {
  const VariableSuggestion({required this.name, required this.classification});
  final String name;
  final ResolvedVariable classification;
}

/// Dynamic built-ins offered as suggestions. Mirrors the dynamic variable set
/// but drops the `$randomUuid` lowercase alias of `$randomUUID` so the menu
/// shows no near-duplicate row.
const List<String> kSuggestableDynamicNames = [
  r'$guid',
  r'$randomUUID',
  r'$timestamp',
  r'$isoTimestamp',
  r'$randomInt',
];

/// Builds the filtered, ordered suggestion list for [query]. Candidate names
/// are [userVariableNames] (env ∪ collection) plus the curated dynamics (unless
/// [includeDynamics] is false). Ordering: prefix matches before substring
/// matches; within a rank, user variables before dynamics, then alphabetical.
/// Each surviving name is run through [classify] for its preview.
List<VariableSuggestion> buildVariableSuggestions({
  required String query,
  required Iterable<String> userVariableNames,
  required ResolvedVariable Function(String name) classify,
  bool includeDynamics = true,
}) {
  final lower = query.toLowerCase();
  final seen = <String>{};
  final users = <String>[];
  for (final n in userVariableNames) {
    if (seen.add(n)) users.add(n);
  }
  final dynamics = includeDynamics
      ? [
          for (final n in kSuggestableDynamicNames)
            if (!seen.contains(n)) n,
        ]
      : const <String>[];
  final dynamicSet = dynamics.toSet();

  bool matches(String n) => lower.isEmpty || n.toLowerCase().contains(lower);
  int rank(String n) => n.toLowerCase().startsWith(lower) ? 0 : 1;

  final candidates = [...users, ...dynamics].where(matches).toList()
    ..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final d = (dynamicSet.contains(a) ? 1 : 0).compareTo(
        dynamicSet.contains(b) ? 1 : 0,
      );
      if (d != 0) return d;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

  return [
    for (final n in candidates)
      VariableSuggestion(name: n, classification: classify(n)),
  ];
}
