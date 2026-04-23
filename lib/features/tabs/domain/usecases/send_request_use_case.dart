import 'package:flutter/foundation.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/network/http_response.dart';
import '../../../../core/network/network_service.dart';
import '../../../../core/domain/entities/request_config_entity.dart';
import '../../../history/domain/usecases/history_usecases.dart';
import '../../../settings/domain/usecases/settings_usecases.dart';
import '../repositories/tabs_repository.dart';

class SendRequestUseCase {
  final TabsRepository tabsRepository;
  final AddToHistoryUseCase addToHistoryUseCase;
  final GetSettingsUseCase getSettingsUseCase;

  SendRequestUseCase({
    required this.tabsRepository,
    required this.addToHistoryUseCase,
    required this.getSettingsUseCase,
  });

  Future<HttpResponseEntity> call({
    required HttpRequestConfigEntity config,
    NetworkCancelHandle? cancelHandle,
  }) async {
    try {
      final response = await tabsRepository.sendRequest(config, cancelHandle: cancelHandle);
      await _record(config, response: response);
      return response;
    } on NetworkFailure catch (f) {
      if (f.type != NetworkFailureType.cancelled) {
        await _record(config, failure: f);
      }
      rethrow;
    }
  }

  Future<void> _record(
    HttpRequestConfigEntity config, {
    HttpResponseEntity? response,
    NetworkFailure? failure,
  }) async {
    try {
      final settings = await getSettingsUseCase();
      final historyConfig = settings.saveResponseInHistory
          ? config.copyWith(
              responseBody: response?.body ?? failure?.message,
              responseHeaders: response?.headers ?? const {},
              statusCode: response?.statusCode ?? failure?.statusCode ?? 0,
              durationMs: response?.durationMs ?? 0,
            )
          : config;
      await addToHistoryUseCase(historyConfig, settings.historyLimit);
    } catch (e, st) {
      // History is best-effort; never fail the request because of persistence —
      // but surface the failure so silent regressions are spotted.
      debugPrint('SendRequestUseCase: failed to record history: $e\n$st');
    }
  }
}
