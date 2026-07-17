// NetworkConfig: pure transport settings for the Dio client (timeouts,
// redirects, SSL verification, proxy, client-cert/mTLS trio) with zero dio
// or feature imports, so NetworkService never depends on the settings
// feature — SettingsEntity.toNetworkConfig maps user settings into this.
// sameAdapterConfig narrows down to just the fields that require rebuilding
// the HTTP adapter, so a timeout-only change can skip that rebuild.

import 'package:getman/core/network/network_service.dart' show NetworkService;
import 'package:getman/features/settings/domain/entities/settings_entity.dart'
    show SettingsEntity;

/// Pure transport configuration for the Dio client. Lives in core (no dio,
/// no feature imports) so [NetworkService] never depends on the settings
/// feature. [SettingsEntity.toNetworkConfig] maps user settings to this.
class NetworkConfig {
  const NetworkConfig({
    this.connectTimeoutMs = 30000,
    this.sendTimeoutMs = 30000,
    this.receiveTimeoutMs = 60000,
    this.followRedirects = true,
    this.maxRedirects = 5,
    this.verifySsl = true,
    this.proxyUrl,
    this.clientCertPath,
    this.clientKeyPath,
    this.clientCertPassphrase,
  });
  final int connectTimeoutMs;
  final int sendTimeoutMs;
  final int receiveTimeoutMs;
  final bool followRedirects;

  /// Max redirects to follow when [followRedirects] is true (Dio default: 5).
  final int maxRedirects;
  final bool verifySsl;
  final String? proxyUrl;

  // Client certificate (mTLS), expressed as plain data — never a dart:io
  // SecurityContext, which would pull dart:io into core/web. The native adapter
  // (dio_adapter_config_io) materializes a SecurityContext from these; web is a
  // no-op (browsers own TLS). PEM cert + PEM key paths + optional passphrase.
  final String? clientCertPath;
  final String? clientKeyPath;
  final String? clientCertPassphrase;

  /// Whether the adapter-relevant fields (SSL verification, proxy, mTLS cert
  /// trio) match [other]. Timeouts/redirects are applied on `BaseOptions` in
  /// place, so they are excluded — only these fields require rebuilding the
  /// HTTP adapter (which drops its socket pool), so the network services can
  /// skip the swap on a timeout-only change.
  bool sameAdapterConfig(NetworkConfig other) =>
      verifySsl == other.verifySsl &&
      proxyUrl == other.proxyUrl &&
      clientCertPath == other.clientCertPath &&
      clientKeyPath == other.clientKeyPath &&
      clientCertPassphrase == other.clientCertPassphrase;

  static const NetworkConfig defaults = NetworkConfig();
}
