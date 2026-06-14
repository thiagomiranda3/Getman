import 'package:get_it/get_it.dart';
import 'package:getman/core/navigation/app_router.dart';
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
import 'package:getman/features/tabs/data/repositories/tabs_repository_impl.dart';
import 'package:getman/features/tabs/domain/repositories/tabs_repository.dart';
import 'package:getman/features/tabs/domain/usecases/send_request_use_case.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

final sl = GetIt.instance;

Future<SettingsEntity> init() async {
  await Hive.initFlutter();

  Hive.registerAdapter(SettingsModelAdapter());
  Hive.registerAdapter(HttpRequestConfigAdapter());
  Hive.registerAdapter(HttpRequestTabModelAdapter());
  Hive.registerAdapter(CollectionNodeAdapter());
  Hive.registerAdapter(EnvironmentModelAdapter());
  Hive.registerAdapter(MultipartFieldModelAdapter());
  Hive.registerAdapter(StoredCookieModelAdapter());
  Hive.registerAdapter(ExtractionRuleModelAdapter());
  Hive.registerAdapter(AssertionModelAdapter());
  Hive.registerAdapter(RequestRulesModelAdapter());

  final settingsBox = await Hive.openBox<SettingsModel>(HiveBoxes.settings);
  await Hive.openBox<HttpRequestConfig>(HiveBoxes.history);
  await Hive.openBox<HttpRequestTabModel>(HiveBoxes.tabs);
  await Hive.openBox(HiveBoxes.tabsMeta);
  await Hive.openBox<CollectionNode>(HiveBoxes.collections);
  final environmentsBox = await Hive.openBox<EnvironmentModel>(HiveBoxes.environments);
  await Hive.openBox<StoredCookieModel>(HiveBoxes.cookies);
  await Hive.openBox<RequestRulesModel>(HiveBoxes.requestRules);

  final initialSettings = settingsBox.get('current')?.toEntity() ?? const SettingsEntity();
  final initialEnvironments =
      environmentsBox.values.map((model) => model.toEntity()).toList(growable: false);

  // Features - Settings
  sl.registerLazySingleton(() => SettingsBloc(
    saveSettingsUseCase: sl(),
    initialSettings: initialSettings,
  ));

  sl.registerLazySingleton(() => GetSettingsUseCase(sl()));
  sl.registerLazySingleton(() => SaveSettingsUseCase(sl()));

  sl.registerLazySingleton<SettingsRepository>(() => SettingsRepositoryImpl(sl()));

  sl.registerLazySingleton<SettingsLocalDataSource>(() => SettingsLocalDataSourceImpl());

  // Features - History
  sl.registerLazySingleton(() => HistoryBloc(watchHistoryUseCase: sl()));

  sl.registerLazySingleton(() => AddToHistoryUseCase(sl()));
  sl.registerLazySingleton(() => WatchHistoryUseCase(sl()));

  sl.registerLazySingleton<HistoryRepository>(() => HistoryRepositoryImpl(sl()));

  sl.registerLazySingleton<HistoryLocalDataSource>(() => HistoryLocalDataSourceImpl());

  // Features - Collections
  sl.registerLazySingleton(() => CollectionsBloc(
    getCollectionsUseCase: sl(),
    saveCollectionsUseCase: sl(),
  ));

  sl.registerLazySingleton(() => GetCollectionsUseCase(sl()));
  sl.registerLazySingleton(() => SaveCollectionsUseCase(sl()));

  sl.registerLazySingleton<CollectionsRepository>(() => CollectionsRepositoryImpl(sl()));

  sl.registerLazySingleton<CollectionsLocalDataSource>(() => CollectionsLocalDataSourceImpl());

  sl.registerLazySingleton(() => WorkspaceSyncService(createWorkspaceDataSource()));

  // Features - Chaining (no-code extraction + assertions)
  sl.registerLazySingleton(() => RulesBloc(
        getRequestRulesUseCase: sl(),
        saveRequestRulesUseCase: sl(),
      ));
  sl.registerLazySingleton(() => GetRequestRulesUseCase(sl()));
  sl.registerLazySingleton(() => SaveRequestRulesUseCase(sl()));
  sl.registerLazySingleton<RequestRulesRepository>(() => RequestRulesRepositoryImpl(sl()));
  sl.registerLazySingleton<RequestRulesLocalDataSource>(() => RequestRulesLocalDataSourceImpl());

  // Features - Environments
  sl.registerLazySingleton(() => EnvironmentsBloc(
    getEnvironmentsUseCase: sl(),
    saveEnvironmentsUseCase: sl(),
    initialEnvironments: initialEnvironments,
  ));

  sl.registerLazySingleton(() => GetEnvironmentsUseCase(sl()));
  sl.registerLazySingleton(() => SaveEnvironmentsUseCase(sl()));

  sl.registerLazySingleton<EnvironmentsRepository>(() => EnvironmentsRepositoryImpl(sl()));

  sl.registerLazySingleton<EnvironmentsLocalDataSource>(() => EnvironmentsLocalDataSourceImpl());

  // Features - Tabs
  sl.registerLazySingleton(() => TabsBloc(
    repository: sl(),
    sendRequestUseCase: sl(),
    getRequestRulesUseCase: sl(),
  ));

  sl.registerLazySingleton(() => SendRequestUseCase(
    tabsRepository: sl(),
    addToHistoryUseCase: sl(),
    getSettingsUseCase: sl(),
  ));

  sl.registerLazySingleton<TabsRepository>(() => TabsRepositoryImpl(
    localDataSource: sl(),
    networkService: sl(),
  ));

  sl.registerLazySingleton<TabsLocalDataSource>(() => TabsLocalDataSourceImpl());

  // Features - Realtime (WebSocket / SSE)
  sl.registerLazySingleton(() => RealtimeService());
  sl.registerLazySingleton(() => RealtimeBloc(service: sl()));

  // Features - Home
  sl.registerLazySingleton(() => const TabDirtyChecker());

  // Core
  final cookieStore = InMemoryCookieStore(persistence: HiveCookiePersistence())..hydrate();
  sl.registerLazySingleton<CookieStore>(() => cookieStore);
  sl.registerLazySingleton(() => NetworkService(
        dio: NetworkService.buildDio(
          initialSettings.toNetworkConfig(),
          CookieInterceptor(cookieStore),
        ),
      ));
  sl.registerLazySingleton(() => AppRouter());

  return initialSettings;
}
