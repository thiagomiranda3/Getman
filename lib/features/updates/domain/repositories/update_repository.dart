import 'package:getman/features/updates/domain/entities/release_info.dart';

/// Fetches the latest published release for a given [UpdatePlatform].
/// Implementations return `null` on any failure (offline, rate-limited, no
/// matching asset) — the caller treats null as "no update info available".
// ignore: one_member_abstracts
abstract class UpdateRepository {
  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform platform);
}
