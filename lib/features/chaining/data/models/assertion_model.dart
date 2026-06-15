import 'package:getman/features/chaining/domain/entities/assertion.dart';
import 'package:hive_ce/hive.dart';

part 'assertion_model.g.dart';

/// typeId 8. Enums stored as their wire string (no separate enum adapter).
@HiveType(typeId: 8)
class AssertionModel extends HiveObject {
  AssertionModel({
    required this.id,
    this.target = 'statusCode',
    this.comparator = 'equals',
    this.path = '',
    this.expected = '',
    this.enabled = true,
  });

  factory AssertionModel.fromEntity(Assertion a) => AssertionModel(
    id: a.id,
    target: a.target.wire,
    comparator: a.comparator.wire,
    path: a.path,
    expected: a.expected,
    enabled: a.enabled,
  );
  @HiveField(0)
  String id;

  @HiveField(1, defaultValue: 'statusCode')
  String target;

  @HiveField(2, defaultValue: 'equals')
  String comparator;

  @HiveField(3, defaultValue: '')
  String path;

  @HiveField(4, defaultValue: '')
  String expected;

  @HiveField(5, defaultValue: true)
  bool enabled;

  Assertion toEntity() => Assertion(
    id: id,
    target: AssertionTarget.fromWire(target),
    comparator: AssertionComparator.fromWire(comparator),
    path: path,
    expected: expected,
    enabled: enabled,
  );
}
