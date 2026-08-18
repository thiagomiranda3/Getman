// Widget tests for the io UpdateGate: the two silent-failure bugs (C1/C2)
// where a failed check or a null-changelog release never surfaced anything
// to the user because `updat`'s own `.then`/`.catchError` machinery only
// acts on a non-null `getLatestVersion()` result / non-null changelog; plus
// the A6 watchdog-vs-paused-frames race (a download completing while the
// window is minimized must not be declared a timeout and abandoned).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/theme/themes/brutalist/brutalist_theme.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:getman/features/updates/presentation/update_gate_io.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

/// Simulates a real check whose fetch fails end-to-end (mirrors
/// `UpdateRepositoryImpl` swallowing a network/parse error and returning
/// null) — this is the case `_getLatestVersion` must turn into a thrown
/// error rather than a silent null.
class _FailingRepo implements UpdateRepository {
  @override
  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform p) async => null;
}

class _ReleaseRepo implements UpdateRepository {
  _ReleaseRepo(this.release);
  final ReleaseInfo release;

  @override
  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform p) async => release;
}

class _MockSave extends Mock implements SaveSettingsUseCase {}

void main() {
  setUpAll(() {
    registerFallbackValue(const SettingsEntity());
    PackageInfo.setMockInitialValues(
      appName: 'getman',
      packageName: 'com.getman.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  SettingsBloc buildSettingsBloc({bool checkForUpdatesOnStartup = true}) {
    final save = _MockSave();
    when(() => save(any())).thenAnswer((_) async {});
    return SettingsBloc(
      saveSettingsUseCase: save,
      initialSettings: SettingsEntity(
        checkForUpdatesOnStartup: checkForUpdatesOnStartup,
      ),
    );
  }

  Widget harness({
    required UpdateController controller,
    required SettingsBloc bloc,
  }) {
    return MaterialApp(
      theme: brutalistTheme(Brightness.light),
      home: ChangeNotifierProvider<UpdateController>.value(
        value: controller,
        child: BlocProvider.value(
          value: bloc,
          child: const Scaffold(body: UpdateGate()),
        ),
      ),
    );
  }

  testWidgets(
    'C1: a failed manual check surfaces the error snackbar and resets '
    'manualInFlight',
    (tester) async {
      final controller = UpdateController(_FailingRepo());
      // Startup auto-check disabled: `updat` only re-invokes its status
      // callback when the terminal status *differs* from the last one it
      // saw. With a fake repo that fails/resolves with no real I/O delay, an
      // auto-check that also lands on `error` would leave the widget with no
      // observable transition for the manual check to fire against — so we
      // isolate the manual path here (the one the "CHECK FOR UPDATES" button
      // actually drives) instead of relying on the startup check to run.
      final bloc = buildSettingsBloc(checkForUpdatesOnStartup: false);

      await tester.pumpWidget(harness(controller: controller, bloc: bloc));
      await tester.pumpAndSettle();

      controller.checkNow();
      await tester.pumpAndSettle();

      expect(find.text("Couldn't check for updates."), findsOneWidget);
      expect(controller.manualInFlight, isFalse);
    },
  );

  testWidgets(
    'C2: a release with a null changelog body still prompts the update '
    'dialog',
    (tester) async {
      final controller = UpdateController(
        _ReleaseRepo(
          const ReleaseInfo(
            version: '99.0.0',
            changelog: null,
            assetUrl: 'https://example.com/getman.dmg',
          ),
        ),
      );
      final bloc = buildSettingsBloc();

      await tester.pumpWidget(harness(controller: controller, bloc: bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('update_now_button')), findsOneWidget);
    },
  );

  testWidgets(
    'regression guard: a manual check on the latest version still shows '
    'the up-to-date snackbar',
    (tester) async {
      final controller = UpdateController(
        _ReleaseRepo(
          const ReleaseInfo(version: '1.0.0', changelog: null, assetUrl: null),
        ),
      );
      // See the C1 comment above for why the startup auto-check is disabled
      // here too — this test isolates the manual "CHECK FOR UPDATES" path.
      final bloc = buildSettingsBloc(checkForUpdatesOnStartup: false);

      await tester.pumpWidget(harness(controller: controller, bloc: bloc));
      await tester.pumpAndSettle();

      controller.checkNow();
      await tester.pumpAndSettle();

      expect(find.text("You're on the latest version."), findsOneWidget);
      expect(controller.manualInFlight, isFalse);
    },
  );

  group('finishInAppUpdate', () {
    test('launches, then flushes tabs, then quits — in that order', () async {
      final calls = <String>[];
      final result = await finishInAppUpdate(
        launchInstaller: () async => calls.add('launch'),
        flushTabs: () async => calls.add('flush'),
        quit: () => calls.add('quit'),
      );
      expect(result, UpdateFinishResult.quitting);
      expect(calls, ['launch', 'flush', 'quit']);
    });

    test('a failed launch keeps the app alive: no flush, no quit', () async {
      final calls = <String>[];
      final result = await finishInAppUpdate(
        launchInstaller: () async => throw Exception('no such file'),
        flushTabs: () async => calls.add('flush'),
        quit: () => calls.add('quit'),
      );
      expect(result, UpdateFinishResult.launchFailed);
      expect(calls, isEmpty);
    });

    test('a failed tab flush still quits (best-effort flush)', () async {
      var quitCalled = false;
      final result = await finishInAppUpdate(
        launchInstaller: () async {},
        flushTabs: () async => throw Exception('hive is gone'),
        quit: () => quitCalled = true,
      );
      expect(result, UpdateFinishResult.quitting);
      expect(quitCalled, isTrue);
    });
  });

  testWidgets(
    'in-app flow: confirm shows the blocking dialog; a failed download pops '
    'it, shows the error snackbar, and never quits',
    (tester) async {
      final controller = UpdateController(
        _ReleaseRepo(
          const ReleaseInfo(
            version: '99.0.0',
            changelog: null,
            assetUrl: 'https://example.com/getman-99.0.0.exe',
          ),
        ),
      );
      final bloc = buildSettingsBloc();
      var quitCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: ChangeNotifierProvider<UpdateController>.value(
            value: controller,
            child: BlocProvider.value(
              value: bloc,
              child: Scaffold(
                body: UpdateGate(
                  debugInstallsInApp: true,
                  debugQuit: () => quitCalled = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Startup check found 99.0.0 → update dialog prompted.
      await tester.tap(find.byKey(const ValueKey('update_now_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DOWNLOAD AND CLOSE'));
      await tester.pump();

      // The blocking dialog is up while updat downloads.
      expect(find.text('DOWNLOADING UPDATE…'), findsOneWidget);

      // flutter_test's HttpClient 400s every request, so the download fails:
      // dialog popped, snackbar shown, app still alive.
      await tester.pumpAndSettle();
      expect(find.text('DOWNLOADING UPDATE…'), findsNothing);
      expect(find.text("Couldn't download the update."), findsOneWidget);
      expect(quitCalled, isFalse);
    },
  );

  group('A6: download-stall watchdog vs paused frames', () {
    const assetUrl = 'https://example.com/getman-99.0.0.exe';

    /// Installs the dart:io fakes that let updat's real in-process download
    /// succeed (or hang) under FakeAsync: an [HttpOverrides] serving the
    /// release asset without the network, and an [IOOverrides] whose fake
    /// installer [File] completes `writeAsBytes` without real disk I/O
    /// (real file futures never resolve inside the test's fake async zone).
    _InstallerIOOverrides installOverrides({required bool hangDownload}) {
      final previousHttp = HttpOverrides.current;
      HttpOverrides.global = _AssetHttpOverrides(
        assetUrl: assetUrl,
        hang: hangDownload,
      );
      final ioOverrides = _InstallerIOOverrides();
      IOOverrides.global = ioOverrides;
      addTearDown(() {
        HttpOverrides.global = previousHttp;
        IOOverrides.global = null;
      });
      return ioOverrides;
    }

    Future<void> startInAppDownload(
      WidgetTester tester, {
      required UpdateController controller,
      required SettingsBloc bloc,
      required void Function(File installer) onLaunch,
      required void Function() onQuit,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: brutalistTheme(Brightness.light),
          home: ChangeNotifierProvider<UpdateController>.value(
            value: controller,
            child: BlocProvider.value(
              value: bloc,
              child: Scaffold(
                body: UpdateGate(
                  debugInstallsInApp: true,
                  debugInstallerLauncher: (installer) async =>
                      onLaunch(installer),
                  debugQuit: onQuit,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('update_now_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DOWNLOAD AND CLOSE'));
      await tester.pump();
      expect(find.text('DOWNLOADING UPDATE…'), findsOneWidget);
    }

    testWidgets(
      'a download that completes while no frames are pumped (minimized '
      'window) cancels the watchdog instead of being declared a timeout',
      (tester) async {
        // updat reports readyToInstall only from its build(), while the
        // 10-minute stall watchdog is a frame-independent wall-clock Timer.
        // Simulate the window being minimized mid-download (frames paused on
        // GTK) with `binding.delayed`, which elapses the fake clock WITHOUT
        // pumping frames. The completion must survive crossing the watchdog
        // deadline frameless, and the finish sequence must run once frames
        // resume.
        final ioOverrides = installOverrides(hangDownload: false);
        final controller = UpdateController(
          _ReleaseRepo(
            const ReleaseInfo(
              version: '99.0.0',
              changelog: null,
              assetUrl: assetUrl,
            ),
          ),
        );
        final launchedPaths = <String>[];
        var quitCalled = false;

        await startInAppDownload(
          tester,
          controller: controller,
          bloc: buildSettingsBloc(),
          onLaunch: (installer) => launchedPaths.add(installer.path),
          onQuit: () => quitCalled = true,
        );

        // Window "minimizes" here: no frames from now until restore. 4 s of
        // clock lets _downloadLocationFor's 3 s getDownloadsDirectory
        // timeout fire and the mocked download complete — the installer is
        // fully written BEFORE the watchdog deadline.
        await tester.binding.delayed(const Duration(seconds: 4));
        expect(ioOverrides.installer?.written, isNotNull);

        // Cross the 10-minute watchdog deadline, still frameless.
        await tester.binding.delayed(const Duration(minutes: 11));

        // "Restore" the window: the first frame delivers the parked
        // readyToInstall. First-frame assert — no timeout, no error.
        await tester.pump();
        expect(find.text('The update download timed out.'), findsNothing);
        expect(find.text("Couldn't download the update."), findsNothing);

        // Drain the finish sequence (launch installer → flush tabs → quit).
        // No pumpAndSettle past this point: on success the app "quits" with
        // the download dialog (indeterminate spinner) still up.
        await tester.pump();
        await tester.pump();
        expect(launchedPaths, hasLength(1));
        expect(launchedPaths.single, contains('getman-99.0.0.exe'));
        expect(quitCalled, isTrue);
      },
    );

    testWidgets(
      'a genuinely stalled download still times out (the deferred verdict '
      'needs one frame, not a completion)',
      (tester) async {
        // Guards the original stall protection now that the watchdog's
        // verdict is deferred by a frame: a download whose http.get never
        // resolves must still pop the dialog and surface the timeout.
        installOverrides(hangDownload: true);
        final controller = UpdateController(
          _ReleaseRepo(
            const ReleaseInfo(
              version: '99.0.0',
              changelog: null,
              assetUrl: assetUrl,
            ),
          ),
        );
        final launchedPaths = <String>[];
        var quitCalled = false;

        await startInAppDownload(
          tester,
          controller: controller,
          bloc: buildSettingsBloc(),
          onLaunch: (installer) => launchedPaths.add(installer.path),
          onQuit: () => quitCalled = true,
        );

        // Let the download start (3 s directory-lookup timeout) and hang,
        // then cross the watchdog deadline with frames running normally.
        // Settling is safe once the pop is issued: the dialog's exit
        // animation completes and unmounts the indeterminate spinner.
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(minutes: 11));
        await tester.pumpAndSettle();

        expect(find.text('The update download timed out.'), findsOneWidget);
        expect(find.text('DOWNLOADING UPDATE…'), findsNothing);
        expect(launchedPaths, isEmpty);
        expect(quitCalled, isFalse);
      },
    );
  });
}

/// Serves the release asset from memory so updat's real downloader (a plain
/// `package:http` GET over `dart:io`'s [HttpClient]) succeeds — or hangs
/// forever when [hang] is true — inside the widget test's fake async zone.
/// Every other URL gets a 400, mirroring flutter_test's default mock client.
class _AssetHttpOverrides extends HttpOverrides {
  _AssetHttpOverrides({required this.assetUrl, required this.hang});

  final String assetUrl;
  final bool hang;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(assetUrl: assetUrl, hang: hang);
}

class _FakeHttpClient extends Fake implements HttpClient {
  _FakeHttpClient({required this.assetUrl, required this.hang});

  final String assetUrl;
  final bool hang;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final isAsset = url.toString() == assetUrl;
    return _FakeHttpClientRequest(
      statusCode: isAsset ? 200 : 400,
      hang: hang && isAsset,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeHttpClientRequest extends Fake implements HttpClientRequest {
  _FakeHttpClientRequest({required this.statusCode, required this.hang});

  final int statusCode;
  final bool hang;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<HttpClientResponse> close() => hang
      ? Completer<HttpClientResponse>().future
      : Future.value(_FakeHttpClientResponse(statusCode: statusCode));
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({required this.statusCode});

  static const _bytes = <int>[0x47, 0x4d, 0x4e]; // arbitrary payload

  @override
  final int statusCode;

  @override
  int get contentLength => _bytes.length;

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => 'OK';

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeHttpHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String name, List<String> values) action) {}
}

/// Routes only the installer path to an in-memory [File] (real file futures
/// never resolve under FakeAsync); everything else stays real dart:io.
final class _InstallerIOOverrides extends IOOverrides {
  _FakeInstallerFile? installer;

  @override
  File createFile(String path) {
    if (path.contains('getman-99.0.0')) {
      return installer ??= _FakeInstallerFile(path);
    }
    return super.createFile(path);
  }
}

class _FakeInstallerFile extends Fake implements File {
  _FakeInstallerFile(this.path);

  @override
  final String path;

  List<int>? written;

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    written = bytes;
    return this;
  }
}
