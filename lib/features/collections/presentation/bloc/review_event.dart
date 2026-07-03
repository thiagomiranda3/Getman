import 'package:equatable/equatable.dart';

abstract class ReviewEvent extends Equatable {
  const ReviewEvent();
  @override
  List<Object?> get props => [];
}

class LoadReview extends ReviewEvent {
  const LoadReview(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

class StageNode extends ReviewEvent {
  const StageNode(this.root, this.path);
  final String root;
  final String path;
  @override
  List<Object?> get props => [root, path];
}

class UnstageNode extends ReviewEvent {
  const UnstageNode(this.root, this.path);
  final String root;
  final String path;
  @override
  List<Object?> get props => [root, path];
}

class SelectEntry extends ReviewEvent {
  const SelectEntry(this.path);
  final String path;
  @override
  List<Object?> get props => [path];
}

class Commit extends ReviewEvent {
  const Commit(this.root, this.message);
  final String root;
  final String message;
  @override
  List<Object?> get props => [root, message];
}

class InitRepo extends ReviewEvent {
  const InitRepo(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}
