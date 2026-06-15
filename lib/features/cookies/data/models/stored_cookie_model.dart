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
  });

  factory StoredCookieModel.fromCookie(NetworkCookie c) => StoredCookieModel(
    name: c.name,
    value: c.value,
    domain: c.domain,
    path: c.path,
    secure: c.secure,
    httpOnly: c.httpOnly,
    expiresEpochMs: c.expiresEpochMs,
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

  NetworkCookie toCookie() => NetworkCookie(
    name: name,
    value: value,
    domain: domain,
    path: path,
    secure: secure,
    httpOnly: httpOnly,
    expiresEpochMs: expiresEpochMs,
  );
}
