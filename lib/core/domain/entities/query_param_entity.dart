import 'package:equatable/equatable.dart';

class QueryParamEntity extends Equatable {
  const QueryParamEntity({required this.key, required this.value});
  final String key;
  final String value;

  @override
  List<Object?> get props => [key, value];
}
