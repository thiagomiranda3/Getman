// Local approval of exact script content; never inferred from shared JSON.
import 'package:getman/core/domain/entities/request_scripts.dart';

abstract class ScriptTrustRepository {
  Future<bool> isTrusted(String configId, RequestScripts scripts);
  Future<void> trust(String configId, RequestScripts scripts);
}
