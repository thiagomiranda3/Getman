import 'package:flutter/foundation.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/core/storage/hive_helpers.dart';
import 'package:getman/features/cookies/data/models/stored_cookie_model.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Hive-backed [CookiePersistence] for the cookie jar. Whole-jar atomic writes
/// (replaceAllInBox), matching the collections/environments persistence style.
/// Failures are swallowed with a debug log — cookie durability is best-effort
/// and must never break a request.
class HiveCookiePersistence implements CookiePersistence {
  Box<StoredCookieModel> _box() => Hive.box<StoredCookieModel>(HiveBoxes.cookies);

  @override
  List<NetworkCookie> loadAll() {
    try {
      return _box().values.map((m) => m.toCookie()).toList();
    } catch (e) {
      debugPrint('Cookie load failed: $e');
      return const [];
    }
  }

  @override
  Future<void> saveAll(List<NetworkCookie> cookies) async {
    try {
      await replaceAllInBox(_box(), cookies.map(StoredCookieModel.fromCookie));
    } catch (e) {
      debugPrint('Cookie save failed: $e');
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      await _box().clear();
    } catch (e) {
      debugPrint('Cookie clear failed: $e');
    }
  }
}
