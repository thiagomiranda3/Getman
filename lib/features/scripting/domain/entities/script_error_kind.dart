// Stable categories for script diagnostics, separate from HTTP failures.
enum ScriptErrorKind {
  syntax,
  runtime,
  timeout,
  cancelled,
  memoryLimit,
  inputTooLarge,
  outputTooLarge,
  unsupportedApi,
  untrusted,
  persistence,
}
