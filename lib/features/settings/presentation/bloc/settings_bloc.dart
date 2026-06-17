import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

/// Lower bound for `historyLimit` — 0 or negative would cause the trim loop
/// in `HistoryLocalDataSourceImpl.addToHistory` to drop the just-added entry.
const int _historyLimitMin = 1;

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({
    required SaveSettingsUseCase saveSettingsUseCase,
    SettingsEntity? initialSettings,
  }) : _saveSettingsUseCase = saveSettingsUseCase,
       super(
         SettingsState(settings: initialSettings ?? const SettingsEntity()),
       ) {
    on<UpdateDarkMode>(
      (e, emit) => _apply(emit, (s) => s.copyWith(isDarkMode: e.isDarkMode)),
    );
    on<UpdateCompactMode>(
      (e, emit) =>
          _apply(emit, (s) => s.copyWith(isCompactMode: e.isCompactMode)),
    );
    on<UpdateReduceVisualEffects>(
      (e, emit) =>
          _apply(emit, (s) => s.copyWith(reduceVisualEffects: e.value)),
    );
    on<UpdateVerticalLayout>(
      (e, emit) =>
          _apply(emit, (s) => s.copyWith(isVerticalLayout: e.isVerticalLayout)),
    );
    on<UpdateHistoryLimit>(
      (e, emit) => _apply(
        emit,
        (s) => s.copyWith(
          historyLimit: e.historyLimit < _historyLimitMin
              ? _historyLimitMin
              : e.historyLimit,
        ),
      ),
    );
    on<UpdateSaveResponseInHistory>(
      (e, emit) =>
          _apply(emit, (s) => s.copyWith(saveResponseInHistory: e.save)),
    );
    on<UpdateAlwaysPrettifyLargeResponses>(
      (e, emit) => _apply(
        emit,
        (s) => s.copyWith(alwaysPrettifyLargeResponses: e.value),
      ),
    );
    on<UpdateResponseHistoryLimit>(
      (e, emit) => _apply(
        emit,
        (s) => s.copyWith(responseHistoryLimit: _clampHistoryDepth(e.limit)),
      ),
    );
    on<UpdateSaveLargeResponsesInHistory>(
      (e, emit) =>
          _apply(emit, (s) => s.copyWith(saveLargeResponsesInHistory: e.value)),
    );
    on<UpdateSplitRatio>(
      (e, emit) => _apply(emit, (s) => s.copyWith(splitRatio: e.ratio)),
    );
    on<UpdateSideMenuWidth>(
      (e, emit) => _apply(emit, (s) => s.copyWith(sideMenuWidth: e.width)),
    );
    on<UpdateThemeId>(
      (e, emit) => _apply(emit, (s) => s.copyWith(themeId: e.themeId)),
    );
    on<UpdateActiveEnvironmentId>(
      (e, emit) => _apply(emit, (s) => s.copyWith(activeEnvironmentId: e.id)),
    );
    on<UpdateConnectTimeout>(
      (e, emit) => _apply(
        emit,
        (s) => s.copyWith(connectTimeoutMs: _clampTimeout(e.ms)),
      ),
    );
    on<UpdateSendTimeout>(
      (e, emit) =>
          _apply(emit, (s) => s.copyWith(sendTimeoutMs: _clampTimeout(e.ms))),
    );
    on<UpdateReceiveTimeout>(
      (e, emit) => _apply(
        emit,
        (s) => s.copyWith(receiveTimeoutMs: _clampTimeout(e.ms)),
      ),
    );
    on<UpdateFollowRedirects>(
      (e, emit) => _apply(emit, (s) => s.copyWith(followRedirects: e.value)),
    );
    on<UpdateMaxRedirects>(
      (e, emit) => _apply(
        emit,
        (s) => s.copyWith(maxRedirects: _clampRedirects(e.value)),
      ),
    );
    on<UpdateVerifySsl>(
      (e, emit) => _apply(emit, (s) => s.copyWith(verifySsl: e.value)),
    );
    on<UpdateProxyUrl>(
      (e, emit) => _apply(emit, (s) => s.copyWith(proxyUrl: e.url)),
    );
    // Each cert field is passed explicitly so null clears it (no sentinel).
    on<UpdateClientCertificate>(
      (e, emit) => _apply(
        emit,
        (s) => s.copyWith(
          clientCertPath: e.certPath,
          clientKeyPath: e.keyPath,
          clientCertPassphrase: e.passphrase,
        ),
      ),
    );
    // The bookmark is always set in lockstep with the path (both null on
    // disconnect), so pass it explicitly rather than via the copyWith sentinel.
    on<UpdateWorkspacePath>(
      (e, emit) => _apply(
        emit,
        (s) => s.copyWith(workspacePath: e.path, workspaceBookmark: e.bookmark),
      ),
    );
  }
  final SaveSettingsUseCase _saveSettingsUseCase;

  // 0 disables the timeout (Dio treats Duration.zero as no limit); never
  // negative.
  static int _clampTimeout(int ms) => ms < 0 ? 0 : ms;

  // Min 1: dart:io throws "Redirect limit exceeded" on the first 3xx when
  // maxRedirects is 0 while followRedirects is on (it has no "0 = don't follow"
  // semantic — disable redirects via the FOLLOW REDIRECTS toggle instead).
  static int _clampRedirects(int v) => v < 1 ? 1 : v;

  /// Response-history depth: 0 disables the feature, capped at 50 to bound the
  /// per-tab storage footprint.
  static int _clampHistoryDepth(int v) => v.clamp(0, 50);

  Future<void> _apply(
    Emitter<SettingsState> emit,
    SettingsEntity Function(SettingsEntity current) update,
  ) async {
    final next = update(state.settings);
    // Emit optimistically — the UI must reflect the user's toggle even if the
    // write fails. Persistence failures are best-effort; surface them via
    // debugPrint so regressions show in console.
    emit(state.copyWith(settings: next));
    try {
      await _saveSettingsUseCase(next);
    } on PersistenceFailure catch (f) {
      log('Settings save failed: ${f.message}', name: 'SettingsBloc');
    }
  }
}
