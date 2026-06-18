# Auto-Update Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a startup + on-demand GitHub-release update check that prompts the user (Update now / Skip this version / Later) and downloads + opens a real per-platform installer, with a settings toggle and a manual "Check for updates" button.

**Architecture:** New `lib/features/updates/` feature (domain/data/presentation, clean architecture). The `updat` package drives the version-check state machine + download via one invisible `UpdatWidget` mounted in `MainScreen`; a `UpdateController` (exposed via `RepositoryProvider`, the `UrlFocusRegistry` pattern) bridges its callbacks to a themed dialog and a Settings button. Only the io-specific gate imports `updat`/`dart:io`; the web build uses a stub via conditional import. CI release artifacts become real installers (.dmg / Inno setup.exe / AppImage).

**Tech Stack:** Flutter, flutter_bloc, get_it, hive_ce, dio, `updat ^1.4.0`, `package_info_plus`, `path_provider`. Tests: flutter_test, bloc_test, mocktail.

## Global Constraints

- Flutter SDK is pinned via `.fvmrc` — always invoke as `fvm flutter ...` / `fvm dart ...`, never plain `flutter`/`dart`.
- Imports are `package:getman/...` everywhere (no relative imports; enforced by `always_use_package_imports` + `directives_ordering`).
- Domain layer: zero imports from `data/` or Flutter UI — pure Dart + `equatable` only.
- BLoCs depend on abstract repository types, never `...Impl` / Hive / Dio. BLoCs must NOT import `package:flutter/...` (trips `bloc_lint`'s `avoid_flutter_imports`); use `dart:developer`'s `log(msg, name: '...')` for bloc logging.
- Widgets never call `sl<T>()`/`GetIt` (custom_lint `avoid_get_it_in_widgets`); reach services via `BlocProvider` / `RepositoryProvider` / constructor injection.
- No hardcoded sizes/colors/radii/weights in widgets — read `context.appLayout` / `appPalette` / `appShape` / `appTypography` / `appDecoration`. No `Colors.black/white/red` literals outside `lib/core/theme/` (custom_lint `avoid_hardcoded_brand_colors`).
- `updat` imports `dart:io`; Getman has a web build target. **Only `update_gate_io.dart` may import `updat` or `dart:io`.** Everything else uses our own `UpdatePhase` enum and `dio`.
- Never renumber an existing Hive `typeId`/`HiveField`. `SettingsModel` (typeId 0) next free `HiveField` is **25**.
- After any `@HiveField`/`@HiveType` change: `fvm dart run build_runner build --delete-conflicting-outputs`.
- GitHub repo for release checks: `thiagomiranda3/Getman`. Release asset name suffixes: macOS `-macos-arm64.dmg`, Windows `-windows-x64-setup.exe`, Linux `-linux-x86_64.AppImage`.
- App identity: product name `getman`, bundle id `br.com.tommiranda.getman`, outputs `getman.app` / `getman.exe` / `getman`.
- **Done-bar (all must pass before any task is "done"):** `fvm flutter analyze` (0 issues), `fvm dart run custom_lint` (0 issues), `fvm dart run bloc_tools:bloc lint lib` (0 issues), `fvm dart format` clean, `fvm flutter test` 100% green. These are independent passes.

---

### Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml:9-29` (dependencies block)

- [ ] **Step 1: Add the three runtime dependencies**

In `pubspec.yaml` under `dependencies:` (keep alphabetical ordering), add:

```yaml
  package_info_plus: ^8.0.0
  path_provider: ^2.1.5
  updat: ^1.4.0
```

- [ ] **Step 2: Resolve dependencies**

Run: `fvm flutter pub get`
Expected: resolves with no version conflicts (updat needs `sdk >=3.4.0 <4.0.0`; ours is `^3.11.4`).

- [ ] **Step 3: Verify the analyzer still passes with the new deps present**

Run: `fvm flutter analyze`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build(updates): add updat, package_info_plus, path_provider deps"
```

---

### Task 2: Settings persistence — new Hive fields + entity

**Files:**
- Modify: `lib/features/settings/data/models/settings_model.dart`
- Modify: `lib/features/settings/domain/entities/settings_entity.dart`
- Regenerate: `lib/features/settings/data/models/settings_model.g.dart` (build_runner)
- Test: `test/features/settings/data/models/settings_model_test.dart`

**Interfaces:**
- Produces: `SettingsEntity.checkForUpdatesOnStartup` (bool, default `true`), `SettingsEntity.skippedUpdateVersion` (String?, default null). `SettingsEntity.copyWith({bool? checkForUpdatesOnStartup, Object? skippedUpdateVersion = _unchanged})`. Same fields on `SettingsModel` with `@HiveField(25, defaultValue: true)` and `@HiveField(26)`.

- [ ] **Step 1: Write the failing test**

Append to `test/features/settings/data/models/settings_model_test.dart` a test asserting round-trip of the new fields (mirror the existing tests' structure in that file — read the file first to match its `group`/helpers):

```dart
test('round-trips checkForUpdatesOnStartup and skippedUpdateVersion', () {
  const entity = SettingsEntity(
    checkForUpdatesOnStartup: false,
    skippedUpdateVersion: '1.2.3',
  );
  final model = SettingsModel.fromEntity(entity);
  expect(model.checkForUpdatesOnStartup, isFalse);
  expect(model.skippedUpdateVersion, '1.2.3');

  final back = model.toEntity();
  expect(back.checkForUpdatesOnStartup, isFalse);
  expect(back.skippedUpdateVersion, '1.2.3');
});

test('checkForUpdatesOnStartup defaults to true', () {
  expect(const SettingsEntity().checkForUpdatesOnStartup, isTrue);
  expect(const SettingsEntity().skippedUpdateVersion, isNull);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/settings/data/models/settings_model_test.dart`
Expected: FAIL — `checkForUpdatesOnStartup` is not defined.

- [ ] **Step 3: Add the fields to `SettingsEntity`**

In `settings_entity.dart`:
- Add to the constructor params (after `saveLargeResponsesInHistory = true,`): `this.checkForUpdatesOnStartup = true,` and `this.skippedUpdateVersion,`.
- Add the field declarations:
```dart
  /// When `true` (default), Getman checks GitHub Releases once on startup and
  /// prompts if a newer version exists. Off = no automatic check (manual only).
  final bool checkForUpdatesOnStartup;

  /// The version string the user chose "Skip this version" for; the startup
  /// check won't prompt again for exactly this version. `null` = nothing skipped.
  final String? skippedUpdateVersion;
```
- In `copyWith`, add params `bool? checkForUpdatesOnStartup,` and `Object? skippedUpdateVersion = _unchanged,`; in the returned `SettingsEntity(...)` add:
```dart
      checkForUpdatesOnStartup:
          checkForUpdatesOnStartup ?? this.checkForUpdatesOnStartup,
      skippedUpdateVersion: identical(skippedUpdateVersion, _unchanged)
          ? this.skippedUpdateVersion
          : skippedUpdateVersion as String?,
```
- Add both to `props` (end of the list).

- [ ] **Step 4: Add the fields to `SettingsModel`**

In `settings_model.dart`:
- Constructor: add `this.checkForUpdatesOnStartup = true,` and `this.skippedUpdateVersion,`.
- `fromJson`: add `checkForUpdatesOnStartup: json['checkForUpdatesOnStartup'] as bool? ?? true,` and `skippedUpdateVersion: json['skippedUpdateVersion'] as String?,`.
- `fromEntity`: add `checkForUpdatesOnStartup: entity.checkForUpdatesOnStartup,` and `skippedUpdateVersion: entity.skippedUpdateVersion,`.
- Field declarations (after `saveLargeResponsesInHistory`):
```dart
  @HiveField(25, defaultValue: true)
  bool checkForUpdatesOnStartup;

  @HiveField(26)
  String? skippedUpdateVersion;
```
- `copyWith`: add `bool? checkForUpdatesOnStartup,` and `Object? skippedUpdateVersion = _unchanged,` params and in the body:
```dart
      checkForUpdatesOnStartup:
          checkForUpdatesOnStartup ?? this.checkForUpdatesOnStartup,
      skippedUpdateVersion: identical(skippedUpdateVersion, _unchanged)
          ? this.skippedUpdateVersion
          : skippedUpdateVersion as String?,
```
- `toJson`: add `'checkForUpdatesOnStartup': checkForUpdatesOnStartup,` and `'skippedUpdateVersion': skippedUpdateVersion,`.
- `toEntity`: add `checkForUpdatesOnStartup: checkForUpdatesOnStartup,` and `skippedUpdateVersion: skippedUpdateVersion,`.

- [ ] **Step 5: Regenerate the Hive adapter**

Run: `fvm dart run build_runner build --delete-conflicting-outputs`
Expected: `settings_model.g.dart` regenerated with read/write for fields 25 and 26.

- [ ] **Step 6: Run tests + format**

Run: `fvm flutter test test/features/settings/data/models/settings_model_test.dart && fvm dart format lib test`
Expected: PASS; formatter clean.

- [ ] **Step 7: Commit**

```bash
git add lib/features/settings/data/models/settings_model.dart lib/features/settings/data/models/settings_model.g.dart lib/features/settings/domain/entities/settings_entity.dart test/features/settings/data/models/settings_model_test.dart
git commit -m "feat(settings): persist checkForUpdatesOnStartup + skippedUpdateVersion"
```

---

### Task 3: Settings bloc events for the update preferences

**Files:**
- Modify: `lib/features/settings/presentation/bloc/settings_event.dart`
- Modify: `lib/features/settings/presentation/bloc/settings_bloc.dart`
- Test: `test/features/settings/presentation/bloc/settings_bloc_test.dart`

**Interfaces:**
- Produces: `UpdateCheckForUpdatesOnStartup({required bool enabled})`, `SetSkippedUpdateVersion(String? version)` events; `SettingsBloc` handles both (persist + emit).

- [ ] **Step 1: Write the failing test**

Append to `test/features/settings/presentation/bloc/settings_bloc_test.dart` (read the file first; reuse its existing `build`/mock setup — it already mocks `SaveSettingsUseCase`):

```dart
blocTest<SettingsBloc, SettingsState>(
  'UpdateCheckForUpdatesOnStartup persists and emits',
  build: buildBloc, // reuse the file's existing builder helper
  act: (bloc) =>
      bloc.add(const UpdateCheckForUpdatesOnStartup(enabled: false)),
  expect: () => [
    isA<SettingsState>().having(
      (s) => s.settings.checkForUpdatesOnStartup,
      'checkForUpdatesOnStartup',
      false,
    ),
  ],
);

blocTest<SettingsBloc, SettingsState>(
  'SetSkippedUpdateVersion stores then clears the version',
  build: buildBloc,
  act: (bloc) => bloc
    ..add(const SetSkippedUpdateVersion('2.0.0'))
    ..add(const SetSkippedUpdateVersion(null)),
  expect: () => [
    isA<SettingsState>().having(
      (s) => s.settings.skippedUpdateVersion, 'skipped', '2.0.0'),
    isA<SettingsState>().having(
      (s) => s.settings.skippedUpdateVersion, 'skipped', isNull),
  ],
);
```

If the test file has no shared `buildBloc` helper, construct the bloc inline exactly as the existing tests in that file do.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/settings/presentation/bloc/settings_bloc_test.dart`
Expected: FAIL — events undefined.

- [ ] **Step 3: Add the events**

Append to `settings_event.dart`:

```dart
class UpdateCheckForUpdatesOnStartup extends SettingsEvent {
  const UpdateCheckForUpdatesOnStartup({required this.enabled});
  final bool enabled;
  @override
  List<Object?> get props => [enabled];
}

class SetSkippedUpdateVersion extends SettingsEvent {
  const SetSkippedUpdateVersion(this.version);
  final String? version;
  @override
  List<Object?> get props => [version];
}
```

- [ ] **Step 4: Add the handlers**

In `settings_bloc.dart` constructor body (after `on<UpdateWorkspacePath>` block):

```dart
    on<UpdateCheckForUpdatesOnStartup>(
      (e, emit) =>
          _apply(emit, (s) => s.copyWith(checkForUpdatesOnStartup: e.enabled)),
    );
    on<SetSkippedUpdateVersion>(
      (e, emit) =>
          _apply(emit, (s) => s.copyWith(skippedUpdateVersion: e.version)),
    );
```

- [ ] **Step 5: Run tests + format**

Run: `fvm flutter test test/features/settings/presentation/bloc/settings_bloc_test.dart && fvm dart format lib test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings/presentation/bloc/settings_event.dart lib/features/settings/presentation/bloc/settings_bloc.dart test/features/settings/presentation/bloc/settings_bloc_test.dart
git commit -m "feat(settings): add update-preference events"
```

---

### Task 4: Domain — UpdatePlatform, ReleaseInfo, UpdateRepository

**Files:**
- Create: `lib/features/updates/domain/entities/release_info.dart`
- Create: `lib/features/updates/domain/repositories/update_repository.dart`
- Test: `test/features/updates/domain/entities/release_info_test.dart`

**Interfaces:**
- Produces:
  - `enum UpdatePlatform { macos, windows, linux }`
  - `class ReleaseInfo extends Equatable { const ReleaseInfo({required String version, required String? changelog, required String? assetUrl}); }` with those three final fields and `props`.
  - `abstract class UpdateRepository { Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform platform); }`

- [ ] **Step 1: Write the failing test**

Create `test/features/updates/domain/entities/release_info_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';

void main() {
  test('ReleaseInfo value equality', () {
    const a = ReleaseInfo(version: '1.1.0', changelog: 'notes', assetUrl: 'u');
    const b = ReleaseInfo(version: '1.1.0', changelog: 'notes', assetUrl: 'u');
    const c = ReleaseInfo(version: '1.2.0', changelog: 'notes', assetUrl: 'u');
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/updates/domain/entities/release_info_test.dart`
Expected: FAIL — file `release_info.dart` does not exist.

- [ ] **Step 3: Create the entity**

`lib/features/updates/domain/entities/release_info.dart`:

```dart
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
```

- [ ] **Step 4: Create the abstract repository**

`lib/features/updates/domain/repositories/update_repository.dart`:

```dart
import 'package:getman/features/updates/domain/entities/release_info.dart';

/// Fetches the latest published release for a given [UpdatePlatform].
/// Implementations return `null` on any failure (offline, rate-limited, no
/// matching asset) — the caller treats null as "no update info available".
abstract class UpdateRepository {
  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform platform);
}
```

- [ ] **Step 5: Run test + format**

Run: `fvm flutter test test/features/updates/domain/entities/release_info_test.dart && fvm dart format lib test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/updates/domain test/features/updates/domain
git commit -m "feat(updates): add ReleaseInfo entity + UpdateRepository contract"
```

---

### Task 5: Data — GitHub release data source

**Files:**
- Create: `lib/features/updates/data/datasources/github_release_data_source.dart`
- Test: `test/features/updates/data/datasources/github_release_data_source_test.dart`

**Interfaces:**
- Consumes: `ReleaseInfo`, `UpdatePlatform`.
- Produces:
  - `class GithubReleaseDataSource { GithubReleaseDataSource({Dio? dio}); Future<ReleaseInfo> fetchLatestRelease(UpdatePlatform platform); }`
  - throws on HTTP/parse error (the repository in Task 6 catches it).
  - asset matching: macOS suffix `-macos-arm64.dmg`, windows `-windows-x64-setup.exe`, linux `-linux-x86_64.AppImage`.

- [ ] **Step 1: Write the failing test**

Create `test/features/updates/data/datasources/github_release_data_source_test.dart`. Use a `MockAdapter`-free approach by injecting a `Dio` whose `httpClientAdapter` returns canned JSON, or stub via `mocktail` on a `Dio` mock. Simplest with mocktail:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/updates/data/datasources/github_release_data_source.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

Response<dynamic> _resp(Map<String, dynamic> json) => Response<dynamic>(
  requestOptions: RequestOptions(path: '/'),
  statusCode: 200,
  data: json,
);

const _sampleJson = {
  'tag_name': 'v1.1.0',
  'body': 'Release notes here',
  'assets': [
    {
      'name': 'getman-1.1.0-macos-arm64.dmg',
      'browser_download_url': 'https://example.com/mac.dmg',
    },
    {
      'name': 'getman-1.1.0-windows-x64-setup.exe',
      'browser_download_url': 'https://example.com/win.exe',
    },
    {
      'name': 'getman-1.1.0-linux-x86_64.AppImage',
      'browser_download_url': 'https://example.com/linux.AppImage',
    },
  ],
};

void main() {
  late _MockDio dio;
  late GithubReleaseDataSource ds;

  setUp(() {
    dio = _MockDio();
    ds = GithubReleaseDataSource(dio: dio);
    when(() => dio.get<dynamic>(any())).thenAnswer((_) async => _resp(_sampleJson));
  });

  test('parses tag (strips v), body, and macOS asset', () async {
    final info = await ds.fetchLatestRelease(UpdatePlatform.macos);
    expect(info.version, '1.1.0');
    expect(info.changelog, 'Release notes here');
    expect(info.assetUrl, 'https://example.com/mac.dmg');
  });

  test('selects the windows setup.exe asset', () async {
    final info = await ds.fetchLatestRelease(UpdatePlatform.windows);
    expect(info.assetUrl, 'https://example.com/win.exe');
  });

  test('selects the linux AppImage asset', () async {
    final info = await ds.fetchLatestRelease(UpdatePlatform.linux);
    expect(info.assetUrl, 'https://example.com/linux.AppImage');
  });

  test('assetUrl is null when no asset matches the platform', () async {
    when(() => dio.get<dynamic>(any())).thenAnswer(
      (_) async => _resp({'tag_name': 'v1.1.0', 'body': null, 'assets': []}),
    );
    final info = await ds.fetchLatestRelease(UpdatePlatform.macos);
    expect(info.assetUrl, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/updates/data/datasources/github_release_data_source_test.dart`
Expected: FAIL — data source file does not exist.

- [ ] **Step 3: Implement the data source**

`lib/features/updates/data/datasources/github_release_data_source.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';

/// Hits the GitHub "latest release" REST endpoint with a dedicated [Dio] (no
/// app interceptors/proxy/cookies — a user's network config must not be able to
/// break the updater). Throws on HTTP/parse failure; the repository wraps this.
class GithubReleaseDataSource {
  GithubReleaseDataSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _latestReleaseUrl =
      'https://api.github.com/repos/thiagomiranda3/Getman/releases/latest';

  /// The asset-name suffix Getman publishes for each platform.
  static String _assetSuffix(UpdatePlatform platform) => switch (platform) {
    UpdatePlatform.macos => '-macos-arm64.dmg',
    UpdatePlatform.windows => '-windows-x64-setup.exe',
    UpdatePlatform.linux => '-linux-x86_64.AppImage',
  };

  Future<ReleaseInfo> fetchLatestRelease(UpdatePlatform platform) async {
    final res = await _dio.get<dynamic>(_latestReleaseUrl);
    final data = res.data as Map<String, dynamic>;

    final tag = data['tag_name'] as String? ?? '';
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    final changelog = data['body'] as String?;

    final assets = (data['assets'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final suffix = _assetSuffix(platform);
    String? assetUrl;
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.endsWith(suffix)) {
        assetUrl = asset['browser_download_url'] as String?;
        break;
      }
    }

    return ReleaseInfo(
      version: version,
      changelog: changelog,
      assetUrl: assetUrl,
    );
  }
}
```

- [ ] **Step 4: Run test + format**

Run: `fvm flutter test test/features/updates/data/datasources/github_release_data_source_test.dart && fvm dart format lib test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/updates/data/datasources test/features/updates/data/datasources
git commit -m "feat(updates): GitHub release data source with per-platform asset match"
```

---

### Task 6: Data — UpdateRepositoryImpl (null on failure)

**Files:**
- Create: `lib/features/updates/data/repositories/update_repository_impl.dart`
- Test: `test/features/updates/data/repositories/update_repository_impl_test.dart`

**Interfaces:**
- Consumes: `GithubReleaseDataSource`, `UpdateRepository`, `ReleaseInfo`, `UpdatePlatform`.
- Produces: `class UpdateRepositoryImpl implements UpdateRepository { UpdateRepositoryImpl(this.dataSource); }` — returns the data source's `ReleaseInfo` on success, `null` on any thrown error.

- [ ] **Step 1: Write the failing test**

Create `test/features/updates/data/repositories/update_repository_impl_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/updates/data/datasources/github_release_data_source.dart';
import 'package:getman/features/updates/data/repositories/update_repository_impl.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:mocktail/mocktail.dart';

class _MockDataSource extends Mock implements GithubReleaseDataSource {}

void main() {
  setUpAll(() => registerFallbackValue(UpdatePlatform.macos));

  late _MockDataSource ds;
  late UpdateRepositoryImpl repo;

  setUp(() {
    ds = _MockDataSource();
    repo = UpdateRepositoryImpl(ds);
  });

  test('returns ReleaseInfo on success', () async {
    when(() => ds.fetchLatestRelease(any())).thenAnswer(
      (_) async =>
          const ReleaseInfo(version: '1.1.0', changelog: 'x', assetUrl: 'u'),
    );
    final info = await repo.fetchLatestRelease(UpdatePlatform.macos);
    expect(info?.version, '1.1.0');
  });

  test('returns null when the data source throws', () async {
    when(() => ds.fetchLatestRelease(any())).thenThrow(Exception('offline'));
    final info = await repo.fetchLatestRelease(UpdatePlatform.macos);
    expect(info, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/updates/data/repositories/update_repository_impl_test.dart`
Expected: FAIL — impl does not exist.

- [ ] **Step 3: Implement the repository**

`lib/features/updates/data/repositories/update_repository_impl.dart`:

```dart
import 'dart:developer';

import 'package:getman/features/updates/data/datasources/github_release_data_source.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';

class UpdateRepositoryImpl implements UpdateRepository {
  UpdateRepositoryImpl(this.dataSource);

  final GithubReleaseDataSource dataSource;

  @override
  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform platform) async {
    try {
      return await dataSource.fetchLatestRelease(platform);
    } catch (e) {
      // Any failure (offline, rate-limit, malformed JSON) => no update info.
      log('Update check failed: $e', name: 'UpdateRepository');
      return null;
    }
  }
}
```

- [ ] **Step 4: Run test + format**

Run: `fvm flutter test test/features/updates/data/repositories/update_repository_impl_test.dart && fvm dart format lib test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/updates/data/repositories test/features/updates/data/repositories
git commit -m "feat(updates): UpdateRepositoryImpl returns null on any failure"
```

---

### Task 7: Presentation — UpdatePhase + version compare + shouldPrompt

**Files:**
- Create: `lib/features/updates/presentation/update_phase.dart`
- Create: `lib/features/updates/presentation/update_decision.dart`
- Test: `test/features/updates/presentation/update_decision_test.dart`

**Interfaces:**
- Produces:
  - `enum UpdatePhase { idle, checking, upToDate, available, downloading, readyToInstall, error, dismissed }`
  - `bool isNewerVersion(String latest, String current)` — true iff `latest` semver > `current` (lenient parse: split on `.`, numeric compare, missing parts = 0; on parse failure return false).
  - `bool shouldPromptForUpdate({required bool autoCheck, required String? latest, required String current, required String? skipped, required bool manual})` per the spec §6.3 rules.

- [ ] **Step 1: Write the failing test**

Create `test/features/updates/presentation/update_decision_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/updates/presentation/update_decision.dart';

void main() {
  group('isNewerVersion', () {
    test('detects a newer patch/minor/major', () {
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });
    test('equal or older is not newer', () {
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
    });
    test('malformed versions are not newer', () {
      expect(isNewerVersion('abc', '1.0.0'), isFalse);
    });
  });

  group('shouldPromptForUpdate', () {
    bool call({
      bool autoCheck = true,
      String? latest = '1.1.0',
      String current = '1.0.0',
      String? skipped,
      bool manual = false,
    }) => shouldPromptForUpdate(
      autoCheck: autoCheck,
      latest: latest,
      current: current,
      skipped: skipped,
      manual: manual,
    );

    test('prompts on a newer version during auto-check', () {
      expect(call(), isTrue);
    });
    test('no prompt when latest is null', () {
      expect(call(latest: null), isFalse);
    });
    test('no prompt when not newer', () {
      expect(call(latest: '1.0.0'), isFalse);
    });
    test('manual check always prompts when newer (ignores skip + autoCheck)', () {
      expect(call(manual: true, autoCheck: false, skipped: '1.1.0'), isTrue);
    });
    test('auto-check off suppresses the prompt', () {
      expect(call(autoCheck: false), isFalse);
    });
    test('skipped version is not auto-prompted', () {
      expect(call(skipped: '1.1.0'), isFalse);
    });
    test('a different skipped version still prompts', () {
      expect(call(skipped: '1.0.5'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/updates/presentation/update_decision_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Create the phase enum**

`lib/features/updates/presentation/update_phase.dart`:

```dart
/// Web-safe mirror of `updat`'s `UpdatStatus`. Only `update_gate_io.dart` maps
/// between the two; everything else (controller, dialog, settings) uses this so
/// the web build never imports `updat`/`dart:io`.
enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  error,
  dismissed,
}
```

- [ ] **Step 4: Create the decision logic**

`lib/features/updates/presentation/update_decision.dart`:

```dart
/// True iff [latest] is a strictly higher dotted-numeric version than
/// [current]. Lenient: missing components count as 0; any non-numeric component
/// makes the comparison return false (we never prompt on a version we can't
/// parse).
bool isNewerVersion(String latest, String current) {
  final a = _parse(latest);
  final b = _parse(current);
  if (a == null || b == null) return false;
  final len = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

List<int>? _parse(String v) {
  final parts = v.split('.');
  final out = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p.trim());
    if (n == null) return null;
    out.add(n);
  }
  return out.isEmpty ? null : out;
}

/// Decides whether to surface the update dialog. A manual check always prompts
/// when a newer version exists (ignoring the auto-check toggle and the skipped
/// version); an automatic startup check additionally respects [autoCheck] and
/// the [skipped] version.
bool shouldPromptForUpdate({
  required bool autoCheck,
  required String? latest,
  required String current,
  required String? skipped,
  required bool manual,
}) {
  if (latest == null) return false;
  if (!isNewerVersion(latest, current)) return false;
  if (manual) return true;
  if (!autoCheck) return false;
  return latest != skipped;
}
```

- [ ] **Step 5: Run test + format**

Run: `fvm flutter test test/features/updates/presentation/update_decision_test.dart && fvm dart format lib test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/updates/presentation/update_phase.dart lib/features/updates/presentation/update_decision.dart test/features/updates/presentation/update_decision_test.dart
git commit -m "feat(updates): UpdatePhase enum + version-compare + prompt decision"
```

---

### Task 8: Presentation — UpdateController

**Files:**
- Create: `lib/features/updates/presentation/update_controller.dart`
- Test: `test/features/updates/presentation/update_controller_test.dart`

**Interfaces:**
- Consumes: `UpdateRepository`, `ReleaseInfo`, `UpdatePlatform`, `UpdatePhase`.
- Produces: `class UpdateController extends ChangeNotifier`:
  - ctor `UpdateController(this._repository)`.
  - fields: `String? currentVersion; String? latestVersion; String? changelog; UpdatePhase phase = UpdatePhase.idle; bool manualInFlight = false; ReleaseInfo? cachedRelease;`
  - command hooks set by the gate: `VoidCallback? triggerCheck; Future<void> Function()? startUpdate; VoidCallback? dismiss;`
  - `Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform platform)` → delegates to repo, stores `cachedRelease`, returns it.
  - `void checkNow()` → `manualInFlight = true; triggerCheck?.call();`
  - `void setCurrentVersion(String v)`, `void updateFromGate({UpdatePhase? phase, String? latestVersion, String? changelog})` (notifies on change).

- [ ] **Step 1: Write the failing test**

Create `test/features/updates/presentation/update_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements UpdateRepository {}

void main() {
  setUpAll(() => registerFallbackValue(UpdatePlatform.macos));

  late _MockRepo repo;
  late UpdateController controller;

  setUp(() {
    repo = _MockRepo();
    controller = UpdateController(repo);
  });

  test('fetchLatestRelease delegates to repo and caches the result', () async {
    const info = ReleaseInfo(version: '1.1.0', changelog: 'c', assetUrl: 'u');
    when(() => repo.fetchLatestRelease(any())).thenAnswer((_) async => info);

    final result = await controller.fetchLatestRelease(UpdatePlatform.macos);
    expect(result, info);
    expect(controller.cachedRelease, info);
  });

  test('checkNow sets manualInFlight and invokes triggerCheck', () {
    var called = false;
    controller.triggerCheck = () => called = true;
    controller.checkNow();
    expect(controller.manualInFlight, isTrue);
    expect(called, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/updates/presentation/update_controller_test.dart`
Expected: FAIL — controller does not exist.

- [ ] **Step 3: Implement the controller**

`lib/features/updates/presentation/update_controller.dart`:

```dart
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

  // Set by the gate each build (captured from `updat`'s builder callbacks).
  VoidCallback? triggerCheck;
  Future<void> Function()? startUpdate;
  VoidCallback? dismiss;

  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform platform) async {
    cachedRelease = await _repository.fetchLatestRelease(platform);
    return cachedRelease;
  }

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
    if (latestVersion != this.latestVersion) {
      this.latestVersion = latestVersion;
      changed = true;
    }
    if (changelog != this.changelog) {
      this.changelog = changelog;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}
```

- [ ] **Step 4: Run test + format**

Run: `fvm flutter test test/features/updates/presentation/update_controller_test.dart && fvm dart format lib test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/updates/presentation/update_controller.dart test/features/updates/presentation/update_controller_test.dart
git commit -m "feat(updates): UpdateController command bus + release cache"
```

---

### Task 9: Presentation — Settings section widget (toggle + button)

**Files:**
- Create: `lib/features/updates/presentation/widgets/update_settings_section.dart`
- Test: `test/features/updates/presentation/widgets/update_settings_section_test.dart`

**Interfaces:**
- Consumes: `UpdateController` (via `RepositoryProvider`), `SettingsBloc` + `UpdateCheckForUpdatesOnStartup`, theme accessors, `_switch`/`_SettingRow` equivalents (this widget renders its own rows; it does NOT reuse `settings_dialog.dart`'s private helpers).
- Produces: `class UpdateSettingsSection extends StatelessWidget` — a `Column` with a toggle row (`ValueKey('check_updates_switch')`) bound to `UpdateCheckForUpdatesOnStartup`, and a row with current version + a `TextButton` (`ValueKey('check_updates_button')`, text `CHECK FOR UPDATES`) calling `context.read<UpdateController>().checkNow()`. Renders nothing (`SizedBox.shrink`) on web (`kIsWeb`).

- [ ] **Step 1: Write the failing test**

Create `test/features/updates/presentation/widgets/update_settings_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:getman/features/updates/presentation/widgets/update_settings_section.dart';
import 'package:mocktail/mocktail.dart';

class _FakeRepo implements UpdateRepository {
  @override
  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform p) async => null;
}

class _MockSave extends Mock implements SaveSettingsUseCase {}

void main() {
  setUpAll(() => registerFallbackValue(const SettingsEntity()));

  testWidgets('renders toggle + check button and dispatches toggle', (t) async {
    final save = _MockSave();
    when(() => save(any())).thenAnswer((_) async {});
    final bloc = SettingsBloc(saveSettingsUseCase: save);
    final controller = UpdateController(_FakeRepo())..setCurrentVersion('1.0.0');

    await t.pumpWidget(
      MaterialApp(
        home: RepositoryProvider.value(
          value: controller,
          child: BlocProvider.value(
            value: bloc,
            child: const Scaffold(body: UpdateSettingsSection()),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('check_updates_switch')), findsOneWidget);
    expect(find.byKey(const ValueKey('check_updates_button')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('check_updates_switch')));
    await t.pump();
    expect(bloc.state.settings.checkForUpdatesOnStartup, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/updates/presentation/widgets/update_settings_section_test.dart`
Expected: FAIL — widget does not exist.

- [ ] **Step 3: Implement the widget**

`lib/features/updates/presentation/widgets/update_settings_section.dart`. Match the visual rhythm of `settings_dialog.dart`'s rows (use `context.appLayout`, `context.appTypography`). Reference the existing `_switch`/`_SettingRow` styling but implement self-contained rows here:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';

/// GENERAL-tab settings block: "check on startup" toggle + a manual
/// "Check for updates" button. Hidden on web (no desktop updater there).
class UpdateSettingsSection extends StatelessWidget {
  const UpdateSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final layout = context.appLayout;
    final controller = context.read<UpdateController>();
    final bloc = context.read<SettingsBloc>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BlocBuilder<SettingsBloc, SettingsState>(
          buildWhen: (p, n) =>
              p.settings.checkForUpdatesOnStartup !=
              n.settings.checkForUpdatesOnStartup,
          builder: (context, state) => SwitchListTile(
            key: const ValueKey('check_updates_switch'),
            contentPadding:
                EdgeInsets.symmetric(horizontal: layout.inputPadding),
            secondary: Icon(Icons.system_update, size: layout.iconSize),
            title: Text(
              'CHECK FOR UPDATES ON STARTUP',
              style: TextStyle(
                fontSize: layout.fontSizeNormal,
                fontWeight: context.appTypography.titleWeight,
              ),
            ),
            value: state.settings.checkForUpdatesOnStartup,
            onChanged: (v) =>
                bloc.add(UpdateCheckForUpdatesOnStartup(enabled: v)),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.inputPadding,
            vertical: layout.tabSpacing,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UPDATES',
                      style: TextStyle(
                        fontSize: layout.fontSizeNormal,
                        fontWeight: context.appTypography.titleWeight,
                      ),
                    ),
                    SizedBox(height: layout.inputPaddingVertical),
                    AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) => Text(
                        controller.currentVersion == null
                            ? 'Getman'
                            : 'Getman ${controller.currentVersion}',
                        style: TextStyle(fontSize: layout.fontSizeSmall),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: layout.tabSpacing),
              TextButton(
                key: const ValueKey('check_updates_button'),
                onPressed: controller.checkNow,
                child: const Text('CHECK FOR UPDATES'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test + format + custom_lint**

Run: `fvm flutter test test/features/updates/presentation/widgets/update_settings_section_test.dart && fvm dart format lib test && fvm dart run custom_lint`
Expected: PASS; custom_lint 0 issues (no `sl`/hardcoded colors).

- [ ] **Step 5: Commit**

```bash
git add lib/features/updates/presentation/widgets/update_settings_section.dart test/features/updates/presentation/widgets/update_settings_section_test.dart
git commit -m "feat(updates): settings section (startup toggle + manual check button)"
```

---

### Task 10: Presentation — themed update dialog

**Files:**
- Create: `lib/features/updates/presentation/widgets/update_dialog.dart`
- Test: `test/features/updates/presentation/widgets/update_dialog_test.dart`

**Interfaces:**
- Consumes: `UpdateController` (listens for `phase`), `SettingsBloc` + `SetSkippedUpdateVersion`, `ResponsiveDialogScaffold` (`title`/`content`/`actions`), theme accessors.
- Produces:
  - `class UpdateDialog extends StatelessWidget` taking `{required String latestVersion, required String currentVersion, required String? changelog}`.
  - `static Future<void> show(BuildContext context, {required String latestVersion, required String currentVersion, required String? changelog, required UpdateController controller, required SettingsBloc settingsBloc})` — wraps in `RepositoryProvider.value` + `BlocProvider.value` and calls `showDialog`.
  - Three actions: SKIP THIS VERSION (`ValueKey('update_skip_button')`) → `settingsBloc.add(SetSkippedUpdateVersion(latestVersion))` + pop; LATER (`ValueKey('update_later_button')`) → `controller.dismiss?.call()` + pop; UPDATE NOW (`ValueKey('update_now_button')`) → `controller.startUpdate?.call()` (does not pop — the dialog body switches to a spinner while `phase == downloading`).

- [ ] **Step 1: Write the failing test**

Create `test/features/updates/presentation/widgets/update_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:getman/features/updates/presentation/widgets/update_dialog.dart';

class _FakeRepo implements UpdateRepository {
  @override
  Future<ReleaseInfo?> fetchLatestRelease(UpdatePlatform p) async => null;
}

void main() {
  testWidgets('renders version line + all three actions', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => const Scaffold(
            body: UpdateDialog(
              latestVersion: '1.1.0',
              currentVersion: '1.0.0',
              changelog: 'New things',
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('1.1.0'), findsWidgets);
    expect(find.byKey(const ValueKey('update_skip_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('update_later_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('update_now_button')), findsOneWidget);
  });
}
```

(Note: `UpdateController` is read via context in the real widget; for this render test the buttons must tolerate a `controller` lookup. To keep the test simple, the widget reads the controller only inside button `onPressed` callbacks — not in `build` — so the render test above needs no provider. If you instead read it in `build`, wrap the test widget in a `RepositoryProvider.value(value: UpdateController(_FakeRepo()))`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/updates/presentation/widgets/update_dialog_test.dart`
Expected: FAIL — dialog does not exist.

- [ ] **Step 3: Implement the dialog**

`lib/features/updates/presentation/widgets/update_dialog.dart`. Read `lib/core/ui/widgets/responsive_dialog.dart` first for the exact `ResponsiveDialogScaffold` API. Implementation outline (fill in fully — no placeholders):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:getman/features/updates/presentation/update_phase.dart';
import 'package:provider/provider.dart';

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    required this.latestVersion,
    required this.currentVersion,
    required this.changelog,
    super.key,
  });

  final String latestVersion;
  final String currentVersion;
  final String? changelog;

  static Future<void> show(
    BuildContext context, {
    required String latestVersion,
    required String currentVersion,
    required String? changelog,
    required UpdateController controller,
    required SettingsBloc settingsBloc,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider<UpdateController>.value(
        value: controller,
        child: BlocProvider.value(
          value: settingsBloc,
          child: UpdateDialog(
            latestVersion: latestVersion,
            currentVersion: currentVersion,
            changelog: changelog,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final controller = context.read<UpdateController>();

    return ResponsiveDialogScaffold(
      title: const Text('UPDATE AVAILABLE'),
      content: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final downloading = controller.phase == UpdatePhase.downloading;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Getman $latestVersion is available '
                '(you have $currentVersion).',
                style: TextStyle(fontSize: layout.fontSizeNormal),
              ),
              SizedBox(height: layout.tabSpacing),
              if (changelog != null && changelog!.trim().isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Text(
                      changelog!,
                      style: TextStyle(fontSize: layout.fontSizeSmall),
                    ),
                  ),
                ),
              SizedBox(height: layout.tabSpacing),
              Text(
                'Getman is not code-signed, so your OS may warn on first '
                'launch — allow it via right-click → Open (macOS) or '
                'More info → Run anyway (Windows).',
                style: TextStyle(fontSize: layout.fontSizeSmall),
              ),
              if (downloading) ...[
                SizedBox(height: layout.tabSpacing),
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: layout.tabSpacing),
                    Text(
                      'Downloading…',
                      style: TextStyle(fontSize: layout.fontSizeSmall),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        TextButton(
          key: const ValueKey('update_skip_button'),
          onPressed: () {
            context.read<SettingsBloc>().add(
              SetSkippedUpdateVersion(latestVersion),
            );
            Navigator.pop(context);
          },
          child: const Text('SKIP THIS VERSION'),
        ),
        TextButton(
          key: const ValueKey('update_later_button'),
          onPressed: () {
            controller.dismiss?.call();
            Navigator.pop(context);
          },
          child: const Text('LATER'),
        ),
        FilledButton(
          key: const ValueKey('update_now_button'),
          onPressed: () => controller.startUpdate?.call(),
          child: const Text('UPDATE NOW'),
        ),
      ],
    );
  }
}
```

NOTE: if `FilledButton` is not the established primary-action style in this codebase, match what `ConfirmDialog`/`NamePromptDialog` use for their primary action instead (read one of them first). Keep the three `ValueKey`s.

- [ ] **Step 4: Run test + format + custom_lint**

Run: `fvm flutter test test/features/updates/presentation/widgets/update_dialog_test.dart && fvm dart format lib test && fvm dart run custom_lint`
Expected: PASS; 0 custom_lint issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/updates/presentation/widgets/update_dialog.dart test/features/updates/presentation/widgets/update_dialog_test.dart
git commit -m "feat(updates): themed Update / Skip / Later dialog"
```

---

### Task 11: Presentation — the update gate (stub + conditional export + io impl)

**Files:**
- Create: `lib/features/updates/presentation/update_gate_stub.dart`
- Create: `lib/features/updates/presentation/update_gate.dart`
- Create: `lib/features/updates/presentation/update_gate_io.dart`
- Test: `test/features/updates/presentation/update_gate_stub_test.dart`

**Interfaces:**
- Consumes: `UpdateController`, `SettingsBloc`/`SettingsState`, `UpdateDialog`, `shouldPromptForUpdate`, `UpdatePhase`, `updat` (io only), `package_info_plus` (io only), `path_provider` (io only), `dart:io` (io only).
- Produces: `class UpdateGate extends StatelessWidget { const UpdateGate({Key? key}); }` available from `update_gate.dart` (stub on web, io impl on native). Renders an invisible widget; orchestrates the startup check + prompt + install launch.

- [ ] **Step 1: Write the failing test (stub)**

Create `test/features/updates/presentation/update_gate_stub_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/updates/presentation/update_gate_stub.dart';

void main() {
  testWidgets('stub gate renders nothing', (t) async {
    await t.pumpWidget(const MaterialApp(home: UpdateGate()));
    expect(find.byType(SizedBox), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/updates/presentation/update_gate_stub_test.dart`
Expected: FAIL — `update_gate_stub.dart` does not exist.

- [ ] **Step 3: Create the stub**

`lib/features/updates/presentation/update_gate_stub.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Web (and any non-`dart:io`) build: the updater is unavailable, so the gate
/// is a no-op. The real implementation lives in `update_gate_io.dart`.
class UpdateGate extends StatelessWidget {
  const UpdateGate({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
```

- [ ] **Step 4: Create the conditional export**

`lib/features/updates/presentation/update_gate.dart`:

```dart
/// Resolves to the real `updat`-driven gate on native platforms and to a no-op
/// stub on web (where `dart:io` / `updat` are unavailable).
export 'package:getman/features/updates/presentation/update_gate_stub.dart'
    if (dart.library.io) 'package:getman/features/updates/presentation/update_gate_io.dart';
```

- [ ] **Step 5: Create the io gate**

`lib/features/updates/presentation/update_gate_io.dart`. This is the only file that imports `updat`, `dart:io`, `package_info_plus`, `path_provider`. Full implementation:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:getman/features/updates/presentation/update_decision.dart';
import 'package:getman/features/updates/presentation/update_phase.dart';
import 'package:getman/features/updates/presentation/widgets/update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
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
    if (_supported) _loadVersion();
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
      getChangelog: (_, __) async => controller.cachedRelease?.changelog,
      getBinaryUrl: (_) async => controller.cachedRelease?.assetUrl ?? '',
      getDownloadFileLocation: _downloadLocation,
      callback: (status) => _onStatus(context, controller, status),
      updateChipBuilder: (context, {
        required appVersion,
        required checkForUpdate,
        required dismissUpdate,
        required latestVersion,
        required launchInstaller,
        required openDialog,
        required startUpdate,
        required status,
      }) {
        // Capture the callbacks + mapped phase, render nothing.
        controller
          ..triggerCheck = checkForUpdate
          ..startUpdate = startUpdate
          ..dismiss = dismissUpdate
          ..updateFromGate(
            phase: _mapPhase(status),
            latestVersion: latestVersion,
            changelog: controller.cachedRelease?.changelog,
          );
        return const SizedBox.shrink();
      },
    );
  }

  /// Gates the network: skip the call entirely when auto-check is off and this
  /// isn't a manual check. Returns the version string `updat` compares.
  Future<String?> _getLatestVersion(UpdateController controller) async {
    final settings = context.read<SettingsBloc>().state.settings;
    if (!controller.manualInFlight && !settings.checkForUpdatesOnStartup) {
      return null;
    }
    final release = await controller.fetchLatestRelease(_platform);
    return release?.version;
  }

  Future<File> _downloadLocation(String? version) async {
    final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    final url = context.read<UpdateController>().cachedRelease?.assetUrl ?? '';
    final ext = url.contains('.') ? url.split('.').last : 'bin';
    final path = p.join(dir.path, 'getman-$version.$ext');
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
      controller.updateFromGate(phase: mapped);

      switch (mapped) {
        case UpdatePhase.available:
          _maybePrompt(context, controller);
        case UpdatePhase.upToDate:
          if (controller.manualInFlight) {
            controller.manualInFlight = false;
            _snack(context, "You're on the latest version.");
          }
        case UpdatePhase.error:
          if (controller.manualInFlight) {
            controller.manualInFlight = false;
            _snack(context, "Couldn't check for updates.");
          }
        case UpdatePhase.readyToInstall:
          _launchInstaller();
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
    final latest = controller.latestVersion;
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
    UpdateDialog.show(
      context,
      latestVersion: latest,
      currentVersion: _currentVersion!,
      changelog: controller.cachedRelease?.changelog,
      controller: controller,
      settingsBloc: context.read<SettingsBloc>(),
    );
  }

  Future<void> _launchInstaller() async {
    final path = _downloadPath;
    if (path == null) return;
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        await Process.start(path, [], mode: ProcessStartMode.detached);
        exit(0);
      } else if (Platform.isLinux) {
        await Process.run('chmod', ['+x', path]);
        await Process.run('xdg-open', [p.dirname(path)]);
      }
    } catch (_) {
      if (mounted) _snack(context, 'Could not open the installer.');
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
```

IMPORTANT: the `updateChipBuilder` named-parameter list above must match `updat 1.4.0`'s actual signature (see `UpdatWidget.updateChipBuilder` — `context`, `latestVersion`, `appVersion`, `status`, `checkForUpdate`, `openDialog`, `startUpdate`, `launchInstaller`, `dismissUpdate`). If the analyzer reports a signature mismatch, copy the exact parameter names/types from the installed package source. Use `showAppSnackBar` if the repo's lint requires it (read `lib/core/ui/widgets/app_snack_bar.dart` — prefer `showAppSnackBar(context, message)` over a raw `SnackBar`).

- [ ] **Step 6: Run stub test + analyze + custom_lint**

Run: `fvm flutter test test/features/updates/presentation/update_gate_stub_test.dart && fvm flutter analyze && fvm dart run custom_lint`
Expected: PASS; analyzer 0 issues (this is the real check for the io gate — it has no unit test). If `showAppSnackBar` is required, switch `_snack` to it.

- [ ] **Step 7: Format + commit**

```bash
fvm dart format lib test
git add lib/features/updates/presentation/update_gate.dart lib/features/updates/presentation/update_gate_io.dart lib/features/updates/presentation/update_gate_stub.dart test/features/updates/presentation/update_gate_stub_test.dart
git commit -m "feat(updates): updat-driven gate (io) + web stub + conditional export"
```

---

### Task 12: Wire DI, providers, MainScreen mount, and the GENERAL tab

**Files:**
- Modify: `lib/core/di/injection_container.dart` (imports + registrations)
- Modify: `lib/main.dart` (RepositoryProvider for `UpdateController`)
- Modify: `lib/features/home/presentation/screens/main_screen.dart` (mount `UpdateGate`)
- Modify: `lib/features/settings/presentation/widgets/settings_dialog.dart` (append `UpdateSettingsSection` to `_generalTab`)
- Test: `test/features/settings/presentation/widgets/settings_dialog_test.dart` (extend existing)

**Interfaces:**
- Consumes: `UpdateController`, `UpdateRepositoryImpl`, `GithubReleaseDataSource`, `UpdateGate`, `UpdateSettingsSection`.

- [ ] **Step 1: Register the repository + controller in DI**

In `injection_container.dart`, add imports:
```dart
import 'package:getman/features/updates/data/datasources/github_release_data_source.dart';
import 'package:getman/features/updates/data/repositories/update_repository_impl.dart';
import 'package:getman/features/updates/domain/repositories/update_repository.dart';
import 'package:getman/features/updates/presentation/update_controller.dart';
```
In the `sl` cascade (e.g. after the Home registrations, before the trailing `UrlFocusRegistry`), add:
```dart
    // Features - Updates (GitHub release auto-update)
    ..registerLazySingleton(() => GithubReleaseDataSource())
    ..registerLazySingleton<UpdateRepository>(
      () => UpdateRepositoryImpl(sl<GithubReleaseDataSource>()),
    )
    ..registerLazySingleton(() => UpdateController(sl<UpdateRepository>()))
```
(Keep `UrlFocusRegistry.new` as the final entry with its `;`.)

- [ ] **Step 2: Expose the controller via RepositoryProvider**

In `main.dart`, add imports:
```dart
import 'package:getman/features/updates/presentation/update_controller.dart';
import 'package:provider/provider.dart';
```
Add to the `MultiRepositoryProvider.providers` list a `ChangeNotifierProvider`
(NOT a `RepositoryProvider` — `UpdateController` is a `ChangeNotifier`, and
providing a `Listenable` through `RepositoryProvider.value` trips provider's
`debugCheckInvalidValueType` assertion in debug builds). `ChangeNotifierProvider`
is a `SingleChildWidget`, so it slots into the `MultiRepositoryProvider.providers`
list directly; the `.value` constructor does NOT dispose the controller (correct —
it's a get_it singleton):
```dart
        ChangeNotifierProvider<UpdateController>.value(
          value: di.sl<UpdateController>(),
        ),
```

- [ ] **Step 3: Mount the gate in MainScreen**

Read `lib/features/home/presentation/screens/main_screen.dart`. Add import:
```dart
import 'package:getman/features/updates/presentation/update_gate.dart';
```
Find the top-level widget the screen returns (a `Scaffold`/`Stack`) and add `const UpdateGate()` as a non-visual sibling — wrap the existing body in a `Stack` only if there isn't already one; otherwise add `const UpdateGate()` to the existing children. It renders `SizedBox.shrink()`, so placement is cosmetic as long as it's below `MaterialApp` + the router Navigator (which `MainScreen` is). Example if the build returns `Scaffold(body: X)`:
```dart
Scaffold(
  body: Stack(children: [X, const UpdateGate()]),
)
```

- [ ] **Step 4: Append the section to the GENERAL tab**

In `settings_dialog.dart`, add import:
```dart
import 'package:getman/features/updates/presentation/widgets/update_settings_section.dart';
```
In `_generalTab`, add `const UpdateSettingsSection(),` as the last child of the `_pane(context, [...])` list.

- [ ] **Step 5: Extend the settings dialog test**

In `test/features/settings/presentation/widgets/settings_dialog_test.dart` (read it first to mirror its harness — it already provides a `SettingsBloc`), the harness must now also provide an `UpdateController` via `RepositoryProvider`. Add a test asserting the toggle shows on the GENERAL tab:

```dart
testWidgets('GENERAL tab shows the update settings section', (t) async {
  // ... pump the dialog using the file's existing helper, but ensure the
  // widget tree includes RepositoryProvider<UpdateController>.value(...).
  expect(find.byKey(const ValueKey('check_updates_switch')), findsOneWidget);
});
```
If the existing harness builds the dialog without an `UpdateController` in scope, wrap it: `RepositoryProvider<UpdateController>.value(value: UpdateController(_FakeRepo()), child: ...)` with a local `_FakeRepo` (as in Task 9).

- [ ] **Step 6: Run the full local done-bar**

Run:
```bash
fvm flutter analyze
fvm dart run custom_lint
fvm dart run bloc_tools:bloc lint lib
fvm dart format lib test tools
fvm flutter test
```
Expected: all green / 0 issues.

- [ ] **Step 7: Commit**

```bash
git add lib/core/di/injection_container.dart lib/main.dart lib/features/home/presentation/screens/main_screen.dart lib/features/settings/presentation/widgets/settings_dialog.dart test/features/settings/presentation/widgets/settings_dialog_test.dart
git commit -m "feat(updates): wire DI, provider, MainScreen gate, GENERAL-tab section"
```

---

### Task 13: CI — real installer artifacts

**Files:**
- Modify: `.github/workflows/release.yml` (macOS, Windows, Linux packaging steps + the `release` job's artifact globs)
- Create: `windows/installer.iss`
- Create: `linux/packaging/getman.desktop`
- Create: `linux/packaging/AppRun`

This task is **not locally runnable**; verification is by inspection + a `workflow_dispatch` dry-run. Do not block the done-bar on it.

- [ ] **Step 1: macOS — produce a `.dmg`**

In `release.yml`, replace the macOS "Package .app bundle" step and its artifact path with:
```yaml
      - name: Package .dmg
        run: |
          mkdir -p dmg_staging
          cp -R build/macos/Build/Products/Release/getman.app dmg_staging/
          ln -s /Applications dmg_staging/Applications
          hdiutil create -volname "Getman" -srcfolder dmg_staging \
            -ov -format UDZO "getman-${VERSION}-macos-arm64.dmg"

      - uses: actions/upload-artifact@v4
        with:
          name: macos
          path: getman-*-macos-arm64.dmg
          if-no-files-found: error
```

- [ ] **Step 2: Windows — Inno Setup installer**

Create `windows/installer.iss` (generate ONE fresh GUID for `AppId` and keep it forever — e.g. via `uuidgen`; the literal below is a placeholder to replace with a real generated GUID):
```ini
#define MyAppName "Getman"
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

[Setup]
AppId={{B4A0C9F2-2D3E-4E2A-9C11-GENERATE-A-REAL-GUID}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\Getman
DefaultGroupName=Getman
OutputDir=..\build\installer
OutputBaseFilename=getman-{#MyAppVersion}-windows-x64-setup
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
AppMutex=GetmanSingleInstanceMutex
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Getman"; Filename: "{app}\getman.exe"
Name: "{commondesktop}\Getman"; Filename: "{app}\getman.exe"

[Run]
Filename: "{app}\getman.exe"; Description: "Launch Getman"; Flags: nowait postinstall skipifsilent
```
Replace the Windows "Package Windows build" step + artifact path in `release.yml`:
```yaml
      - name: Build installer (Inno Setup)
        shell: pwsh
        run: |
          choco install innosetup -y --no-progress
          & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DMyAppVersion="$env:VERSION" windows\installer.iss

      - uses: actions/upload-artifact@v4
        with:
          name: windows
          path: build/installer/getman-*-windows-x64-setup.exe
          if-no-files-found: error
```
(If `VERSION` begins with `v`, strip it for the installer's `MyAppVersion`: `$ver = $env:VERSION -replace '^v',''` and pass `$ver`.)

- [ ] **Step 3: Linux — AppImage**

Create `linux/packaging/getman.desktop`:
```ini
[Desktop Entry]
Type=Application
Name=Getman
Exec=getman
Icon=getman
Categories=Development;
Terminal=false
```
Create `linux/packaging/AppRun` (executable):
```sh
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/getman" "$@"
```
Replace the Linux "Package Linux bundle" step + artifact path in `release.yml`:
```yaml
      - name: Package AppImage
        run: |
          export ARCH=x86_64
          APPDIR=AppDir
          mkdir -p "$APPDIR/usr/bin"
          cp -r build/linux/x64/release/bundle/* "$APPDIR/usr/bin/"
          cp linux/packaging/getman.desktop "$APPDIR/getman.desktop"
          cp linux/icon.png "$APPDIR/getman.png"
          cp linux/packaging/AppRun "$APPDIR/AppRun"
          chmod +x "$APPDIR/AppRun"
          wget -q https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
          chmod +x appimagetool-x86_64.AppImage
          ./appimagetool-x86_64.AppImage --appimage-extract-and-run \
            "$APPDIR" "getman-${VERSION}-linux-x86_64.AppImage"

      - uses: actions/upload-artifact@v4
        with:
          name: linux
          path: getman-*-linux-x86_64.AppImage
          if-no-files-found: error
```

- [ ] **Step 4: Verify the workflow YAML parses**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml'))" && echo OK`
Expected: `OK` (the `release` job's `files: artifacts/*` glob already picks up whatever the build jobs upload, so no change needed there).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml windows/installer.iss linux/packaging/
git commit -m "ci(updates): ship .dmg + Inno setup.exe + AppImage installers"
```

- [ ] **Step 6: (Manual, post-merge) dry-run**

After pushing, trigger the `workflow_dispatch` run (`gh workflow run Release -f tag=v0.0.0-dev`) and confirm all three desktop jobs produce their installer artifact. Not part of the automated done-bar.

---

### Task 14: Documentation — CLAUDE.md + wiki

**Files:**
- Modify: `CLAUDE.md`
- Modify (separate repo): the `Getman.wiki.git` working copy

- [ ] **Step 1: Update CLAUDE.md tech stack + structure**

- §1 Tech Stack: add a bullet — "**Auto-update**: `updat` (GitHub-release updater) + `package_info_plus` (current version) + `path_provider` (download path). Only `lib/features/updates/presentation/update_gate_io.dart` imports `updat`/`dart:io`; web uses `update_gate_stub.dart` via a conditional export."
- §2 features list: add `updates` and a short subsection describing the gate/controller/dialog + that installers ship per-platform.
- §3 SettingsModel row note: append `bool checkForUpdatesOnStartup` at `HiveField(25)` (default `true`) and `String? skippedUpdateVersion` at `HiveField(26)`; change "next free: 25" to "next free: 27".

- [ ] **Step 2: Verify CLAUDE.md edits are coherent**

Read the changed sections back; ensure the `HiveField` numbering and "next free" are consistent with Task 2.

- [ ] **Step 3: Update the wiki**

Clone (if not present) and edit:
```bash
git clone https://github.com/thiagomiranda3/Getman.wiki.git /tmp/getman-wiki
```
Add a new page `Auto-Update.md` covering: the startup check, the Update / Skip this version / Later prompt, the GENERAL-tab "Check for updates on startup" toggle + "CHECK FOR UPDATES" button, the per-platform install (.dmg drag-to-Applications / Windows installer / Linux AppImage), and the unsigned-app authorization step (Gatekeeper / SmartScreen). Add it to `_Sidebar.md`. Commit + push (`master`).

- [ ] **Step 4: Commit the CLAUDE.md change**

```bash
git add CLAUDE.md
git commit -m "docs(updates): document auto-update feature, deps, settings fields"
```

---

## Self-Review

**Spec coverage:**
- §1 module layout → Tasks 4–11. ✓
- §2 version check / dedicated Dio / package_info_plus → Tasks 1, 5, 6, 11. ✓
- §3 web-safety / conditional import → Task 11 (+ Global Constraints). ✓
- §4 asset matching / null-on-failure → Tasks 5, 6. ✓
- §5 Hive fields + events + GENERAL-tab UI → Tasks 2, 3, 9, 12. ✓
- §6 gate/controller/dialog/launcher + shouldPrompt → Tasks 7, 8, 10, 11. ✓
- §7 CI installers → Task 13. ✓
- §8 testing → each task's TDD steps + Task 12 full done-bar. ✓
- §9 docs → Task 14. ✓

**Placeholder scan:** The only intentional placeholder is the Inno `AppId` GUID (Task 13 Step 2) — flagged explicitly with instructions to generate a real one. No "TBD"/"add error handling"/"similar to" placeholders elsewhere.

**Type consistency:** `ReleaseInfo{version, changelog, assetUrl}`, `UpdatePlatform{macos,windows,linux}`, `UpdatePhase` (8 values), `shouldPromptForUpdate(...)`, `isNewerVersion(...)`, `UpdateController` field/method names, and the `ValueKey`s (`check_updates_switch`, `check_updates_button`, `update_skip_button`, `update_later_button`, `update_now_button`) are used identically across Tasks 4–12. Settings fields `checkForUpdatesOnStartup` / `skippedUpdateVersion` and events `UpdateCheckForUpdatesOnStartup` / `SetSkippedUpdateVersion` match across Tasks 2, 3, 9, 10, 12.

**Open risk flagged for execution:** the exact `updateChipBuilder` parameter signature for `updat 1.4.0` must be confirmed against the installed package (Task 11 Step 5 note) — the analyzer is the gate.
```
