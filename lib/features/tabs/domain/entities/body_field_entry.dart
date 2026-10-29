// One locally learned JSON property name and its cumulative usage count.
// Values and complete request bodies never enter the dictionary.
import 'package:equatable/equatable.dart';

class BodyFieldEntry extends Equatable {
  const BodyFieldEntry({required this.name, required this.usageCount});

  final String name;
  final int usageCount;

  BodyFieldEntry copyWith({String? name, int? usageCount}) => BodyFieldEntry(
    name: name ?? this.name,
    usageCount: usageCount ?? this.usageCount,
  );

  @override
  List<Object?> get props => [name, usageCount];
}
