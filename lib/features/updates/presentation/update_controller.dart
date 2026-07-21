// Web-safe command bus shared by the io-only update gate, the update dialog,
// and the Settings "Check for updates" button; see class doc below.

import 'package:flutter/foundation.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';
import 'package:getman/features/updates/presentation/update_phase.dart';

/// Shared command bus between the (io-only) update gate, the themed update
/// dialog, and the Settings "Check for updates" button. Holds the cached
/// release + display version and the gate's action callbacks. Web-safe (no
/// `updat`/`dart:io` import); exposed to the widget tree via `RepositoryProvider`.
class UpdateController extends ChangeNotifier {
  UpdateController(this._repository);

  final UpdateRepository _repository;

  String? currentVersion;
  String? latestVersion;
  String? changelog;
  UpdatePhase phase = UpdatePhase.idle;
  bool manualInFlight = false;
  ReleaseInfo? cachedRelease;

  /// True when this platform installs updates in-app (Windows/Linux: download
  /// to the Downloads folder, then auto-launch + quit) rather than handing
  /// the download to the browser (macOS, web). Set once by the io gate at
  /// startup — a plain field, no [notifyListeners] needed.
  bool installsInApp = false;

  // Set by the gate each build (captured from `updat`'s builder callbacks).
  VoidCallback? triggerCheck;
  Future<void> Function()? startUpdate;
  VoidCallback? dismiss;

  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform platform) async =>
      cachedRelease = await _repository.fetchLatestRelease(platform);

  /// Triggered by the Settings button: forces a check whose result is always
  /// surfaced (even "up to date") regardless of the auto-check toggle / skip.
  void checkNow() {
    manualInFlight = true;
    triggerCheck?.call();
  }

  void setCurrentVersion(String version) {
    if (currentVersion == version) return;
    currentVersion = version;
    notifyListeners();
  }

  void updateFromGate({
    UpdatePhase? phase,
    String? latestVersion,
    String? changelog,
  }) {
    var changed = false;
    if (phase != null && phase != this.phase) {
      this.phase = phase;
      changed = true;
    }
    // Null params mean "unchanged" (e.g. the gate's phase-only `_onStatus`
    // call). Without this guard, a phase-only update wipes the version +
    // changelog the chip builder set — which left `_maybePrompt` reading a null
    // version and silently suppressing the update dialog.
    if (latestVersion != null && latestVersion != this.latestVersion) {
      this.latestVersion = latestVersion;
      changed = true;
    }
    if (changelog != null && changelog != this.changelog) {
      this.changelog = changelog;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}
