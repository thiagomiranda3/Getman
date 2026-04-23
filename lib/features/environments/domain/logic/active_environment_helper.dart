import '../entities/environment_entity.dart';

class ActiveEnvironmentHelper {
  static Map<String, String> variablesFor(
    List<EnvironmentEntity> environments,
    String? activeId,
  ) {
    if (activeId == null) return const {};
    for (final env in environments) {
      if (env.id == activeId) return env.variables;
    }
    return const {};
  }
}
