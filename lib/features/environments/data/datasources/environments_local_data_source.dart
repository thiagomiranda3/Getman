import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/storage/hive_boxes.dart';
import '../../../../core/storage/hive_helpers.dart';
import '../models/environment_model.dart';

abstract class EnvironmentsLocalDataSource {
  Future<List<EnvironmentModel>> getEnvironments();
  Future<void> saveEnvironments(List<EnvironmentModel> environments);
}

class EnvironmentsLocalDataSourceImpl implements EnvironmentsLocalDataSource {
  Box<EnvironmentModel> _box() => Hive.box<EnvironmentModel>(HiveBoxes.environments);

  @override
  Future<List<EnvironmentModel>> getEnvironments() async {
    try {
      return _box().values.toList();
    } catch (e) {
      throw PersistenceException('Failed to read environments', cause: e);
    }
  }

  @override
  Future<void> saveEnvironments(List<EnvironmentModel> environments) async {
    try {
      await replaceAllInBox(_box(), environments);
    } catch (e) {
      throw PersistenceException('Failed to save environments', cause: e);
    }
  }
}
