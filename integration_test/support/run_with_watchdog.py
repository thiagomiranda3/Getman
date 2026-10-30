"""Bound integration process lifetime independently of the JS runtime."""
import os
import signal
import subprocess
import sys

def interrupt(_signal, _frame):
    raise KeyboardInterrupt

signal.signal(signal.SIGTERM, interrupt)

process = subprocess.Popen(sys.argv[1:], start_new_session=True)
try:
    sys.exit(process.wait(timeout=int(os.environ.get("E2E_WATCHDOG_SECONDS", "240"))))
except (subprocess.TimeoutExpired, KeyboardInterrupt):
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    sys.exit(124)
