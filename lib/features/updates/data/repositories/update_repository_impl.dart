import 'dart:developer';

import 'package:getman/features/updates/data/datasources/github_release_data_source.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';

class UpdateRepositoryImpl implements UpdateRepository {
  UpdateRepositoryImpl(this.dataSource);

  final GithubReleaseDataSource dataSource;

  @override
  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform platform) async {
    try {
      return await dataSource.fetchLatestRelease(platform);
    } on Object catch (e) {
      // Any failure (offline, rate-limit, malformed JSON) => no update info.
      log('Update check failed: $e', name: 'UpdateRepository');
      return null;
    }
  }
}
