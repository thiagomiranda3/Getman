/// Photosensitivity (flash-safety) guard. WCAG 2.3.1 "general flash threshold":
/// content must not flash more than three times in any one-second period.
/// Pure Dart so the whole motion spine can use it.
library;

/// Maximum safe number of general flashes per second (WCAG 2.3.1).
const int kMaxSafeFlashesPerSecond = 3;

/// Shortest safe period between flash onsets (~333ms).
const Duration kMinFlashPeriod = Duration(
  milliseconds: 1000 ~/ kMaxSafeFlashesPerSecond,
);

/// Clamps a desired flash/blink count over [sweep] so the resulting rate never
/// exceeds [kMaxSafeFlashesPerSecond]. Always returns at least 1.
int safeFlashCount(Duration sweep, int desired) {
  final budget = sweep.inMilliseconds * kMaxSafeFlashesPerSecond ~/ 1000;
  final ceiling = budget < 1 ? 1 : budget;
  return desired.clamp(1, ceiling);
}
