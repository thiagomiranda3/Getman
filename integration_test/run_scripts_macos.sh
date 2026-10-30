#!/usr/bin/env bash
# macOS app sandbox reads corpus over a host-only fixture server.
set -euo pipefail
cd "$(dirname "$0")/.."
server_pid=''
foreground_pid=''
cleanup() {
  if [[ -n "$foreground_pid" ]]; then kill "$foreground_pid" 2>/dev/null || true; wait "$foreground_pid" 2>/dev/null || true; fi
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM
fixture_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
python3 integration_test/support/scripts_web_server.py "$fixture_port" &
server_pid=$!
for attempt in {1..50}; do
  if curl -fsS "http://127.0.0.1:$fixture_port/login" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
target="${1:-integration_test/scripts_flows_test.dart}"
if [[ $# -gt 0 ]]; then shift; fi
python3 integration_test/support/foreground_test_app.py "$PWD/build/macos/Build/Products/Debug/getman.app" &
foreground_pid=$!
python3 integration_test/support/run_with_watchdog.py fvm flutter test "$target" -d macos --no-pub --dart-define=E2E_SLOW_MS="${E2E_SLOW_MS:-0}" --dart-define="SCRIPT_FIXTURE_BASE_URL=http://127.0.0.1:$fixture_port" "$@"
