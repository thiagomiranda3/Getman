import 'package:equatable/equatable.dart';

/// What part of the response an assertion checks.
enum AssertionTarget {
  statusCode('statusCode'),
  responseTime('responseTime'),
  bodyJsonPath('bodyJsonPath'),
  header('header');

  final String wire;
  const AssertionTarget(this.wire);

  static AssertionTarget fromWire(String? value) {
    for (final t in AssertionTarget.values) {
      if (t.wire == value) return t;
    }
    return AssertionTarget.statusCode;
  }
}

/// How the actual value is compared to [Assertion.expected].
enum AssertionComparator {
  equals('equals'),
  notEquals('notEquals'),
  contains('contains'),
  lessThan('lessThan'),
  greaterThan('greaterThan'),
  inRange('inRange'),
  exists('exists');

  final String wire;
  const AssertionComparator(this.wire);

  static AssertionComparator fromWire(String? value) {
    for (final c in AssertionComparator.values) {
      if (c.wire == value) return c;
    }
    return AssertionComparator.equals;
  }
}

/// A no-code post-response assertion.
///
/// [path] is the JSONPath (for [AssertionTarget.bodyJsonPath]) or header name
/// (for [AssertionTarget.header]); unused for status/time. [expected] is the
/// comparison value (for [AssertionComparator.inRange] use `"lo-hi"`).
class Assertion extends Equatable {
  final String id;
  final AssertionTarget target;
  final AssertionComparator comparator;
  final String path;
  final String expected;
  final bool enabled;

  const Assertion({
    required this.id,
    this.target = AssertionTarget.statusCode,
    this.comparator = AssertionComparator.equals,
    this.path = '',
    this.expected = '',
    this.enabled = true,
  });

  Assertion copyWith({
    AssertionTarget? target,
    AssertionComparator? comparator,
    String? path,
    String? expected,
    bool? enabled,
  }) {
    return Assertion(
      id: id,
      target: target ?? this.target,
      comparator: comparator ?? this.comparator,
      path: path ?? this.path,
      expected: expected ?? this.expected,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  List<Object?> get props => [id, target, comparator, path, expected, enabled];
}
