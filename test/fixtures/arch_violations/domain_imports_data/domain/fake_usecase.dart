// ignore_for_file: unused_import, uri_does_not_exist
// FIXTURE — intentional architecture violation: domain importing from data layer.
// This file exists solely to prove that the architecture tests detect this violation.
import '../../data/models/fake_model.dart';
import 'package:equatable/equatable.dart';
