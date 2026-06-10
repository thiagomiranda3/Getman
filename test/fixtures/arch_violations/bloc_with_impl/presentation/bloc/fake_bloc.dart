// ignore_for_file: unused_import, uri_does_not_exist
// FIXTURE — intentional architecture violation: BLoC importing a repository implementation.
// This file exists solely to prove that the architecture tests detect this violation.
import '../../data/repositories/fake_repository_impl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
