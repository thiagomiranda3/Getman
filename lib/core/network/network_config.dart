/// Pure transport configuration for the Dio client. Lives in core (no dio,
/// no feature imports) so [NetworkService] never depends on the settings
/// feature. [SettingsEntity.toNetworkConfig] maps user settings to this.
class NetworkConfig {
  final int connectTimeoutMs;
  final int sendTimeoutMs;
  final int receiveTimeoutMs;
  final bool followRedirects;
  final bool verifySsl;
  final String? proxyUrl;

  const NetworkConfig({
    this.connectTimeoutMs = 30000,
    this.sendTimeoutMs = 30000,
    this.receiveTimeoutMs = 60000,
    this.followRedirects = true,
    this.verifySsl = true,
    this.proxyUrl,
  });

  static const NetworkConfig defaults = NetworkConfig();
}
