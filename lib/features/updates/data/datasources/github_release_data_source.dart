import 'package:dio/dio.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';

/// Hits the GitHub "latest release" REST endpoint with a dedicated [Dio] (no
/// app interceptors/proxy/cookies — a user's network config must not be able to
/// break the updater). Throws on HTTP/parse failure; the repository wraps this.
class GithubReleaseDataSource {
  GithubReleaseDataSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _latestReleaseUrl =
      'https://api.github.com/repos/thiagomiranda3/Getman/releases/latest';

  /// The asset-name suffix Getman publishes for each platform.
  static String _assetSuffix(UpdatePlatform platform) => switch (platform) {
    UpdatePlatform.macos => '-macos-arm64.dmg',
    UpdatePlatform.windows => '-windows-x64-setup.exe',
    UpdatePlatform.linux => '-linux-x86_64.AppImage',
  };

  Future<ReleaseInfo> fetchLatestRelease(UpdatePlatform platform) async {
    final res = await _dio.get<dynamic>(_latestReleaseUrl);
    final data = res.data as Map<String, dynamic>;

    final tag = data['tag_name'] as String? ?? '';
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    final changelog = data['body'] as String?;

    final assets = (data['assets'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final suffix = _assetSuffix(platform);
    String? assetUrl;
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.endsWith(suffix)) {
        assetUrl = asset['browser_download_url'] as String?;
        break;
      }
    }

    return ReleaseInfo(
      version: version,
      changelog: changelog,
      assetUrl: assetUrl,
    );
  }
}
