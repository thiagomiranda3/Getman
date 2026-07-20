// Native-only auto-update gate: the SOLE importer of dart:io, package:updat,
// and package_info_plus (the web-safety gate — see update_gate.dart's
// conditional export to update_gate_stub.dart on web). Uses `updat` purely for
// the GitHub version *check*; the actual download is always handed off to the
// user's default browser (_openDownloadInBrowser), never performed in-process
// — a file downloaded by this sandboxed, unsigned app carries a strict
// com.apple.quarantine flag that macOS Gatekeeper reports as "damaged", and
// the sandbox forbids clearing that flag ourselves. See class doc below.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:getman/features/updates/presentation/update_decision.dart';
import 'package:getman/features/updates/presentation/update_phase.dart';
import 'package:getman/features/updates/presentation/widgets/update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:updat/updat.dart';
import 'package:url_launcher/url_launcher.dart';

/// Invisible widget mounted in `MainScreen`. Hosts one `UpdatWidget` purely for
/// the GitHub version *check*, bridges its callbacks into [UpdateController],
/// and shows the themed [UpdateDialog] / snackbars per the prompt decision.
///
/// Note: the actual download is intentionally handed to the user's browser
/// (see `_openDownloadInBrowser`), not performed in-process, so this gate
/// never drives `updat`'s download/install flow.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  String? _currentVersion;

  static const _appName = 'getman';

  /// Where to send the browser when no matching asset URL is known.
  static const _releasesUrl =
      'https://github.com/thiagomiranda3/Getman/releases/latest';

  bool get _supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  UpdatePlatform get _platform => Platform.isMacOS
      ? UpdatePlatform.macos
      : Platform.isWindows
      ? UpdatePlatform.windows
      : UpdatePlatform.linux;

  @override
  void initState() {
    super.initState();
    if (_supported) unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _currentVersion = info.version);
    context.read<UpdateController>().setCurrentVersion(info.version);
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported || _currentVersion == null) return const SizedBox.shrink();
    final controller = context.read<UpdateController>();

    return UpdatWidget(
      currentVersion: _currentVersion!,
      appName: _appName,
      openOnDownload: false,
      getLatestVersion: () => _getLatestVersion(controller),
      getChangelog: (latestVer, appVer) async =>
          controller.cachedRelease?.changelog ?? '',
      // Required by UpdatWidget but never invoked: we hand the download to the
      // browser rather than calling updat's in-process `startUpdate()`.
      getBinaryUrl: (_) async => controller.cachedRelease?.assetUrl ?? '',
      callback: (status) => _onStatus(context, controller, status),
      updateChipBuilder:
          ({
            required context,
            required latestVersion,
            required appVersion,
            required status,
            required checkForUpdate,
            required openDialog,
            required startUpdate,
            required launchInstaller,
            required dismissUpdate,
          }) {
            // Capture the callbacks synchronously — plain field assignments,
            // no listener notification. `startUpdate` is repointed at the
            // browser hand-off instead of updat's downloader. It is assigned
            // last and with a block body: a trailing `=> expr` in a cascade
            // would bind the next `..` to the closure's return value.
            controller
              ..triggerCheck = checkForUpdate
              ..dismiss = dismissUpdate
              ..startUpdate = () {
                return _openDownloadInBrowser(controller);
              };

            // Defer the notifying updateFromGate call out of build, mirroring
            // _onStatus, to avoid "markNeedsBuild called during build" when
            // updat rebuilds the chip while the UpdateDialog's AnimatedBuilder
            // is already listening.
            final mappedPhase = _mapPhase(status);
            final capturedLatest = latestVersion;
            final capturedChangelog = controller.cachedRelease?.changelog;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              controller.updateFromGate(
                phase: mappedPhase,
                latestVersion: capturedLatest,
                changelog: capturedChangelog,
              );
            });

            return const SizedBox.shrink();
          },
    );
  }

  /// Gates the network: skip the call entirely when auto-check is off and this
  /// isn't a manual check (a deliberate no-op — `updat` never calls `.then` in
  /// this case, so it's fine that this returns null rather than throwing).
  /// Returns the version string `updat` compares.
  ///
  /// A real check whose fetch fails (`fetchLatestRelease` returns null) MUST
  /// throw rather than return null: `updat`'s `updateValues` only acts inside
  /// `.then((latestVersion) { if (latestVersion != null...) ... })` — a null
  /// result is silently swallowed and `status` never becomes `error`. Throwing
  /// routes it through `updat`'s `.catchError`, which does set
  /// `status = UpdatStatus.error`, so `_onStatus` can surface the failure.
  Future<String?> _getLatestVersion(UpdateController controller) async {
    final settingsBloc = context.read<SettingsBloc>();
    final settings = settingsBloc.state.settings;
    if (!controller.manualInFlight && !settings.checkForUpdatesOnStartup) {
      return null;
    }
    final release = await controller.fetchLatestRelease(_platform);
    if (release == null) {
      throw StateError('Failed to fetch the latest release.');
    }
    return release.version;
  }

  /// Opens the release download in the user's default browser instead of
  /// fetching it in-process.
  ///
  /// A file written by this *sandboxed* app over the network is stamped with a
  /// strict `com.apple.quarantine` flag (agent = us) that macOS escalates into
  /// a "damaged and can't be opened" Gatekeeper block on our un-notarized app —
  /// even though the bytes are byte-identical to the GitHub asset. The sandbox
  /// forbids us from clearing that attribute ourselves (verified: `removexattr`
  /// fails with EPERM). A browser download instead carries a benign quarantine
  /// that opens normally, so we route the user there.
  Future<void> _openDownloadInBrowser(UpdateController controller) async {
    final url = controller.cachedRelease?.assetUrl ?? _releasesUrl;
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } on Exception {
        ok = false;
      }
    }
    if (!mounted) return;
    showAppSnackBar(
      context,
      ok
          ? 'Opening the download in your browser…'
          : "Couldn't open your browser. Download from $_releasesUrl",
    );
  }

  void _onStatus(
    BuildContext context,
    UpdateController controller,
    UpdatStatus status,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mapped = _mapPhase(status);
      controller.updateFromGate(phase: mapped);

      switch (mapped) {
        case UpdatePhase.available:
          _maybePrompt(context, controller);
        case UpdatePhase.upToDate:
          if (controller.manualInFlight) {
            controller.manualInFlight = false;
            showAppSnackBar(context, "You're on the latest version.");
          }
        case UpdatePhase.error:
          // A failed *check* only matters to surface when the user explicitly
          // pressed "Check for updates"; background checks stay quiet.
          if (controller.manualInFlight) {
            controller.manualInFlight = false;
            showAppSnackBar(context, "Couldn't check for updates.");
          }
        // The download/install phases never occur now that the browser handles
        // the download, but the switch over UpdatStatus must stay exhaustive.
        case UpdatePhase.idle:
        case UpdatePhase.checking:
        case UpdatePhase.downloading:
        case UpdatePhase.readyToInstall:
        case UpdatePhase.dismissed:
          break;
      }
    });
  }

  void _maybePrompt(BuildContext context, UpdateController controller) {
    final settings = context.read<SettingsBloc>().state.settings;
    // Source the version from the synchronously-cached release (set during the
    // fetch, before any updat status callback) rather than `latestVersion`,
    // which is only populated by a separate post-frame callback and may not be
    // set yet when this prompt decision runs.
    final latest =
        controller.cachedRelease?.version ?? controller.latestVersion;
    final manual = controller.manualInFlight;
    controller.manualInFlight = false;
    final prompt = shouldPromptForUpdate(
      autoCheck: settings.checkForUpdatesOnStartup,
      latest: latest,
      current: _currentVersion!,
      skipped: settings.skippedUpdateVersion,
      manual: manual,
    );
    if (!prompt || latest == null) return;
    unawaited(
      UpdateDialog.show(
        context,
        latestVersion: latest,
        currentVersion: _currentVersion!,
        changelog: controller.cachedRelease?.changelog,
        controller: controller,
        settingsBloc: context.read<SettingsBloc>(),
      ),
    );
  }

  UpdatePhase _mapPhase(UpdatStatus s) => switch (s) {
    UpdatStatus.idle => UpdatePhase.idle,
    UpdatStatus.checking => UpdatePhase.checking,
    UpdatStatus.available => UpdatePhase.available,
    UpdatStatus.availableWithChangelog => UpdatePhase.available,
    UpdatStatus.upToDate => UpdatePhase.upToDate,
    UpdatStatus.error => UpdatePhase.error,
    UpdatStatus.downloading => UpdatePhase.downloading,
    UpdatStatus.readyToInstall => UpdatePhase.readyToInstall,
    UpdatStatus.dismissed => UpdatePhase.dismissed,
  };
}
