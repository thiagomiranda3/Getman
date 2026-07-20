// Hive model (typeId 6, box: cookies) for one persisted cookie. hostOnly at
// HiveField(7) implements RFC 6265 host-only matching (true = exact-host
// only); it defaults to false so cookies persisted before this field existed
// keep the legacy, more-permissive suffix-domain matching.

import 'package:getman/core/network/network_cookie.dart';
import 'package:hive_ce/hive.dart';

part 'stored_cookie_model.g.dart';

/// Hive model for a persisted cookie. typeId 6 (first free after 0–5).
@HiveType(typeId: 6)
class StoredCookieModel extends HiveObject {
  StoredCookieModel({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.secure = false,
    this.httpOnly = false,
    this.expiresEpochMs,
    this.hostOnly = false,
  });

  factory StoredCookieModel.fromCookie(NetworkCookie c) => StoredCookieModel(
    name: c.name,
    value: c.value,
    domain: c.domain,
    path: c.path,
    secure: c.secure,
    httpOnly: c.httpOnly,
    expiresEpochMs: c.expiresEpochMs,
    hostOnly: c.hostOnly,
  );
  @HiveField(0)
  String name;

  @HiveField(1)
  String value;

  @HiveField(2)
  String domain;

  @HiveField(3, defaultValue: '/')
  String path;

  @HiveField(4, defaultValue: false)
  bool secure;

  @HiveField(5, defaultValue: false)
  bool httpOnly;

  @HiveField(6)
  int? expiresEpochMs;

  // Absent on cookies persisted before host-only support → false, i.e. legacy
  // cookies keep the pre-fix suffix-matching behavior.
  @HiveField(7, defaultValue: false)
  bool hostOnly;

  NetworkCookie toCookie() => NetworkCookie(
    name: name,
    value: value,
    domain: domain,
    path: path,
    secure: secure,
    httpOnly: httpOnly,
    expiresEpochMs: expiresEpochMs,
    hostOnly: hostOnly,
  );
}
