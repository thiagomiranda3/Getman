import 'package:equatable/equatable.dart';

abstract class GitSyncEvent extends Equatable {
  const GitSyncEvent();
  @override
  List<Object?> get props => [];
}

class LoadBranchStatus extends GitSyncEvent {
  const LoadBranchStatus(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

class SwitchBranch extends GitSyncEvent {
  const SwitchBranch(this.root, this.branch);
  final String root;
  final String branch;
  @override
  List<Object?> get props => [root, branch];
}

class CreateBranch extends GitSyncEvent {
  const CreateBranch(this.root, this.branch);
  final String root;
  final String branch;
  @override
  List<Object?> get props => [root, branch];
}

class PullChanges extends GitSyncEvent {
  const PullChanges(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

class PushChanges extends GitSyncEvent {
  const PushChanges(this.root);
  final String root;
  @override
  List<Object?> get props => [root];
}

class StashChanges extends GitSyncEvent {
  const StashChanges(this.root, this.message);
  final String root;
  final String message;
  @override
  List<Object?> get props => [root, message];
}

class PopStash extends GitSyncEvent {
  const PopStash(this.root, this.index);
  final String root;
  final int index;
  @override
  List<Object?> get props => [root, index];
}

class DropStash extends GitSyncEvent {
  const DropStash(this.root, this.index);
  final String root;
  final int index;
  @override
  List<Object?> get props => [root, index];
}
