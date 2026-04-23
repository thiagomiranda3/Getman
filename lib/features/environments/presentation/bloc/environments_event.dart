import 'package:equatable/equatable.dart';
import '../../domain/entities/environment_entity.dart';

abstract class EnvironmentsEvent extends Equatable {
  const EnvironmentsEvent();
  @override
  List<Object?> get props => [];
}

class LoadEnvironments extends EnvironmentsEvent {
  const LoadEnvironments();
}

class AddEnvironment extends EnvironmentsEvent {
  final String name;
  const AddEnvironment(this.name);
  @override
  List<Object?> get props => [name];
}

class UpdateEnvironment extends EnvironmentsEvent {
  final EnvironmentEntity environment;
  const UpdateEnvironment(this.environment);
  @override
  List<Object?> get props => [environment];
}

class DeleteEnvironment extends EnvironmentsEvent {
  final String id;
  const DeleteEnvironment(this.id);
  @override
  List<Object?> get props => [id];
}
