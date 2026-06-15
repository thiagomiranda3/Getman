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

  static const NetworkConfig defaults = NetworkConfig();
}
