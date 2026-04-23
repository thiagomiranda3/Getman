import 'package:equatable/equatable.dart';
import '../../domain/entities/environment_entity.dart';

class EnvironmentsState extends Equatable {
  final List<EnvironmentEntity> environments;
  final bool isLoading;

  const EnvironmentsState({
    this.environments = const [],
    this.isLoading = false,
  });

  @override
  List<Object?> get props => [environments, isLoading];

  EnvironmentsState copyWith({
    List<EnvironmentEntity>? environments,
    bool? isLoading,
  }) {
    return EnvironmentsState(
      environments: environments ?? this.environments,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
