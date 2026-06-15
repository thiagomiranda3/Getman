import 'package:flutter/foundation.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/features/cookies/data/models/stored_cookie_model.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// Hive-backed [CookiePersistence] for the cookie jar. Cookies are stored
/// **keyed by `domain|path|name`** so each `Set-Cookie` is a single put/delete
/// instead of rewriting the whole jar. Failures are swallowed with a debug log
/// — cookie durability is best-effort and must never break a request.
class HiveCookiePersistence implements CookiePersistence {
  Box<StoredCookieModel> _box() =>
      Hive.box<StoredCookieModel>(HiveBoxes.cookies);

  @override
  List<NetworkCookie> loadAll() {
    try {
      return _box().values.map((m) => m.toCookie()).toList();
    } on Object catch (e) {
      debugPrint('Cookie load failed: $e');
      return const [];
    }
  }

  @override
  Future<void> upsert(NetworkCookie cookie) async {
    try {
      await _box().put(cookie.key, StoredCookieModel.fromCookie(cookie));
    } on Object catch (e) {
      debugPrint('Cookie upsert failed: $e');
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await _box().delete(key);
    } on Object catch (e) {
      debugPrint('Cookie remove failed: $e');
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      await _box().clear();
    } on Object catch (e) {
      debugPrint('Cookie clear failed: $e');
    }
  }

  /// One-time migration of cookies stored under legacy auto-increment int keys
  /// (pre keyed-storage) to their `domain|path|name` key, so later [upsert]s
  /// overwrite the same logical cookie instead of leaving an int-keyed dup.
  /// No-op once keys are strings. The box must already be open.
  static Future<void> migrateLegacyKeysIfNeeded() async {
    try {
      final box = Hive.box<StoredCookieModel>(HiveBoxes.cookies);
      if (box.isEmpty || !box.keys.any((k) => k is int)) return;
      final values = box.values.toList(growable: false);
      await box.clear();
      await box.putAll({for (final m in values) m.toCookie().key: m});
    } on Object catch (e) {
      debugPrint('Cookie key migration failed: $e');
    }
  }
}
