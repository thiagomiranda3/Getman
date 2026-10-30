// Real bootstrap assets on native and Flutter browser-test HTTP servers.
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScriptRuntimeTestAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (!kIsWeb) return rootBundle.load(key);
    final response = await Dio().get<List<int>>(
      Uri.base.resolve('/$key').toString(),
      options: Options(responseType: ResponseType.bytes),
    );
    return ByteData.sublistView(Uint8List.fromList(response.data!));
  }
}
