// ignore_for_file: unused_import, uri_does_not_exist
// FIXTURE — intentional architecture violation: BLoC importing from the data layer.
// This file exists solely to prove that the architecture tests detect this violation.
import '../../data/datasources/fake_data_source.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
