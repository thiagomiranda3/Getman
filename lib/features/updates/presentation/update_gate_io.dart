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
import 'package:path_provider/path_provider.dart';
import 'package:updat/updat.dart';

/// Invisible widget mounted in `MainScreen`. Hosts one `UpdatWidget` that
/// checks GitHub on mount, bridges its callbacks into [UpdateController], and
/// shows the themed [UpdateDialog] / snackbars per the prompt decision.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  String? _currentVersion;
  String? _downloadPath;

  static const _appName = 'getman';

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
          controller.cachedRelease?.changelog,
      getBinaryUrl: (_) async => controller.cachedRelease?.assetUrl ?? '',
      getDownloadFileLocation: _downloadLocation,
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
            // no listener notification.
            controller
              ..triggerCheck = checkForUpdate
              // updat's startUpdate is void Function(); wrap to match
              // UpdateController.startUpdate which is Future<void> Function()?
              ..startUpdate = () async {
                startUpdate();
              }
              ..dismiss = dismissUpdate;

            // Defer the notifying updateFromGate call out of build, mirroring
            // _onStatus, to avoid "markNeedsBuild called during build" when
            // updat rebuilds the chip (e.g. on downloading state change) while
            // the UpdateDialog's AnimatedBuilder is already listening.
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
  /// isn't a manual check. Returns the version string `updat` compares.
  Future<String?> _getLatestVersion(UpdateController controller) async {
    final settingsBloc = context.read<SettingsBloc>();
    final settings = settingsBloc.state.settings;
    if (!controller.manualInFlight && !settings.checkForUpdatesOnStartup) {
      return null;
    }
    final release = await controller.fetchLatestRelease(_platform);
    return release?.version;
  }

  Future<File> _downloadLocation(String? version) async {
    final controller = context.read<UpdateController>();
    final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    final url = controller.cachedRelease?.assetUrl ?? '';
    final ext = url.contains('.') ? url.split('.').last : 'bin';
    final path = '${dir.path}${Platform.pathSeparator}getman-$version.$ext';
    _downloadPath = path;
    return File(path);
  }

  void _onStatus(
    BuildContext context,
    UpdateController controller,
    UpdatStatus status,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mapped = _mapPhase(status);
      // Capture the phase we're leaving before updateFromGate overwrites it, so
      // an error after a download can be distinguished from a failed check.
      final wasDownloading = controller.phase == UpdatePhase.downloading;
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
          // Always surface a failed download (the user explicitly pressed
          // UPDATE NOW) so it never silently does nothing; a failed background
          // check stays quiet unless it was a manual check.
          if (controller.manualInFlight || wasDownloading) {
            controller.manualInFlight = false;
            showAppSnackBar(
              context,
              wasDownloading
                  ? 'Update download failed. Please try again later.'
                  : "Couldn't check for updates.",
            );
          }
        case UpdatePhase.readyToInstall:
          unawaited(_launchInstaller());
        case UpdatePhase.idle:
        case UpdatePhase.checking:
        case UpdatePhase.downloading:
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

  Future<void> _launchInstaller() async {
    final path = _downloadPath;
    if (path == null) return;
    try {
      if (Platform.isMacOS) {
        // Mount the .dmg, then quit: macOS won't let the user replace a
        // running .app bundle, so the app must exit for the drag-install to
        // succeed. The mounted volume + Finder window are owned by the system
        // and survive our exit.
        await Process.run('open', [path]);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        exit(0);
      } else if (Platform.isWindows) {
        await Process.start(path, [], mode: ProcessStartMode.detached);
        exit(0);
      } else if (Platform.isLinux) {
        await Process.run('chmod', ['+x', path]);
        final parent = File(path).parent.path;
        await Process.run('xdg-open', [parent]);
      }
    } on Exception {
      if (mounted) showAppSnackBar(context, 'Could not open the installer.');
    }
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
