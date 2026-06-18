import 'package:equatable/equatable.dart';

/// The desktop platforms Getman ships update artifacts for.
enum UpdatePlatform { macos, windows, linux }

/// A single GitHub release reduced to what the updater needs: the semantic
/// [version] (no leading `v`), the release [changelog] body, and the
/// platform-specific [assetUrl] to download (null if no matching asset).
class ReleaseInfo extends Equatable {
  const ReleaseInfo({
    required this.version,
    required this.changelog,
    required this.assetUrl,
  });

  final String version;
  final String? changelog;
  final String? assetUrl;

  @override
  List<Object?> get props => [version, changelog, assetUrl];
}
