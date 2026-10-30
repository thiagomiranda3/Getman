// Synchronous execution ownership used before every asynchronous effect.
class ScriptExecutionRegistry {
  final Map<String, String> _executions = {};
  void register(String tabId, String executionId) {
    _executions[tabId] = executionId;
  }

  bool isCurrent(String tabId, String executionId) =>
      _executions[tabId] == executionId;
  void finish(String tabId, String executionId) {
    if (isCurrent(tabId, executionId)) _executions.remove(tabId);
  }
}
