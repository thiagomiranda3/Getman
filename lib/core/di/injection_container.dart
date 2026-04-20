import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../navigation/app_router.dart';
import '../network/network_service.dart';
import '../storage/hive_boxes.dart';

import '../../features/settings/data/datasources/settings_local_data_source.dart';
import '../../features/settings/data/models/settings_model.dart';
import '../../features/settings/data/repositories/settings_repository_impl.dart';
import '../../features/settings/domain/entities/settings_entity.dart';
import '../../features/settings/domain/repositories/settings_repository.dart';
import '../../features/settings/domain/usecases/settings_usecases.dart';
import '../../features/settings/presentation/bloc/settings_bloc.dart';

import '../../features/history/data/datasources/history_local_data_source.dart';
import '../../features/history/data/models/request_config_model.dart';
import '../../features/history/data/repositories/history_repository_impl.dart';
import '../../features/history/domain/repositories/history_repository.dart';
import '../../features/history/domain/usecases/history_usecases.dart';
import '../../features/history/presentation/bloc/history_bloc.dart';

import '../../features/collections/data/datasources/collections_local_data_source.dart';
import '../../features/collections/data/models/collection_node_model.dart';
import '../../features/collections/data/repositories/collections_repository_impl.dart';
import '../../features/collections/domain/repositories/collections_repository.dart';
import '../../features/collections/domain/usecases/collections_usecases.dart';
import '../../features/collections/presentation/bloc/collections_bloc.dart';

import '../../features/tabs/data/datasources/tabs_local_data_source.dart';
import '../../features/tabs/data/models/request_tab_model.dart';
import '../../features/tabs/data/repositories/tabs_repository_impl.dart';
import '../../features/tabs/domain/repositories/tabs_repository.dart';
import '../../features/tabs/presentation/bloc/tabs_bloc.dart';

import '../../features/home/domain/usecases/tab_dirty_checker.dart';

final sl = GetIt.instance;

Future<SettingsEntity> init() async {
  await Hive.initFlutter();

  Hive.registerAdapter(SettingsModelAdapter());
  Hive.registerAdapter(HttpRequestConfigAdapter());
  Hive.registerAdapter(HttpRequestTabModelAdapter());
  Hive.registerAdapter(CollectionNodeAdapter());

  final settingsBox = await Hive.openBox<SettingsModel>(HiveBoxes.settings);
  await Hive.openBox<HttpRequestConfig>(HiveBoxes.history);
  await Hive.openBox<HttpRequestTabModel>(HiveBoxes.tabs);
  await Hive.openBox<CollectionNode>(HiveBoxes.collections);

  final initialSettings = settingsBox.get('current')?.toEntity() ?? const SettingsEntity();

  // Features - Settings
  sl.registerLazySingleton(() => SettingsBloc(
    getSettingsUseCase: sl(),
    saveSettingsUseCase: sl(),
    initialSettings: initialSettings,
  ));

  sl.registerLazySingleton(() => GetSettingsUseCase(sl()));
  sl.registerLazySingleton(() => SaveSettingsUseCase(sl()));

  sl.registerLazySingleton<SettingsRepository>(() => SettingsRepositoryImpl(sl()));

  sl.registerLazySingleton<SettingsLocalDataSource>(() => SettingsLocalDataSourceImpl());

  // Features - History
  sl.registerLazySingleton(() => HistoryBloc(
    getHistoryUseCase: sl(),
    addToHistoryUseCase: sl(),
    clearHistoryUseCase: sl(),
    watchHistoryUseCase: sl(),
  ));

  sl.registerLazySingleton(() => GetHistoryUseCase(sl()));
  sl.registerLazySingleton(() => AddToHistoryUseCase(sl()));
  sl.registerLazySingleton(() => ClearHistoryUseCase(sl()));
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

  // Features - Tabs
  sl.registerLazySingleton(() => TabsBloc(
    repository: sl(),
    networkService: sl(),
    addToHistoryUseCase: sl(),
    getSettingsUseCase: sl(),
  ));

  sl.registerLazySingleton<TabsRepository>(() => TabsRepositoryImpl(sl()));

  sl.registerLazySingleton<TabsLocalDataSource>(() => TabsLocalDataSourceImpl());

  // Features - Home
  sl.registerLazySingleton(() => const TabDirtyChecker());

  // Core
  sl.registerLazySingleton(() => NetworkService(dio: NetworkService.buildDio()));
  sl.registerLazySingleton(() => AppRouter());

  return initialSettings;
}
