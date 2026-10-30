#!/usr/bin/env bash
# WATCH a single E2E flow drive the real macOS app window, in slow motion.
#
# The app's default window is desktop-sized (see MainMenu.xib) and the harness
# does NOT override the test viewport, so `flutter test` renders the live app to
# the window (you watch the taps/typing happen) — it's not the headless
# "Test starting…" stub. This is a thin wrapper over run_macos.sh that turns
# slow-motion ON by default (700 ms/step) and runs one flow.
#
# Usage:
#   bash integration_test/run_macos_watch.sh tabs
#   bash integration_test/run_macos_watch.sh scripts_ui
#   E2E_SLOW_MS=1200 bash integration_test/run_macos_watch.sh environments
#
# One flow per run. For the full, fast pass use `run_macos.sh` (no args).
set -uo pipefail

exec env E2E_SLOW_MS="${E2E_SLOW_MS:-700}" \
  bash "$(dirname "$0")/run_macos.sh" "${1:-tabs}"
