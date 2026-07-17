// Fixture: equatable_props_complete — classes missing fields from `props`.
// ignore_for_file: uri_does_not_exist, unused_import, must_be_immutable
import 'package:equatable/equatable.dart';

// MISSING field `b` in props → the class name is flagged.
// expect_lint: equatable_props_complete
class BadState extends Equatable {
  const BadState(this.a, this.b);
  final int a;
  final int b;
  @override
  List<Object?> get props => [a];
}

// Complete → not flagged.
class GoodState extends Equatable {
  const GoodState(this.a, this.b);
  final int a;
  final int b;
  @override
  List<Object?> get props => [a, b];
}

// Field intentionally excluded with a reason → suppressed, not flagged.
// The diagnostic is anchored to the class name, so the `// ignore:` goes
// directly above the class declaration (a field-level ignore would not
// suppress a class-anchored report).
// id is deliberately outside equality.
// ignore: equatable_props_complete
class ExcludedState extends Equatable {
  const ExcludedState(this.a, this.id);
  final int a;
  final int id;
  @override
  List<Object?> get props => [a];
}

// Non-Equatable class → never flagged.
class Plain {
  Plain(this.a);
  final int a;
}

// Pins the "ignore must be class-level" contract: a `// ignore:` on the field
// does NOT suppress the diagnostic because it is anchored to the class name.
// The class IS still flagged — the expect_lint below must remain present.
// expect_lint: equatable_props_complete
class FieldLevelIgnoreState extends Equatable {
  const FieldLevelIgnoreState(this.a, this.b);
  final int a;
  // ignore: equatable_props_complete  ← field-level; does NOT suppress the class lint
  final int b;
  @override
  List<Object?> get props => [a];
}
