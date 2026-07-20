// Pure decision logic for the auto-updater: dotted-version comparison
// (isNewerVersion) and whether to surface the update dialog
// (shouldPromptForUpdate). shouldPromptForUpdate suppresses a prompt only for
// the EXACT skipped version — a still-newer release prompts again, and the
// stored skipped-version setting is never cleared by this function.

/// True iff [latest] is a strictly higher dotted-numeric version than
/// [current]. Lenient: missing components count as 0; any non-numeric component
/// makes the comparison return false (we never prompt on a version we can't
/// parse).
bool isNewerVersion(String latest, String current) {
  final a = _parse(latest);
  final b = _parse(current);
  if (a == null || b == null) return false;
  final len = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

List<int>? _parse(String v) {
  final parts = v.split('.');
  final out = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p.trim());
    if (n == null) return null;
    out.add(n);
  }
  return out.isEmpty ? null : out;
}

/// Decides whether to surface the update dialog. A manual check always prompts
/// when a newer version exists (ignoring the auto-check toggle and the skipped
/// version); an automatic startup check additionally respects [autoCheck] and
/// the [skipped] version.
bool shouldPromptForUpdate({
  required bool autoCheck,
  required String? latest,
  required String current,
  required String? skipped,
  required bool manual,
}) {
  if (latest == null) return false;
  if (!isNewerVersion(latest, current)) return false;
  if (manual) return true;
  if (!autoCheck) return false;
  return latest != skipped;
}
