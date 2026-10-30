#!/usr/bin/env bash
# Fresh ChromeDriver session uses a disposable browser profile/origin.
set -euo pipefail
cd "$(dirname "$0")/.."
server_pid=''
driver_pid=''
harness_directory=''
web_index_backup=''
cleanup() {
  if [[ -n "$web_index_backup" ]]; then cp "$web_index_backup" web/index.html; fi
  if [[ -n "$harness_directory" ]]; then rm -rf "$harness_directory"; fi
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
  if [[ -n "$driver_pid" ]]; then kill "$driver_pid" 2>/dev/null || true; wait "$driver_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM
command -v chromedriver >/dev/null || { echo 'ChromeDriver is required on PATH.' >&2; exit 1; }
fixture_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
harness_directory=$(mktemp -d "${TMPDIR:-/tmp}/getman-scripts-web.XXXXXX")
web_index_backup="$harness_directory/index.html"
cp web/index.html "$web_index_backup"
python3 integration_test/support/prepare_scripts_web.py "$fixture_port" "$harness_directory"
python3 integration_test/support/scripts_web_server.py "$fixture_port" "$harness_directory" &
server_pid=$!
chromedriver --port=4444 &
driver_pid=$!
for attempt in {1..50}; do
  if curl -fsS http://127.0.0.1:4444/status >/dev/null 2>&1 && curl -fsS "http://127.0.0.1:$fixture_port/login" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
python3 integration_test/support/run_with_watchdog.py fvm flutter drive --no-pub --driver=test_driver/integration_test.dart --target=integration_test/web/scripts_web_test.dart -d web-server --browser-name=chrome --dart-define="SCRIPT_FIXTURE_BASE_URL=http://127.0.0.1:$fixture_port" --web-port=0 "$@"
