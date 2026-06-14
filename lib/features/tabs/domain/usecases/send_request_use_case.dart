import 'package:flutter/foundation.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/utils/perf_trace.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';

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
    Map<String, String> envVars = const {},
    NetworkCancelHandle? cancelHandle,
  }) async {
    try {
      final response = await traceAsync(
        'send.request',
        () => tabsRepository.sendRequest(
          config,
          envVars: envVars,
          cancelHandle: cancelHandle,
        ),
      );
      await traceAsync('send.recordHistory', () => _record(config, response: response));
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
      final rawBody = response?.body ?? failure?.message;
      final cappedBody = rawBody != null && rawBody.length > kMaxPersistedResponseBodyChars
          ? kResponseBodyTooLargePlaceholder
          : rawBody;
      final historyConfig = settings.saveResponseInHistory
          ? config.copyWith(
              responseBody: cappedBody,
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
