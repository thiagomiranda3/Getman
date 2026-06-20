import 'dart:math' as math;

/// Fast responses snap (weight 0); slow ones land heavy (weight 1).
const int kFastLatencyMs = 150;
const int kSlowLatencyMs = 3000;

/// Maps a response latency to a 0..1 "weight" used to scale resolution effects.
/// Log-perceptual between [kFastLatencyMs] and [kSlowLatencyMs]; clamped.
double latencyWeight(int? durationMs) {
  if (durationMs == null || durationMs <= kFastLatencyMs) return 0;
  if (durationMs >= kSlowLatencyMs) return 1;
  final lo = math.log(kFastLatencyMs.toDouble());
  final hi = math.log(kSlowLatencyMs.toDouble());
  return ((math.log(durationMs.toDouble()) - lo) / (hi - lo)).clamp(0.0, 1.0);
}

/// Full in-flight tension is reached after this many ms of waiting.
const int kTensionFullMs = 3000;

/// 0→1 build-up curve for the live wait, given elapsed ms. Linear, clamped.
double inFlightTension(int elapsedMs) {
  if (elapsedMs <= 0) return 0;
  if (elapsedMs >= kTensionFullMs) return 1;
  return (elapsedMs / kTensionFullMs).clamp(0.0, 1.0);
}
