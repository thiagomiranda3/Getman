// ignore_for_file: uri_does_not_exist, unused_import

// expect_lint: domain_no_infrastructure_imports
import 'package:flutter/material.dart';
// expect_lint: domain_no_infrastructure_imports
import 'dart:io';
// expect_lint: domain_no_infrastructure_imports
import 'package:dio/dio.dart';
// expect_lint: domain_no_infrastructure_imports
import 'package:hive_ce/hive.dart';
// expect_lint: domain_no_infrastructure_imports
import 'package:getman/features/x/data/foo_model.dart';

// Allowed in domain — must NOT be flagged:
import 'package:equatable/equatable.dart';
import 'package:getman/features/x/domain/bar.dart';
