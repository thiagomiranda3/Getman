// Native-only auto-update gate: the SOLE importer of package:updat and
// package_info_plus; one of the io-gated (*_io.dart) importers of dart:io and
// path_provider (the web-safety gate — see update_gate.dart's conditional
// export to update_gate_stub.dart on web).
// Two flows: macOS hands the download to the browser (a file downloaded by
// this sandboxed, unsigned app carries a strict com.apple.quarantine flag
// that Gatekeeper reports as "damaged", and the sandbox forbids clearing it);
// Windows/Linux download in-app via updat to the Downloads folder, then
// launch the installer and quit (finishInAppUpdate). See class doc below.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:getman/features/updates/presentation/update_decision.dart';
import 'package:getman/features/updates/presentation/update_phase.dart';
import 'package:getman/features/updates/presentation/widgets/update_dialog.dart';
import 'package:getman/features/updates/presentation/widgets/update_download_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:updat/updat.dart';
import 'package:url_launcher/url_launcher.dart';

/// Invisible widget mounted in `MainScreen`. Hosts one `UpdatWidget` for the
/// GitHub version *check* (and, on Windows/Linux, the in-app download),
/// bridges its callbacks into [UpdateController], and shows the themed
/// [UpdateDialog] / snackbars per the prompt decision.
///
/// macOS: the download is handed to the user's browser (see
/// `_openDownloadInBrowser`) — never performed in-process. Windows/Linux:
/// updat downloads the installer (blocking [UpdateDownloadDialog], guarded by
/// a download-stall watchdog), then [finishInAppUpdate] launches it, flushes
/// tabs, and quits.
class UpdateGate extends StatefulWidget {
  const UpdateGate({
    super.key,
    this.debugInstallsInApp,
    this.debugInstallerLauncher,
    this.debugQuit,
    this.debugDownloadTimeout,
  });

  /// Test seams — widget tests run on a macOS host, so the Windows/Linux
  /// in-app flow is unreachable without overrides. All null in production.
  @visibleForTesting
  final bool? debugInstallsInApp;

  @visibleForTesting
  final Future<void> Function(File installer)? debugInstallerLauncher;

  @visibleForTesting
  final void Function()? debugQuit;

  /// Overrides the download-stall watchdog's duration (production default:
  /// 10 minutes) so a fire path can be exercised deterministically in tests.
  @visibleForTesting
  final Duration? debugDownloadTimeout;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  String? _currentVersion;

  /// The installer download target, remembered by [_downloadLocationFor] so
  /// the finish/error paths can launch it or name it in messages.
  File? _installerFile;

  /// True from the user's "download and close" confirmation until the
  /// download resolves. Routes `_onStatus`'s readyToInstall/error into the
  /// in-app flow (a failed version *check* also emits `error` — this flag
  /// tells the two apart).
  bool _inAppDownloadInFlight = false;

  /// Whether the blocking [UpdateDownloadDialog] is on screen, so the error
  /// path pops exactly it and nothing else.
  bool _downloadDialogOpen = false;

  /// updat's real in-process downloader, captured from the chip builder.
  void Function()? _updatStartUpdate;

  /// Guards against updat's downloader (a single `http.get` with no timeout)
  /// stalling mid-transfer and leaving the non-dismissible
  /// [UpdateDownloadDialog] up forever. Started in [_startInAppDownload];
  /// cancelled on any terminal resolution (`_onStatus`'s error/readyToInstall
  /// branches) and in [dispose].
  Timer? _downloadWatchdog;

  bool get _installsInApp =>
      widget.debugInstallsInApp ?? (Platform.isWindows || Platform.isLinux);

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
    if (_supported) {
      context.read<UpdateController>().installsInApp = _installsInApp;
      unawaited(_loadVersion());
    }
  }

  @override
  void dispose() {
    _downloadWatchdog?.cancel();
    super.dispose();
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
      // Used by updat's in-app downloader on Windows/Linux. On macOS the
      // browser hand-off means it's never invoked.
      getBinaryUrl: (_) async => controller.cachedRelease?.assetUrl ?? '',
      getDownloadFileLocation: _downloadLocationFor,
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
            // no listener notification. `startUpdate` branches per platform:
            // Windows/Linux drive updat's own downloader in-app; macOS keeps
            // the browser hand-off. It is assigned last and with a block
            // body: a trailing `=> expr` in a cascade would bind the next
            // `..` to the closure's return value.
            _updatStartUpdate = startUpdate;
            controller
              ..triggerCheck = checkForUpdate
              ..dismiss = dismissUpdate
              ..startUpdate = () {
                return _installsInApp
                    ? _startInAppDownload()
                    : _openDownloadInBrowser(controller);
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

  /// Computes (and remembers) where the installer download lands: the user's
  /// Downloads folder, falling back to the system temp dir when the platform
  /// reports none (some headless Linux setups; plugin-less tests — a widget
  /// test has no macOS/Windows/Linux platform channel wired up at all, so the
  /// call never replies rather than resolving null, hence the timeout below).
  /// Must never throw — updat calls it OUTSIDE its own try/catch, so an
  /// exception here would strand the status at `downloading` with the dialog
  /// up forever; the same goes for a hang, hence the bounded wait.
  Future<File> _downloadLocationFor(String? latestVersion) async {
    final url = context.read<UpdateController>().cachedRelease?.assetUrl ?? '';
    Directory? downloads;
    try {
      downloads = await getDownloadsDirectory().timeout(
        const Duration(seconds: 3),
      );
    } on Object {
      downloads = null;
    }
    final dir = downloads ?? Directory.systemTemp;
    final ext = url.contains('.') ? url.split('.').last : 'bin';
    final file = File(
      '${dir.path}${Platform.pathSeparator}$_appName-$latestVersion.$ext',
    );
    _installerFile = file;
    return file;
  }

  /// Confirmed in-app flow: block the UI with [UpdateDownloadDialog] and hand
  /// off to updat's downloader. Resolution arrives via [_onStatus]
  /// (readyToInstall → [_finishInAppUpdate]; error → pop + snackbar). A
  /// watchdog timer guards against the download stalling forever (see
  /// [_downloadWatchdog]).
  Future<void> _startInAppDownload() async {
    // Capture always precedes prompts today, so `_updatStartUpdate` should
    // never be null here — this guard just prevents a permanent blocking
    // modal if that ever stops being true.
    if (_updatStartUpdate == null) return;
    _inAppDownloadInFlight = true;
    _downloadDialogOpen = true;
    unawaited(
      UpdateDownloadDialog.show(
        context,
      ).whenComplete(() => _downloadDialogOpen = false),
    );
    _downloadWatchdog = Timer(
      widget.debugDownloadTimeout ?? const Duration(minutes: 10),
      () {
        if (!_inAppDownloadInFlight || !mounted) return;
        _inAppDownloadInFlight = false;
        _popDownloadDialogIfOpen();
        showAppSnackBar(context, 'The update download timed out.');
        // If updat's downloader resolves after this fires, `_onStatus`'s
        // readyToInstall/error branches see `_inAppDownloadInFlight ==
        // false` and no-op, so a late completion is a harmless no-op rather
        // than reopening the dialog or launching a stale installer.
      },
    );
    _updatStartUpdate?.call();
  }

  void _popDownloadDialogIfOpen() {
    if (!_downloadDialogOpen) return;
    _downloadDialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  /// Download finished: run the terminal sequence (launch installer → flush
  /// tabs → quit). Only the launch-failure outcome returns control here —
  /// the app must then stay fully usable, with the installer path surfaced.
  Future<void> _finishInAppUpdate() async {
    final installer = _installerFile;
    if (installer == null) return;
    TabsBloc? tabs;
    try {
      tabs = context.read<TabsBloc>();
    } on Object {
      tabs = null; // Tests may mount the gate without a TabsBloc.
    }
    final launcher = widget.debugInstallerLauncher ?? launchDownloadedInstaller;
    final result = await finishInAppUpdate(
      launchInstaller: () => launcher(installer),
      flushTabs: () async => tabs?.close(),
      quit: widget.debugQuit ?? _exitApp,
    );
    if (!mounted || result != UpdateFinishResult.launchFailed) return;
    _popDownloadDialogIfOpen();
    showAppSnackBar(
      context,
      'Update downloaded to ${installer.path}, but it could not be opened — '
      'run it manually.',
    );
  }

  static Never _exitApp() => exit(0);

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
          if (_inAppDownloadInFlight) {
            // The in-app download failed (not a version check): unblock the
            // UI and keep the app running.
            _downloadWatchdog?.cancel();
            _inAppDownloadInFlight = false;
            _popDownloadDialogIfOpen();
            showAppSnackBar(context, "Couldn't download the update.");
          } else if (controller.manualInFlight) {
            // A failed *check* only matters to surface when the user
            // explicitly pressed "Check for updates"; background checks stay
            // quiet.
            controller.manualInFlight = false;
            showAppSnackBar(context, "Couldn't check for updates.");
          }
        case UpdatePhase.readyToInstall:
          if (_inAppDownloadInFlight) {
            _downloadWatchdog?.cancel();
            _inAppDownloadInFlight = false;
            unawaited(_finishInAppUpdate());
          }
        // downloading is surfaced by the blocking dialog _startInAppDownload
        // already pushed; the rest need no side effects.
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

/// Outcome of [finishInAppUpdate]: tells the gate (and tests) apart "the app
/// is about to exit" from "installer launch failed, keep the app alive".
enum UpdateFinishResult { quitting, launchFailed }

/// Terminal sequence of the in-app update: launch the downloaded installer,
/// best-effort flush unsaved tabs, then quit.
///
/// Launch comes FIRST deliberately — flushing first would `close()` the
/// TabsBloc, and if the launch then failed the app would sit open with dead
/// tab persistence. A failed launch here leaves the app fully intact; a
/// failed flush never blocks the quit (losing <10 s of tab edits beats
/// stranding the update with the installer already running).
@visibleForTesting
Future<UpdateFinishResult> finishInAppUpdate({
  required Future<void> Function() launchInstaller,
  required Future<void> Function() flushTabs,
  required void Function() quit,
}) async {
  try {
    await launchInstaller();
  } on Object {
    return UpdateFinishResult.launchFailed;
  }
  try {
    await flushTabs();
  } on Object catch (e) {
    // Best-effort only — see doc above.
    debugPrint('Tab flush before update install failed: $e');
  }
  quit();
  return UpdateFinishResult.quitting;
}

/// Launches the downloaded installer. Windows: start the Inno Setup `.exe`
/// detached. Linux: `chmod +x` first, then start the AppImage detached — a
/// fresh download has no execute bit, so a plain file-open would not run it.
/// Throws on failure so [finishInAppUpdate] can keep the app alive.
@visibleForTesting
Future<void> launchDownloadedInstaller(File installer) async {
  if (Platform.isLinux) {
    final chmod = await Process.run('chmod', ['+x', installer.path]);
    if (chmod.exitCode != 0) {
      throw ProcessException(
        'chmod',
        ['+x', installer.path],
        chmod.stderr.toString(),
        chmod.exitCode,
      );
    }
  }
  await Process.start(
    installer.path,
    const <String>[],
    mode: ProcessStartMode.detached,
  );
}
