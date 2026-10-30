// Installation-local script approvals. Only an exact request identity and
// canonical version/source digest can authorize execution; never exported.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/scripting/domain/repositories/script_trust_repository.dart';
import 'package:hive_ce/hive.dart';

class ScriptTrustRepositoryImpl implements ScriptTrustRepository {
  ScriptTrustRepositoryImpl(this._box);
  final Box<String> _box;

  String _digest(RequestScripts scripts) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            scripts.apiVersion,
            scripts.preRequest,
            scripts.postResponse,
          ]),
        ),
      )
      .toString();

  @override
  Future<bool> isTrusted(String configId, RequestScripts scripts) async {
    if (scripts.isEmpty) return true;
    try {
      return _box.get(configId) == _digest(scripts);
    } on Object {
      throw const PersistenceFailure('Unable to read script approval');
    }
  }

  @override
  Future<void> trust(String configId, RequestScripts scripts) async {
    try {
      await _box.put(configId, _digest(scripts));
      await _box.flush();
    } on Object {
      throw const PersistenceFailure('Unable to save script approval');
    }
  }
}
