// Registers the existing Hive schema in each isolate that owns boxes.
// No typeIds or fields change when ownership moves to the storage worker.
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:getman/features/collections/data/models/saved_example_model.dart';
import 'package:getman/features/cookies/data/models/stored_cookie_model.dart';
import 'package:getman/features/environments/data/models/environment_model.dart';
import 'package:getman/features/history/data/models/request_config_model.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:getman/features/tabs/data/models/multipart_field_model.dart';
import 'package:getman/features/tabs/data/models/panel_model.dart';
import 'package:getman/features/tabs/data/models/parked_param_model.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:getman/features/tabs/data/models/stored_response_model.dart';
import 'package:hive_ce/hive.dart';

void registerHiveAdapters() {
  _register(SettingsModelAdapter());
  _register(HttpRequestConfigAdapter());
  _register(HttpRequestTabModelAdapter());
  _register(StoredResponseModelAdapter());
  _register(PanelModelAdapter());
  _register(CollectionNodeAdapter());
  _register(SavedExampleModelAdapter());
  _register(EnvironmentModelAdapter());
  _register(MultipartFieldModelAdapter());
  _register(ParkedParamModelAdapter());
  _register(StoredCookieModelAdapter());
}

// Preserve the model type: registering TypeAdapter<dynamic> would make the
// first adapter match every value, including values belonging to other models.
void _register<T>(TypeAdapter<T> adapter) {
  if (!Hive.isAdapterRegistered(adapter.typeId)) {
    Hive.registerAdapter<T>(adapter);
  }
}
