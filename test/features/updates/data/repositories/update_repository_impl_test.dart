import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/updates/data/datasources/github_release_data_source.dart';
import 'package:getman/features/updates/data/repositories/update_repository_impl.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:mocktail/mocktail.dart';

class _MockDataSource extends Mock implements GithubReleaseDataSource {}

void main() {
  setUpAll(() => registerFallbackValue(UpdatePlatform.macos));

  late _MockDataSource ds;
  late UpdateRepositoryImpl repo;

  setUp(() {
    ds = _MockDataSource();
    repo = UpdateRepositoryImpl(ds);
  });

  test('returns ReleaseInfo on success', () async {
    when(() => ds.fetchLatestRelease(any())).thenAnswer(
      (_) async =>
          const ReleaseInfo(version: '1.1.0', changelog: 'x', assetUrl: 'u'),
    );
    final info = await repo.fetchLatestRelease(UpdatePlatform.macos);
    expect(info?.version, '1.1.0');
  });

  test('returns null when the data source throws', () async {
    when(() => ds.fetchLatestRelease(any())).thenThrow(Exception('offline'));
    final info = await repo.fetchLatestRelease(UpdatePlatform.macos);
    expect(info, isNull);
  });
}
