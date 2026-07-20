// Resolves the active environment (and its variables) by id out of a list --
// shared helper for send-time substitution and environment-aware widgets.

import 'package:getman/features/environments/domain/entities/environment_entity.dart';

class ActiveEnvironmentHelper {
  static Map<String, String> variablesFor(
    List<EnvironmentEntity> environments,
    String? activeId,
  ) => activeEnvironment(environments, activeId)?.variables ?? const {};

  static EnvironmentEntity? activeEnvironment(
    List<EnvironmentEntity> environments,
    String? activeId,
  ) {
    if (activeId == null) return null;
    for (final env in environments) {
      if (env.id == activeId) return env;
    }
    return null;
  }
}
