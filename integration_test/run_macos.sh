#!/usr/bin/env bash
# Runs the Getman E2E suite on macOS.
#
# By default all flows are composed into one entry point (all_flows_test.dart)
# so the macOS app is built and launched once, then every case runs sequentially
# in that one process. (Passing multiple test *files* to `flutter test` on
# desktop doesn't work — the 2nd+ fail with "Error waiting for a debug
# connection" — hence the single aggregator file.)
#
# Usage:
#   bash integration_test/run_macos.sh                  # whole suite (one build)
#   bash integration_test/run_macos.sh tabs             # one flow: flows/tabs_test.dart
#   bash integration_test/run_macos.sh flows/tabs_test.dart
#   E2E_SLOW_MS=800 bash integration_test/run_macos.sh tabs   # slow-motion (watch it)
#
# WATCH IT RUN: a real macOS app window opens while the test drives it. Run a
# single flow so it's followable, and set E2E_SLOW_MS to pause after each
# scripted step (see support/actions.dart) so you can see state change in real
# time. E2E_SLOW_MS=0 (default) = full speed.
set -uo pipefail

cd "$(dirname "$0")/.."

# Resolve the target: no arg → the aggregator (all flows, one build); an arg is
# either a flow name ("tabs") or a path ("flows/tabs_test.dart" / absolute).
target="${1:-integration_test/all_flows_test.dart}"
if [[ "$target" != *.dart ]]; then
  target="integration_test/flows/${target}_test.dart"
elif [[ "$target" != integration_test/* && "$target" != /* ]]; then
  target="integration_test/$target"
fi

E2E_WATCHDOG_SECONDS="${E2E_WATCHDOG_SECONDS:-1800}" exec bash integration_test/run_scripts_macos.sh "$target"
