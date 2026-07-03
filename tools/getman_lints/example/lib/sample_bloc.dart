// ignore_for_file: uri_does_not_exist, unused_import

// expect_lint: bloc_depends_on_abstractions
import 'package:getman/features/x/data/x_repository_impl.dart';
// expect_lint: bloc_depends_on_abstractions
import 'package:dio/dio.dart';
// expect_lint: bloc_depends_on_abstractions
import 'package:hive_ce/hive.dart';

// Allowed — abstract domain repo:
import 'package:getman/features/x/domain/repositories/x_repository.dart';
