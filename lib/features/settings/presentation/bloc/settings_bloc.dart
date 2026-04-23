import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/settings_entity.dart';
import '../../domain/usecases/settings_usecases.dart';
import 'settings_event.dart';
import 'settings_state.dart';

/// Lower bound for `historyLimit` — 0 or negative would cause the trim loop
/// in `HistoryLocalDataSourceImpl.addToHistory` to drop the just-added entry.
const int _historyLimitMin = 1;

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SaveSettingsUseCase saveSettingsUseCase;

  SettingsBloc({
    required this.saveSettingsUseCase,
    SettingsEntity? initialSettings,
  }) : super(SettingsState(settings: initialSettings ?? const SettingsEntity())) {
    on<UpdateDarkMode>((e, emit) => _apply(emit, (s) => s.copyWith(isDarkMode: e.isDarkMode)));
    on<UpdateCompactMode>((e, emit) => _apply(emit, (s) => s.copyWith(isCompactMode: e.isCompactMode)));
    on<UpdateVerticalLayout>((e, emit) => _apply(emit, (s) => s.copyWith(isVerticalLayout: e.isVerticalLayout)));
    on<UpdateHistoryLimit>((e, emit) => _apply(emit, (s) => s.copyWith(
          historyLimit: e.historyLimit < _historyLimitMin ? _historyLimitMin : e.historyLimit,
        )));
    on<UpdateSaveResponseInHistory>((e, emit) => _apply(emit, (s) => s.copyWith(saveResponseInHistory: e.save)));
    on<UpdateSplitRatio>((e, emit) => _apply(emit, (s) => s.copyWith(splitRatio: e.ratio)));
    on<UpdateSideMenuWidth>((e, emit) => _apply(emit, (s) => s.copyWith(sideMenuWidth: e.width)));
    on<UpdateThemeId>((e, emit) => _apply(emit, (s) => s.copyWith(themeId: e.themeId)));
  }

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
      await saveSettingsUseCase(next);
    } on PersistenceFailure catch (f) {
      debugPrint('Settings save failed: ${f.message}');
    }
  }
}
