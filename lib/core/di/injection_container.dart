import 'package:get_it/get_it.dart';
import 'package:getman/core/navigation/app_router.dart';
import 'package:getman/core/navigation/url_focus_registry.dart';
import 'package:getman/core/network/cookie_interceptor.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/in_memory_cookie_store.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/network/realtime_service.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/chaining/data/datasources/request_rules_local_data_source.dart';
import 'package:getman/features/chaining/data/models/assertion_model.dart';
import 'package:getman/features/chaining/data/models/extraction_rule_model.dart';
import 'package:getman/features/chaining/data/models/request_rules_model.dart';
import 'package:getman/features/chaining/data/repositories/request_rules_repository_impl.dart';
import 'package:getman/features/chaining/domain/repositories/request_rules_repository.dart';
import 'package:getman/features/chaining/domain/usecases/request_rules_usecases.dart';
import 'package:getman/features/chaining/presentation/bloc/rules_bloc.dart';
import 'package:getman/features/collections/data/datasources/collections_local_data_source.dart';
import 'package:getman/features/collections/data/datasources/workspace_data_source_factory.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:getman/features/collections/data/models/saved_example_model.dart';
import 'package:getman/features/collections/data/repositories/collections_repository_impl.dart';
import 'package:getman/features/collections/data/services/workspace_sync_service.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/cookies/data/hive_cookie_persistence.dart';
import 'package:getman/features/cookies/data/models/stored_cookie_model.dart';
import 'package:getman/features/environments/data/datasources/environments_local_data_source.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:getman/features/environments/data/repositories/environments_repository_impl.dart';
import 'package:getman/features/environments/domain/repositories/environments_repository.dart';
import 'package:getman/features/environments/domain/usecases/environments_usecases.dart';
import 'package:getman/features/environments/presentation/bloc/environments_bloc.dart';
import 'package:getman/features/history/data/datasources/history_local_data_source.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/history/data/repositories/history_repository_impl.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';
import 'package:getman/features/settings/data/datasources/settings_local_data_source.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:getman/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/settings/domain/repositories/settings_repository.dart';
import 'package:getman/features/settings/domain/usecases/settings_usecases.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/tabs/data/datasources/tabs_local_data_source.dart';
import 'package:getman/features/tabs/data/models/multipart_field_model.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:getman/features/tabs/data/models/stored_response_model.dart';
import 'package:getman/features/tabs/data/repositories/tabs_repository_impl.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

final GetIt sl = GetIt.instance;

// Hive adapters register only once per process (re-registering a typeId throws,
// and there is no unregister). [reset] keeps them registered while tearing down
// get_it + boxes, so [init] must not re-register them on a second call (E2E
// boots the app once per test). Guarded by this flag.
bool _adaptersRegistered = false;

/// Boots the dependency graph and returns the settings to launch with.
///
/// [storageDirectoryOverride] points Hive at a specific directory instead of
/// the platform app-support dir. Production passes nothing (uses
/// `initFlutter`); E2E/integration tests pass a throwaway temp dir so a test
/// run never reads or wipes the developer's real saved data. Pair with [reset]
/// between tests.
Future<SettingsEntity> init({String? storageDirectoryOverride}) async {
  if (storageDirectoryOverride != null) {
    Hive.init(storageDirectoryOverride);
  } else {
    await Hive.initFlutter();
  }

  if (!_adaptersRegistered) {
    Hive
      ..registerAdapter(SettingsModelAdapter())
      ..registerAdapter(HttpRequestConfigAdapter())
      ..registerAdapter(HttpRequestTabModelAdapter())
      ..registerAdapter(StoredResponseModelAdapter())
      ..registerAdapter(CollectionNodeAdapter())
      ..registerAdapter(SavedExampleModelAdapter())
      ..registerAdapter(EnvironmentModelAdapter())
      ..registerAdapter(MultipartFieldModelAdapter())
      ..registerAdapter(StoredCookieModelAdapter())
      ..registerAdapter(ExtractionRuleModelAdapter())
      ..registerAdapter(AssertionModelAdapter())
      ..registerAdapter(RequestRulesModelAdapter());
    _adaptersRegistered = true;
  }

  // Open every box in PARALLEL (Future.wait) so cold start is bounded by the
  // slowest single box, not their sum. The cookies + request-rules boxes are
  // small and open concurrently with the rest; they used to be deferred to a
  // post-frame callback, but that raced early sends — a request fired before
  // the deferred warm-up finished silently dropped persisted cookies and
  // skipped post-response rules. Opening them on the cold path closes that race
  // for a negligible (parallel) cost. See [openAndHydrateDeferredBoxes].
  final boxes = await Future.wait<Box<dynamic>>([
    Hive.openBox<SettingsModel>(HiveBoxes.settings),
    Hive.openBox<EnvironmentModel>(HiveBoxes.environments),
    Hive.openBox<HttpRequestConfig>(HiveBoxes.history),
    Hive.openBox<HttpRequestTabModel>(HiveBoxes.tabs),
    Hive.openBox(HiveBoxes.tabsMeta),
    Hive.openBox<CollectionNode>(HiveBoxes.collections),
    Hive.openBox<StoredCookieModel>(HiveBoxes.cookies),
    Hive.openBox<RequestRulesModel>(HiveBoxes.requestRules),
  ]);
  final settingsBox = boxes[0] as Box<SettingsModel>;
  final environmentsBox = boxes[1] as Box<EnvironmentModel>;

  // Re-key any legacy int-keyed environments by id so per-id put/delete writes
  // overwrite the same logical environment (no-op once keys are strings).
  await EnvironmentsLocalDataSourceImpl.migrateLegacyKeysIfNeeded();
  // Same for collections: re-key the legacy auto-increment box by root id so
  // per-root keyed writes overwrite the same logical root (L12). Runs before
  // collections are first read.
  await CollectionsLocalDataSourceImpl.migrateLegacyKeysIfNeeded();

  final initialSettings =
      settingsBox.get('current')?.toEntity() ?? const SettingsEntity();
  final initialEnvironments = environmentsBox.values
      .map((model) => model.toEntity())
      .toList(growable: false);

  sl
    // Features - Settings
    ..registerLazySingleton(
      () => SettingsBloc(
        saveSettingsUseCase: sl(),
        initialSettings: initialSettings,
      ),
    )
    ..registerLazySingleton(() => GetSettingsUseCase(sl()))
    ..registerLazySingleton(() => SaveSettingsUseCase(sl()))
    ..registerLazySingleton<SettingsRepository>(
      () => SettingsRepositoryImpl(sl()),
    )
    ..registerLazySingleton<SettingsLocalDataSource>(
      SettingsLocalDataSourceImpl.new,
    )
    // Features - History
    ..registerLazySingleton(() => HistoryBloc(watchHistoryUseCase: sl()))
    ..registerLazySingleton(() => AddToHistoryUseCase(sl()))
    ..registerLazySingleton(() => WatchHistoryUseCase(sl()))
    ..registerLazySingleton<HistoryRepository>(
      () => HistoryRepositoryImpl(sl()),
    )
    ..registerLazySingleton<HistoryLocalDataSource>(
      HistoryLocalDataSourceImpl.new,
    )
    // Features - Collections
    ..registerLazySingleton(
      () => CollectionsBloc(
        getCollectionsUseCase: sl(),
        saveCollectionsUseCase: sl(),
      ),
    )
    ..registerLazySingleton(() => GetCollectionsUseCase(sl()))
    ..registerLazySingleton(() => SaveCollectionsUseCase(sl()))
    ..registerLazySingleton<CollectionsRepository>(
      () => CollectionsRepositoryImpl(sl()),
    )
    ..registerLazySingleton<CollectionsLocalDataSource>(
      CollectionsLocalDataSourceImpl.new,
    )
    ..registerLazySingleton(
      () => WorkspaceSyncService(createWorkspaceDataSource()),
    )
    // Features - Chaining (no-code extraction + assertions)
    ..registerLazySingleton(
      () => RulesBloc(
        getRequestRulesUseCase: sl(),
        saveRequestRulesUseCase: sl(),
      ),
    )
    ..registerLazySingleton(() => GetRequestRulesUseCase(sl()))
    ..registerLazySingleton(() => SaveRequestRulesUseCase(sl()))
    ..registerLazySingleton<RequestRulesRepository>(
      () => RequestRulesRepositoryImpl(sl()),
    )
    ..registerLazySingleton<RequestRulesLocalDataSource>(
      RequestRulesLocalDataSourceImpl.new,
    )
    // Features - Environments
    ..registerLazySingleton(
      () => EnvironmentsBloc(
        getEnvironmentsUseCase: sl(),
        saveEnvironmentsUseCase: sl(),
        putEnvironmentUseCase: sl(),
        deleteEnvironmentUseCase: sl(),
        initialEnvironments: initialEnvironments,
      ),
    )
    ..registerLazySingleton(() => GetEnvironmentsUseCase(sl()))
    ..registerLazySingleton(() => SaveEnvironmentsUseCase(sl()))
    ..registerLazySingleton(() => PutEnvironmentUseCase(sl()))
    ..registerLazySingleton(() => DeleteEnvironmentUseCase(sl()))
    ..registerLazySingleton<EnvironmentsRepository>(
      () => EnvironmentsRepositoryImpl(sl()),
    )
    ..registerLazySingleton<EnvironmentsLocalDataSource>(
      EnvironmentsLocalDataSourceImpl.new,
    )
    // Features - Tabs
    ..registerLazySingleton(
      () => TabsBloc(
        repository: sl(),
        sendRequestUseCase: sl(),
        getRequestRulesUseCase: sl(),
      ),
    )
    ..registerLazySingleton(
      () => SendRequestUseCase(
        tabsRepository: sl(),
        addToHistoryUseCase: sl(),
        getSettingsUseCase: sl(),
      ),
    )
    ..registerLazySingleton<TabsRepository>(
      () => TabsRepositoryImpl(
        localDataSource: sl(),
        networkService: sl(),
      ),
    )
    ..registerLazySingleton<TabsLocalDataSource>(TabsLocalDataSourceImpl.new)
    // Features - Realtime (WebSocket / SSE)
    ..registerLazySingleton(RealtimeService.new)
    ..registerLazySingleton(() => RealtimeBloc(service: sl()))
    // Features - Home
    ..registerLazySingleton(() => const TabDirtyChecker())
    // Lets the Cmd/Ctrl+L shortcut focus the active tab's URL field.
    ..registerLazySingleton(UrlFocusRegistry.new);

  // Core. The cookie box is already open (parallel wait above); hydrate the jar
  // before the network service can be used so the first send sees stored
  // cookies.
  final cookieStore = InMemoryCookieStore(persistence: HiveCookiePersistence());
  await openAndHydrateDeferredBoxes(cookieStore);
  sl
    ..registerLazySingleton<CookieStore>(() => cookieStore)
    ..registerLazySingleton(
      () => NetworkService(
        dio: NetworkService.buildDio(
          initialSettings.toNetworkConfig(),
          CookieInterceptor(cookieStore),
        ),
      ),
    )
    ..registerLazySingleton(AppRouter.new);

  return initialSettings;
}

/// Ensures the cookies + request-rules boxes are open, migrates the cookie jar
/// to its keyed layout, then hydrates [store]. [init] calls this on the
/// cold-start path so an early send can never race an unopened box (bugs:
/// dropped cookies / skipped post-response rules). Idempotent — the `isBoxOpen`
/// guards make it safe to call when the boxes are already open, and it is also
/// the single seam exercised by the boot test.
Future<void> openAndHydrateDeferredBoxes(InMemoryCookieStore store) async {
  await Future.wait<Box<dynamic>>([
    if (!Hive.isBoxOpen(HiveBoxes.cookies))
      Hive.openBox<StoredCookieModel>(HiveBoxes.cookies),
    if (!Hive.isBoxOpen(HiveBoxes.requestRules))
      Hive.openBox<RequestRulesModel>(HiveBoxes.requestRules),
  ]);
  await HiveCookiePersistence.migrateLegacyKeysIfNeeded();
  store.hydrate();
}

/// Tears down the DI container and closes all Hive boxes so [init] can be
/// called again with a fresh storage directory. Used by the E2E harness
/// between flows; not part of the production boot path. Registered Hive
/// adapters intentionally survive (Hive cannot unregister them, and [init]
/// guards against re-adding them).
Future<void> reset() async {
  await sl.reset();
  await Hive.close();
}
