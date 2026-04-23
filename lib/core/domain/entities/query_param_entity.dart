import 'package:equatable/equatable.dart';

class QueryParamEntity extends Equatable {
  final String key;
  final String value;

  const QueryParamEntity({required this.key, required this.value});

  @override
  List<Object?> get props => [key, value];
}
