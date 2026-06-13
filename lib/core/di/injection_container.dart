import 'package:get_it/get_it.dart';
import 'package:getman/core/navigation/app_router.dart';
import 'package:getman/core/network/network_service.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/collections/data/datasources/collections_local_data_source.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:getman/features/collections/data/repositories/collections_repository_impl.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
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

  final settingsBox = await Hive.openBox<SettingsModel>(HiveBoxes.settings);
  await Hive.openBox<HttpRequestConfig>(HiveBoxes.history);
  await Hive.openBox<HttpRequestTabModel>(HiveBoxes.tabs);
  await Hive.openBox(HiveBoxes.tabsMeta);
  await Hive.openBox<CollectionNode>(HiveBoxes.collections);
  final environmentsBox = await Hive.openBox<EnvironmentModel>(HiveBoxes.environments);

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

  // Features - Home
  sl.registerLazySingleton(() => const TabDirtyChecker());

  // Core
  sl.registerLazySingleton(() => NetworkService(dio: NetworkService.buildDio()));
  sl.registerLazySingleton(() => AppRouter());

  return initialSettings;
}
