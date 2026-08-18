import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/updates/data/datasources/github_release_data_source.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

Response<dynamic> _resp(Map<String, dynamic> json) => Response<dynamic>(
  requestOptions: RequestOptions(path: '/'),
  statusCode: 200,
  data: json,
);

const Map<String, dynamic> _sampleJson = {
  'tag_name': 'v1.1.0',
  'body': 'Release notes here',
  'assets': [
    {
      'name': 'getman-1.1.0-macos-arm64.dmg',
      'browser_download_url': 'https://example.com/mac.dmg',
    },
    {
      'name': 'getman-1.1.0-windows-x64-setup.exe',
      'browser_download_url': 'https://example.com/win.exe',
    },
    {
      'name': 'getman-1.1.0-linux-x86_64.AppImage',
      'browser_download_url': 'https://example.com/linux.AppImage',
    },
  ],
};

void main() {
  late _MockDio dio;
  late GithubReleaseDataSource ds;

  setUp(() {
    dio = _MockDio();
    ds = GithubReleaseDataSource(dio: dio);
    when(
      () => dio.get<dynamic>(any()),
    ).thenAnswer((_) async => _resp(_sampleJson));
  });

  test('parses tag (strips v), body, and macOS asset', () async {
    final info = await ds.fetchLatestRelease(UpdatePlatform.macos);
    expect(info.version, '1.1.0');
    expect(info.changelog, 'Release notes here');
    expect(info.assetUrl, 'https://example.com/mac.dmg');
  });

  test('selects the windows setup.exe asset', () async {
    final info = await ds.fetchLatestRelease(UpdatePlatform.windows);
    expect(info.assetUrl, 'https://example.com/win.exe');
  });

  test('selects the linux AppImage asset', () async {
    final info = await ds.fetchLatestRelease(UpdatePlatform.linux);
    expect(info.assetUrl, 'https://example.com/linux.AppImage');
  });

  test(
    'default Dio carries connect/receive timeouts so CHECK FOR UPDATES '
    'cannot hang forever on a silently-dropping network',
    () {
      // The updater deliberately bypasses the app's proxy config, so on
      // proxy-only networks the request is dropped silently — without
      // timeouts it never completes and the UI stays in `checking`.
      final defaultDs = GithubReleaseDataSource();
      expect(
        defaultDs.dio.options.connectTimeout,
        const Duration(seconds: 10),
      );
      expect(
        defaultDs.dio.options.receiveTimeout,
        const Duration(seconds: 20),
      );
    },
  );

  test('assetUrl is null when no asset matches the platform', () async {
    when(() => dio.get<dynamic>(any())).thenAnswer(
      (_) async => _resp({
        'tag_name': 'v1.1.0',
        'body': null,
        'assets': <Map<String, dynamic>>[],
      }),
    );
    final info = await ds.fetchLatestRelease(UpdatePlatform.macos);
    expect(info.assetUrl, isNull);
  });
}
