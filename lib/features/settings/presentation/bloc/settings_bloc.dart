import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/settings_entity.dart';
import '../../domain/usecases/settings_usecases.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SaveSettingsUseCase saveSettingsUseCase;

  SettingsBloc({
    required this.saveSettingsUseCase,
    SettingsEntity? initialSettings,
  }) : super(SettingsState(settings: initialSettings ?? const SettingsEntity())) {
    on<UpdateDarkMode>(_onUpdateDarkMode);
    on<UpdateCompactMode>(_onUpdateCompactMode);
    on<UpdateVerticalLayout>(_onUpdateVerticalLayout);
    on<UpdateHistoryLimit>(_onUpdateHistoryLimit);
    on<UpdateSaveResponseInHistory>(_onUpdateSaveResponseInHistory);
    on<UpdateSplitRatio>(_onUpdateSplitRatio);
    on<UpdateSideMenuWidth>(_onUpdateSideMenuWidth);
  }

  Future<void> _onUpdateDarkMode(UpdateDarkMode event, Emitter<SettingsState> emit) async {
    final newSettings = state.settings.copyWith(isDarkMode: event.isDarkMode);
    await saveSettingsUseCase(newSettings);
    emit(state.copyWith(settings: newSettings));
  }

  Future<void> _onUpdateCompactMode(UpdateCompactMode event, Emitter<SettingsState> emit) async {
    final newSettings = state.settings.copyWith(isCompactMode: event.isCompactMode);
    await saveSettingsUseCase(newSettings);
    emit(state.copyWith(settings: newSettings));
  }

  Future<void> _onUpdateVerticalLayout(UpdateVerticalLayout event, Emitter<SettingsState> emit) async {
    final newSettings = state.settings.copyWith(isVerticalLayout: event.isVerticalLayout);
    await saveSettingsUseCase(newSettings);
    emit(state.copyWith(settings: newSettings));
  }

  Future<void> _onUpdateHistoryLimit(UpdateHistoryLimit event, Emitter<SettingsState> emit) async {
    final newSettings = state.settings.copyWith(historyLimit: event.historyLimit);
    await saveSettingsUseCase(newSettings);
    emit(state.copyWith(settings: newSettings));
  }

  Future<void> _onUpdateSaveResponseInHistory(UpdateSaveResponseInHistory event, Emitter<SettingsState> emit) async {
    final newSettings = state.settings.copyWith(saveResponseInHistory: event.save);
    await saveSettingsUseCase(newSettings);
    emit(state.copyWith(settings: newSettings));
  }

  Future<void> _onUpdateSplitRatio(UpdateSplitRatio event, Emitter<SettingsState> emit) async {
    final newSettings = state.settings.copyWith(splitRatio: event.ratio);
    await saveSettingsUseCase(newSettings);
    emit(state.copyWith(settings: newSettings));
  }

  Future<void> _onUpdateSideMenuWidth(UpdateSideMenuWidth event, Emitter<SettingsState> emit) async {
    final newSettings = state.settings.copyWith(sideMenuWidth: event.width);
    await saveSettingsUseCase(newSettings);
    emit(state.copyWith(settings: newSettings));
  }
}
